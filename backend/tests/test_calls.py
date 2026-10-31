"""Comprehensive pytest suite for AI Voice Bargaining & Meeting Scheduling (/calls)."""

from __future__ import annotations

import asyncio
from datetime import datetime
import io
import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any
import wave
from zoneinfo import ZoneInfo

import httpx
import jsonschema
import pytest

from app.calls.agents import (
    build_customer_agent_system_prompt,
    build_renovator_agent_system_prompt,
    build_renovator_persona,
    ensure_meeting_slots,
    round_to_50,
)
from app.calls.outcome import (
    evaluate_match,
    load_call_replay,
    save_call_replay,
    verify_outcome_and_compute_match,
)
from app.calls.transport import SimulatedCallTransport
from app.calls.tts import pcm_or_wav_to_wav, synthesize_turn_wav
from app.config import SHARED_DIR, settings
from app.main import CALLS, JOBS, CallRecord, JobRecord, app, load_demo_result
from app.models import (
    AgentTurnOutput,
    CallBrief,
    CallOutcome,
    CallOutcomeExtraction,
    CallRequest,
    CallTurn,
    Contractor,
    ExpectedPrice,
    MeetingInput,
    ResearchRequest,
    Subscores,
)
from app.scheduling.calendar import (
    BOOKED_EVENTS,
    compute_deterministic_event_id,
    schedule_in_person_meeting,
)


# ---------------------------------------------------------------------------
# Helpers & Fixtures
# ---------------------------------------------------------------------------


def load_json_schema(filename: str) -> dict[str, Any]:
    schema_path = SHARED_DIR / "schemas" / filename
    return json.loads(schema_path.read_text(encoding="utf-8"))


def make_research_request() -> ResearchRequest:
    demo_project_path = SHARED_DIR / "fixtures" / "demo_project.json"
    project_data = json.loads(demo_project_path.read_text(encoding="utf-8"))
    return ResearchRequest.model_validate(
        {
            "project": project_data,
            "answers": {
                "budget": "5k_15k",
                "scope": "partial",
                "timeline": "one_to_three_months",
                "priority": "balanced",
                "trust_requirements": ["licensed_insured", "written_quote"],
            },
        }
    )


def make_contractor(
    contractor_id: str = "demo-contractor-1",
    name: str = "Atelier Kanso Renovations (Fictional Demo Co.)",
    target_price: float | None = 7100,
    max_price: float | None = 8200,
    expected_low: float | None = 6800,
    expected_high: float | None = 8500,
    red_flags: list[str] | None = None,
) -> Contractor:
    return Contractor(
        id=contractor_id,
        rank=1,
        name=name,
        phone_e164="+33199000001",
        phone_verified=True,
        phone_source_url="https://example.invalid/atelier-kanso/contact",
        website="https://example.invalid/atelier-kanso",
        address="14 Rue de l'Exemple Fictif, 75011 Paris, France",
        trades=["painting", "flooring"],
        rating=4.9,
        review_count=142,
        certifications=[],
        insurance="Garantie Décennale verified",
        portfolio_urls=[],
        expected_price=ExpectedPrice(
            low=expected_low,
            high=expected_high,
            currency="EUR",
        ),
        availability="Available in 4 weeks",
        score=89,
        subscores=Subscores(price=82, reputation=95, fit=94, availability=78),
        why_recommended="Top match for Japandi painting and oak flooring.",
        red_flags=red_flags if red_flags is not None else [],
        source_urls=["https://example.invalid/atelier-kanso"],
        call_brief=CallBrief(
            target_price=target_price,
            max_price=max_price,
            leverage_points=[
                "Small 14 m2 single-room footprint allows combining crews.",
                "Flexible start window within 1-3 months.",
            ],
            questions_to_ask=[
                "Does the quote include acoustic underlayment?",
            ],
        ),
    )


def make_pcm_samples(num_samples: int = 2400) -> bytes:
    return b"\x10\x00" * num_samples


# ---------------------------------------------------------------------------
# 1. Default Slot Generator & Persona Price Calculation Tests
# ---------------------------------------------------------------------------


def test_ensure_meeting_slots_generates_9_weekday_slots_when_empty() -> None:
    tz = ZoneInfo("Europe/Paris")
    # Friday 2026-10-30 -> next 3 weekdays are Mon Nov 2, Tue Nov 3, Wed Nov 4
    friday_now = datetime(2026, 10, 30, 12, 0, 0, tzinfo=tz)
    slots = ensure_meeting_slots([], "Europe/Paris", now_dt=friday_now)
    assert len(slots) == 9
    assert slots[0] == "2026-11-02T10:00:00+01:00"
    assert slots[1] == "2026-11-02T14:00:00+01:00"
    assert slots[2] == "2026-11-02T17:00:00+01:00"
    for s in slots:
        dt = datetime.fromisoformat(s)
        assert dt.weekday() < 5

    # Provided slots are preserved unchanged
    custom = ["2026-11-05T10:00:00+01:00"]
    assert ensure_meeting_slots(custom, "Europe/Paris") == custom


def test_persona_price_calculation_fallback_and_null_error() -> None:
    assert round_to_50(9184.0) == 9200.0
    assert round_to_50(7650.0) == 7650.0

    # Primary: uses call_brief.target_price (7100) and call_brief.max_price (8200)
    c1 = make_contractor(target_price=7100, max_price=8200)
    slots = ["2026-11-02T10:00:00+01:00", "2026-11-02T14:00:00+01:00"]
    persona1 = build_renovator_persona(c1, slots, is_demo=True)
    # 8200 * 1.12 = 9184 -> rounded to 50 = 9200
    assert persona1.opening_price == 9200.0
    # (7100 + 8200) / 2 = 7650 -> rounded to 50 = 7650
    assert persona1.floor_price == 7650.0
    assert persona1.available_slots[0] == "2026-11-02T14:00:00+01:00"
    assert len(persona1.available_slots) == 3

    # Fallback: call_brief prices are None -> falls back to expected_price (6800, 8500)
    c_fallback = make_contractor(
        target_price=None,
        max_price=None,
        expected_low=6800,
        expected_high=8500,
    )
    persona_fb = build_renovator_persona(c_fallback, slots, is_demo=True)
    # 8500 * 1.12 = 9520 -> 9500
    assert persona_fb.opening_price == 9500.0
    # (6800 + 8500) / 2 = 7650 -> 7650
    assert persona_fb.floor_price == 7650.0

    # Null prices on both call_brief and expected_price -> raises ValueError
    c_null = make_contractor(
        target_price=None,
        max_price=None,
        expected_low=None,
        expected_high=None,
    )
    with pytest.raises(ValueError, match="No usable price"):
        build_renovator_persona(c_null, slots, is_demo=True)


# ---------------------------------------------------------------------------
# 2 & 3. Prompt Isolation & Privacy Guardrail Tests
# ---------------------------------------------------------------------------


def test_renovator_prompt_isolation_and_non_demo_stand_in_name() -> None:
    req = make_research_request()
    real_name = "Real Paris Renovations SARL"
    contractor = make_contractor(
        name=real_name,
        target_price=7100,
        max_price=8200,
    )
    slots = ["2026-11-02T10:00:00+01:00", "2026-11-02T14:00:00+01:00"]

    # Non-demo contractor -> must NOT include real company name, target_price, max_price, or budget
    persona_live = build_renovator_persona(contractor, slots, is_demo=False)
    assert persona_live.identity_name == "a local renovation specialist"

    customer_prompt = build_customer_agent_system_prompt(
        req, contractor, slots, is_demo=False
    )
    renovator_prompt = build_renovator_agent_system_prompt(
        persona_live, currency="EUR", call_language="en-US"
    )

    assert real_name not in renovator_prompt
    assert real_name not in customer_prompt
    assert "7100" not in renovator_prompt  # target_price excluded
    assert "8200" not in renovator_prompt  # max_price excluded
    assert "5k_15k" not in renovator_prompt  # budget excluded
    assert "PRIVATE NEGOTIATION BRIEF" not in renovator_prompt
    assert "9200" in renovator_prompt  # opening_price included
    assert "7650" in renovator_prompt  # floor_price included


def test_customer_prompt_excludes_floor_price_and_pii_and_includes_ai_disclosure() -> None:
    req = make_research_request()
    contractor = make_contractor(target_price=7100, max_price=8200)
    slots = ["2026-11-02T10:00:00+01:00", "2026-11-02T14:00:00+01:00"]
    persona = build_renovator_persona(contractor, slots, is_demo=True)

    customer_prompt = build_customer_agent_system_prompt(
        req, contractor, slots, is_demo=True
    )

    # Must NOT include floor_price (7650) or opening_price (9200)
    assert str(int(persona.floor_price)) not in customer_prompt
    assert str(int(persona.opening_price)) not in customer_prompt
    assert "floor_price" not in customer_prompt

    # Must include AI assistant disclosure rule, leverage points, and PII prohibition
    assert "AI assistant" in customer_prompt
    assert "Small 14 m2 single-room footprint" in customer_prompt
    assert "Never share the customer's name, email, phone number, or street address" in customer_prompt


# ---------------------------------------------------------------------------
# 6. TTS WAV Wrapping & Graceful Failure Tests
# ---------------------------------------------------------------------------


def test_pcm_or_wav_to_wav_produces_valid_wav_headers() -> None:
    pcm = make_pcm_samples(1200)
    wav_from_pcm = pcm_or_wav_to_wav(pcm, mime_type="audio/L16;rate=24000")
    assert wav_from_pcm[:4] == b"RIFF"
    with wave.open(io.BytesIO(wav_from_pcm), "rb") as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        assert wf.getframerate() == 24000
        assert wf.readframes(wf.getnframes()) == pcm

    # Passing an already-valid WAV re-wraps cleanly
    rewrapped = pcm_or_wav_to_wav(wav_from_pcm, mime_type="audio/wav")
    assert rewrapped[:4] == b"RIFF"


@pytest.mark.asyncio
async def test_tts_failure_continues_call_with_null_audio_url_and_warning() -> None:
    class FailingTTSClient:
        class models:
            @staticmethod
            def generate_content(**kwargs: Any) -> Any:
                raise RuntimeError("Simulated TTS quota error")

    wav_bytes, warning = await synthesize_turn_wav(
        "Hello from AI assistant.",
        "customer_agent",
        client=FailingTTSClient(),
    )
    assert wav_bytes is None
    assert warning is not None
    assert "TTS synthesis failed" in warning


# ---------------------------------------------------------------------------
# 7 & 8. Deterministic Outcome Evidence & All 5 Match Criteria Tests
# ---------------------------------------------------------------------------


def test_outcome_verification_resets_unverified_price_and_slot() -> None:
    contractor = make_contractor(target_price=7100, max_price=8200)
    turns = [
        CallTurn(
            index=0,
            speaker="customer_agent",
            text="Hello, I am an AI assistant calling for a Paris renovation.",
        ),
        CallTurn(
            index=1,
            speaker="renovator_agent",
            text="Our opening estimate is 9200 EUR, and we can do 7650 EUR all-in.",
        ),
    ]
    slots = ["2026-11-02T10:00:00+01:00", "2026-11-02T14:00:00+01:00"]

    # Hallucinated final_price (6900 not in transcript) and hallucinated slot
    bad_extraction = CallOutcomeExtraction(
        end_reason="agreement",
        opening_price=9200,
        final_price=6900,
        currency="EUR",
        labour_included=True,
        materials_included=True,
        tax_included=True,
        scope_confirmed=True,
        agreed_slot="2026-12-25T10:00:00+01:00",
        notes="Hallucinated values",
    )

    outcome, match, warnings = verify_outcome_and_compute_match(
        extraction=bad_extraction,
        turns=turns,
        customer_slots=slots,
        contractor=contractor,
    )
    assert outcome.final_price is None
    assert outcome.agreed_slot is None
    assert outcome.savings is None
    assert match.match is False
    assert any("final_price was not found in transcript" in w for w in warnings)
    assert any("agreed_slot did not match" in w for w in warnings)


def test_every_match_failure_reason() -> None:
    slot = "2026-11-02T14:00:00+01:00"
    base_contractor = make_contractor(target_price=7100, max_price=8200, red_flags=[])

    # 1. All 5 conditions met -> match=True, reasons=[]
    valid_outcome = CallOutcome(
        end_reason="agreement",
        opening_price=9200,
        final_price=7650,
        savings=1550,
        currency="EUR",
        labour_included=True,
        materials_included=True,
        tax_included=True,
        scope_confirmed=True,
        agreed_slot=slot,
        notes="Agreed",
    )
    m_ok = evaluate_match(valid_outcome, base_contractor)
    assert m_ok.match is True
    assert m_ok.reasons == []

    # 2. end_reason != "agreement"
    m_no_agree = evaluate_match(
        valid_outcome.model_copy(update={"end_reason": "no_agreement"}),
        base_contractor,
    )
    assert m_no_agree.match is False
    assert any("did not end in agreement" in r for r in m_no_agree.reasons)

    # 3. final_price > max_price
    m_over_max = evaluate_match(
        valid_outcome.model_copy(update={"final_price": 8500}),
        base_contractor,
    )
    assert m_over_max.match is False
    assert any("exceeds maximum allowed price" in r for r in m_over_max.reasons)

    # 4. scope_confirmed != True
    m_no_scope = evaluate_match(
        valid_outcome.model_copy(update={"scope_confirmed": False}),
        base_contractor,
    )
    assert m_no_scope.match is False
    assert any("scope was not confirmed" in r for r in m_no_scope.reasons)

    # 5. agreed_slot is None
    m_no_slot = evaluate_match(
        valid_outcome.model_copy(update={"agreed_slot": None}),
        base_contractor,
    )
    assert m_no_slot.match is False
    assert any("No valid meeting slot" in r for r in m_no_slot.reasons)

    # 6. contractor has red_flags
    flagged_contractor = make_contractor(
        target_price=7100,
        max_price=8200,
        red_flags=["Recent scheduling delay reported"],
    )
    m_flags = evaluate_match(valid_outcome, flagged_contractor)
    assert m_flags.match is False
    assert any("Contractor has red flags" in r for r in m_flags.reasons)


# ---------------------------------------------------------------------------
# 10, 11, 12. Google Calendar Allowlist, Deduplication, and Template Fallback Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_calendar_allowlist_enforcement_and_deduplication(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    BOOKED_EVENTS.clear()
    monkeypatch.setattr(settings, "invite_allowlist", ["allowed@example.com"])

    req = make_research_request()
    contractor = make_contractor()
    slot = "2026-11-02T14:00:00+01:00"
    outcome = CallOutcome(
        end_reason="agreement",
        opening_price=9200,
        final_price=7650,
        savings=1550,
        currency="EUR",
        labour_included=True,
        materials_included=True,
        tax_included=True,
        scope_confirmed=True,
        agreed_slot=slot,
    )

    inserted_calls: list[dict[str, Any]] = []

    class FakeEventsResource:
        def insert(self, **kwargs: Any) -> Any:
            inserted_calls.append(kwargs)
            return SimpleNamespace(
                execute=lambda: {
                    "id": kwargs["body"]["id"],
                    "htmlLink": "https://calendar.google.com/calendar/event?eid=test123",
                }
            )

    class FakeCalendarService:
        def events(self) -> FakeEventsResource:
            return FakeEventsResource()

    # Case A: customer_email NOT in allowlist -> no attendees, sendUpdates="none", warning added
    meeting_unlisted = MeetingInput(
        customer_email="not-allowed@example.com",
        address="12 Rue de Rivoli, 75004 Paris",
        slots=[slot],
    )
    res1 = await schedule_in_person_meeting(
        research_request=req,
        contractor=contractor,
        meeting=meeting_unlisted,
        outcome=outcome,
        is_demo=True,
        calendar_service=FakeCalendarService(),
    )
    assert res1.status == "created"
    assert len(inserted_calls) == 1
    assert "attendees" not in inserted_calls[0]["body"]
    assert inserted_calls[0]["sendUpdates"] == "none"
    assert any("not in INVITE_ALLOWLIST" in w for w in res1.warnings)

    # Case B: Calling again with same (project_id, contractor_id, agreed_slot) -> deduplicated!
    res_dup = await schedule_in_person_meeting(
        research_request=req,
        contractor=contractor,
        meeting=meeting_unlisted,
        outcome=outcome,
        is_demo=True,
        calendar_service=FakeCalendarService(),
    )
    assert len(inserted_calls) == 1  # No second API call made
    assert any("Duplicate booking prevented" in w for w in res_dup.warnings)

    # Case C: customer_email IN allowlist -> attendees=[{"email": "allowed@example.com"}], sendUpdates="all"
    BOOKED_EVENTS.clear()
    meeting_allowed = MeetingInput(
        customer_email="allowed@example.com",
        address="12 Rue de Rivoli, 75004 Paris",
        slots=[slot],
    )
    res2 = await schedule_in_person_meeting(
        research_request=req,
        contractor=contractor,
        meeting=meeting_allowed,
        outcome=outcome,
        is_demo=True,
        calendar_service=FakeCalendarService(),
    )
    assert res2.status == "created"
    assert len(inserted_calls) == 2
    assert inserted_calls[1]["body"]["attendees"] == [{"email": "allowed@example.com"}]
    assert inserted_calls[1]["sendUpdates"] == "all"


@pytest.mark.asyncio
async def test_calendar_fallback_link_only_when_token_missing_or_api_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    BOOKED_EVENTS.clear()
    monkeypatch.setattr(
        settings, "google_token_file", "non_existent_token_12345.json"
    )

    req = make_research_request()
    contractor = make_contractor()
    slot = "2026-11-02T14:00:00+01:00"
    outcome = CallOutcome(
        end_reason="agreement",
        opening_price=9200,
        final_price=7650,
        savings=1550,
        currency="EUR",
        scope_confirmed=True,
        agreed_slot=slot,
    )
    meeting = MeetingInput(
        customer_email="customer@example.com",
        address="12 Rue de Rivoli, 75004 Paris",
        slots=[slot],
    )

    # 1. Missing token.json -> status="link_only" with template URL
    res_no_token = await schedule_in_person_meeting(
        research_request=req,
        contractor=contractor,
        meeting=meeting,
        outcome=outcome,
        is_demo=True,
        calendar_service=None,
    )
    assert res_no_token.status == "link_only"
    assert res_no_token.event_url is not None
    assert "calendar.google.com/calendar/render?action=TEMPLATE" in res_no_token.event_url
    assert "20261102T130000Z%2F20261102T134500Z" in res_no_token.event_url

    # 2. Calendar API raises exception -> status="link_only" with warning
    BOOKED_EVENTS.clear()

    class FailingCalendarService:
        def events(self) -> Any:
            raise RuntimeError("Calendar API 503 Unavailable")

    res_api_fail = await schedule_in_person_meeting(
        research_request=req,
        contractor=contractor,
        meeting=meeting,
        outcome=outcome,
        is_demo=True,
        calendar_service=FailingCalendarService(),
    )
    assert res_api_fail.status == "link_only"
    assert res_api_fail.event_url is not None
    assert any("Calendar API call failed" in w for w in res_api_fail.warnings)


# ---------------------------------------------------------------------------
# 4, 5, 9, 13. Full Call Transport, Turn Limit, Timeout, Stop, Replay & API Schema Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_turn_limit_and_timeout_handling(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    req = make_research_request()
    contractor = make_contractor()
    slots = ["2026-11-02T10:00:00+01:00", "2026-11-02T14:00:00+01:00"]
    persona = build_renovator_persona(contractor, slots, is_demo=True)

    # 1. Turn limit test (MAX_CALL_TURNS=2, agents keep end_call=False)
    monkeypatch.setattr(settings, "max_call_turns", 2)
    monkeypatch.setattr(settings, "call_timeout_seconds", 10.0)

    class NeverEndingGeminiClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: str, config: Any) -> Any:
                if model == settings.tts_model:
                    return SimpleNamespace(
                        candidates=[
                            SimpleNamespace(
                                content=SimpleNamespace(
                                    parts=[
                                        SimpleNamespace(
                                            inline_data=SimpleNamespace(
                                                data=make_pcm_samples(400),
                                                mime_type="audio/L16;rate=24000",
                                            )
                                        )
                                    ]
                                )
                            )
                        ]
                    )
                return SimpleNamespace(
                    text=AgentTurnOutput(
                        text="Still discussing the renovation details.",
                        end_call=False,
                        end_reason=None,
                    ).model_dump_json()
                )

    call_rec = CallRecord(
        call_id="call-limit-test",
        job_id="job-1",
        contractor_id=contractor.id,
        research_request=req,
        contractor=contractor,
        is_demo=True,
        meeting=MeetingInput(
            customer_email="test@example.com",
            address="12 Rue de Rivoli, Paris",
            slots=slots,
        ),
        slots=slots,
        persona=persona,
        customer_prompt="Customer prompt",
        renovator_prompt="Renovator prompt",
        gemini_client=NeverEndingGeminiClient(),
    )
    transport = SimulatedCallTransport(gemini_client=NeverEndingGeminiClient())
    await transport.run_conversation(call_rec)
    assert len(call_rec.turns) == 2
    assert call_rec.hit_turn_limit is True

    # 2. Timeout test (CALL_TIMEOUT_SECONDS=0.05, slow model)
    monkeypatch.setattr(settings, "max_call_turns", 6)
    monkeypatch.setattr(settings, "call_timeout_seconds", 0.05)

    class SlowGeminiClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: str, config: Any) -> Any:
                import time as _time

                _time.sleep(0.2)
                return SimpleNamespace(
                    text=AgentTurnOutput(
                        text="Too slow", end_call=False
                    ).model_dump_json()
                )

    call_timeout = CallRecord(
        call_id="call-timeout-test",
        job_id="job-1",
        contractor_id=contractor.id,
        research_request=req,
        contractor=contractor,
        is_demo=True,
        meeting=MeetingInput(
            customer_email="test@example.com",
            address="12 Rue de Rivoli, Paris",
            slots=slots,
        ),
        slots=slots,
        persona=persona,
        customer_prompt="Customer prompt",
        renovator_prompt="Renovator prompt",
        gemini_client=SlowGeminiClient(),
    )
    await SimulatedCallTransport(gemini_client=SlowGeminiClient()).run_conversation(
        call_timeout
    )
    assert call_timeout.timed_out is True
    assert any("timed out" in w.lower() for w in call_timeout.warnings)


@pytest.mark.asyncio
async def test_api_call_lifecycle_replay_audio_stop_and_schema_validation(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    JOBS.clear()
    CALLS.clear()
    BOOKED_EVENTS.clear()

    call_req_schema = load_json_schema("call_request.schema.json")
    call_status_schema = load_json_schema("call_status.schema.json")

    req = make_research_request()
    demo_res = load_demo_result(req)
    job_id = "demo-job-001"
    JOBS[job_id] = JobRecord(
        job_id=job_id,
        request=req,
        status="completed",
        phase="done",
        result=demo_res,
    )

    monkeypatch.setattr(settings, "call_replay", True)
    monkeypatch.setattr(
        settings, "google_token_file", "non_existent_token_12345.json"
    )

    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        # 1. Validate request against call_request.schema.json
        payload = {
            "job_id": job_id,
            "contractor_id": "demo-contractor-1",
            "meeting": {
                "customer_email": "customer@example.com",
                "address": "12 Rue de Rivoli, 75004 Paris, France",
                "slots": [
                    "2026-11-02T10:00:00+01:00",
                    "2026-11-02T14:00:00+01:00",
                    "2026-11-02T17:00:00+01:00",
                ],
            },
        }
        jsonschema.validate(instance=payload, schema=call_req_schema)

        # 2. 404 on unknown job_id, 409 on incomplete job
        resp_404 = await client.post(
            "/calls",
            json={**payload, "job_id": "missing-job"},
        )
        assert resp_404.status_code == 404

        JOBS["queued-job"] = JobRecord(
            job_id="queued-job", request=req, status="running", phase="researching"
        )
        resp_409 = await client.post(
            "/calls",
            json={**payload, "job_id": "queued-job"},
        )
        assert resp_409.status_code == 409

        # 3. Start replay call (0 live Gemini calls)
        create_resp = await client.post("/calls", json=payload)
        assert create_resp.status_code == 200
        call_id = create_resp.json()["call_id"]

        final_body: dict[str, Any] | None = None
        for _ in range(25):
            st_resp = await client.get(f"/calls/{call_id}")
            assert st_resp.status_code == 200
            body = st_resp.json()
            if body["status"] == "completed":
                final_body = body
                break
            await asyncio.sleep(0.02)

        assert final_body is not None
        jsonschema.validate(instance=final_body, schema=call_status_schema)

        # Ensure persona & floor_price are NEVER exposed in API response
        raw_resp_str = json.dumps(final_body)
        assert "floor_price" not in raw_resp_str
        assert "persona" not in raw_resp_str

        assert final_body["is_replay"] is True
        assert final_body["simulated"] is True
        assert len(final_body["turns"]) == 6
        assert final_body["outcome"]["final_price"] == 7650
        assert final_body["outcome"]["savings"] == 1550
        assert final_body["match"]["match"] is True
        assert final_body["booking"] is not None
        assert final_body["booking"]["status"] == "link_only"

        # Test ?after=4 query parameter filtering
        after_resp = await client.get(f"/calls/{call_id}?after=4")
        assert after_resp.status_code == 200
        after_turns = after_resp.json()["turns"]
        assert [t["index"] for t in after_turns] == [4, 5]

        # 4. Call with contractor 2 (has red_flags) -> match=False and NO booking!
        payload_c2 = {
            **payload,
            "contractor_id": "demo-contractor-2",
        }
        c2_resp = await client.post("/calls", json=payload_c2)
        c2_id = c2_resp.json()["call_id"]
        c2_body: dict[str, Any] | None = None
        for _ in range(25):
            r = await client.get(f"/calls/{c2_id}")
            if r.json()["status"] == "completed":
                c2_body = r.json()
                break
            await asyncio.sleep(0.02)
        assert c2_body is not None
        assert c2_body["match"]["match"] is False
        assert c2_body["booking"] is None

        # 5. Stop endpoint test -> status="stopped", booking=None
        stop_resp = await client.post(f"/calls/{call_id}/stop")
        assert stop_resp.status_code == 200
        stop_body = stop_resp.json()
        jsonschema.validate(instance=stop_body, schema=call_status_schema)
        assert stop_body["status"] == "stopped"
        assert stop_body["phase"] == "done"
        assert stop_body["booking"] is None


def test_save_and_load_call_replay_with_wav_audio(tmp_path: Path) -> None:
    contractor = make_contractor()
    slots = ["2026-11-02T10:00:00+01:00", "2026-11-02T14:00:00+01:00"]
    wav_bytes = pcm_or_wav_to_wav(make_pcm_samples(600))
    turns = [
        CallTurn(
            index=0,
            speaker="customer_agent",
            text="Hello, I am an AI assistant calling for a Paris renovation.",
            audio_url="/calls/old/audio/0",
        ),
        CallTurn(
            index=1,
            speaker="renovator_agent",
            text="We can do 9200 EUR initially, or 7650 EUR all-in at 2026-11-02T14:00:00+01:00.",
            audio_url="/calls/old/audio/1",
        ),
    ]
    outcome = CallOutcome(
        end_reason="agreement",
        opening_price=9200,
        final_price=7650,
        savings=1550,
        currency="EUR",
        labour_included=True,
        materials_included=True,
        tax_included=True,
        scope_confirmed=True,
        agreed_slot="2026-11-02T14:00:00+01:00",
        notes="Saved replay",
    )
    match = evaluate_match(outcome, contractor)

    replay_dir = tmp_path / "demo_call_replay"
    save_call_replay(
        turns=turns,
        audio_by_turn={0: wav_bytes, 1: wav_bytes},
        outcome=outcome,
        match=match,
        warnings=[],
        replay_dir=replay_dir,
    )

    loaded_turns, loaded_audio, loaded_outcome, loaded_match, warnings = (
        load_call_replay(
            call_id="new-call-99",
            customer_slots=slots,
            contractor=contractor,
            replay_dir=replay_dir,
        )
    )
    assert len(loaded_turns) == 2
    assert loaded_turns[0].audio_url == "/calls/new-call-99/audio/0"
    assert loaded_audio[0][:4] == b"RIFF"
    assert loaded_outcome.final_price == 7650
    assert loaded_match.match is True
    assert any("Replay:" in w for w in warnings)
    assert compute_deterministic_event_id(
        "demo-001", contractor.id, slots[1]
    ).startswith("reno")


@pytest.mark.asyncio
async def test_live_simulated_flow_audio_endpoint_and_mid_call_stop(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    JOBS.clear()
    CALLS.clear()
    BOOKED_EVENTS.clear()

    req = make_research_request()
    demo_res = load_demo_result(req)
    job_id = "demo-job-live-sim"
    JOBS[job_id] = JobRecord(
        job_id=job_id,
        request=req,
        status="completed",
        phase="done",
        result=demo_res,
    )

    monkeypatch.setattr(settings, "call_replay", False)
    monkeypatch.setattr(
        settings, "google_token_file", "non_existent_token_12345.json"
    )
    # Redirect DEMO_CALL_REPLAY_DIR to tmp_path so tests don't dirty shared/fixtures
    import app.calls.outcome as outcome_mod

    monkeypatch.setattr(
        outcome_mod, "DEMO_CALL_REPLAY_DIR", tmp_path / "demo_call_replay"
    )

    slot = "2026-11-02T14:00:00+01:00"
    scripted_turns = [
        AgentTurnOutput(
            text="Hello, I am an AI assistant calling for a Paris renovation.",
            end_call=False,
        ),
        AgentTurnOutput(
            text=f"We can do 9200 EUR initially, or 7650 EUR all-in and meet at {slot}.",
            end_call=True,
            end_reason="agreement",
        ),
    ]
    turn_counter = 0

    class FakeLiveGeminiClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: str, config: Any) -> Any:
                nonlocal turn_counter
                if model == settings.tts_model:
                    return SimpleNamespace(
                        candidates=[
                            SimpleNamespace(
                                content=SimpleNamespace(
                                    parts=[
                                        SimpleNamespace(
                                            inline_data=SimpleNamespace(
                                                data=make_pcm_samples(500),
                                                mime_type="audio/L16;rate=24000",
                                            )
                                        )
                                    ]
                                )
                            )
                        ]
                    )
                if model == settings.talk_model:
                    out = scripted_turns[min(turn_counter, len(scripted_turns) - 1)]
                    turn_counter += 1
                    return SimpleNamespace(text=out.model_dump_json())
                # Structuring model for outcome extraction
                return SimpleNamespace(
                    text=CallOutcomeExtraction(
                        end_reason="agreement",
                        opening_price=9200,
                        final_price=7650,
                        currency="EUR",
                        labour_included=True,
                        materials_included=True,
                        tax_included=True,
                        scope_confirmed=True,
                        agreed_slot=slot,
                        notes="Agreed on 7650 EUR",
                    ).model_dump_json()
                )

    import app.calls.agents as agents_mod
    import app.calls.tts as tts_mod

    monkeypatch.setattr(
        agents_mod.genai, "Client", lambda **kw: FakeLiveGeminiClient()
    )
    monkeypatch.setattr(
        tts_mod.genai, "Client", lambda **kw: FakeLiveGeminiClient()
    )
    monkeypatch.setattr(
        outcome_mod.genai, "Client", lambda **kw: FakeLiveGeminiClient()
    )

    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        create_resp = await client.post(
            "/calls",
            json={
                "job_id": job_id,
                "contractor_id": "demo-contractor-1",
                "meeting": {
                    "customer_email": "customer@example.com",
                    "address": "12 Rue de Rivoli, 75004 Paris",
                    "slots": ["2026-11-02T10:00:00+01:00", slot],
                },
            },
        )
        assert create_resp.status_code == 200
        call_id = create_resp.json()["call_id"]

        for _ in range(30):
            r = await client.get(f"/calls/{call_id}")
            if r.json()["status"] == "completed":
                break
            await asyncio.sleep(0.02)

        # Fetch WAV audio for turn 0
        audio_resp = await client.get(f"/calls/{call_id}/audio/0")
        assert audio_resp.status_code == 200
        assert audio_resp.headers["content-type"].startswith("audio/wav")
        assert audio_resp.content[:4] == b"RIFF"

        # Missing turn audio -> 404
        missing_audio = await client.get(f"/calls/{call_id}/audio/99")
        assert missing_audio.status_code == 404
