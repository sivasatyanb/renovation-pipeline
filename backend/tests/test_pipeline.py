"""Comprehensive pytest suite for the Automated Home-Renovation Pipeline backend."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import httpx
import jsonschema
import pytest
from pydantic import ValidationError

from app.config import SHARED_DIR, settings
from app.main import JOBS, app
from app.models import (
    CallBrief,
    Certification,
    ExpectedPrice,
    ExtractedContractor,
    PriceEstimate,
    PriceLineItem,
    ResearchRequest,
    StructuringExtraction,
    Subscores,
)
from app.pipeline.researcher import (
    build_research_prompt,
    extract_interaction_report_text,
    run_deep_research,
)
from app.pipeline.structurer import StructuringError, structure_research_report
from app.pipeline.verifier import (
    compute_score,
    normalize_phone_e164,
    normalize_website_url,
    verify_and_rank_contractors,
    verify_phone_on_page,
)


# ---------------------------------------------------------------------------
# Helpers & Fixtures
# ---------------------------------------------------------------------------


def load_json_schema(filename: str) -> dict[str, Any]:
    schema_path = SHARED_DIR / "schemas" / filename
    return json.loads(schema_path.read_text(encoding="utf-8"))


def make_valid_request_payload(priority: str = "balanced") -> dict[str, Any]:
    demo_project_path = SHARED_DIR / "fixtures" / "demo_project.json"
    project_data = json.loads(demo_project_path.read_text(encoding="utf-8"))
    return {
        "project": project_data,
        "answers": {
            "budget": "5k_15k",
            "scope": "partial",
            "timeline": "one_to_three_months",
            "priority": priority,
            "trust_requirements": ["licensed_insured", "written_quote"],
        },
    }


def make_extracted_contractor(
    name: str = "Atelier Test",
    phone_raw: str | None = "01 42 68 55 00",
    phone_source_url: str | None = "https://atelier-test.fr/contact",
    website: str | None = "https://www.atelier-test.fr/",
    trades: list[str] | None = None,
    is_closed: bool = False,
    business_status: str | None = "active",
    covers_scope: bool = True,
    price_sub: float = 80,
    rep_sub: float = 85,
    fit_sub: float = 90,
    avail_sub: float = 75,
) -> ExtractedContractor:
    return ExtractedContractor(
        name=name,
        phone_raw=phone_raw,
        phone_source_url=phone_source_url,
        website=website,
        address="10 Rue de Rivoli, 75001 Paris",
        is_closed=is_closed,
        business_status=business_status,
        covers_scope=covers_scope,
        trades=trades if trades is not None else ["painting", "flooring"],
        rating=4.8,
        review_count=52,
        certifications=[
            Certification(
                name="Qualibat RGE",
                source_url="https://qualibat.example/atelier-test",
            )
        ],
        insurance="Garantie Décennale verified",
        portfolio_urls=["https://atelier-test.fr/portfolio"],
        expected_price=ExpectedPrice(low=6500, high=8200, currency="EUR"),
        availability="Available in 4 weeks",
        subscores=Subscores(
            price=price_sub,
            reputation=rep_sub,
            fit=fit_sub,
            availability=avail_sub,
        ),
        why_recommended="Covers both painting and oak flooring with strong reviews.",
        red_flags=[],
        source_urls=["https://atelier-test.fr/contact"],
        call_brief=CallBrief(
            target_price=6800,
            max_price=7900,
            leverage_points=["Single room 14 m2 layout"],
            questions_to_ask=["Is underlayment included?"],
        ),
    )


def make_price_estimate() -> PriceEstimate:
    return PriceEstimate(
        low=6000,
        high=9000,
        currency="EUR",
        line_items=[
            PriceLineItem(label="Painting (38 m2)", low=2000, high=3000),
            PriceLineItem(label="Oak flooring (14 m2)", low=4000, high=6000),
        ],
        source_urls=["https://pricing.example/paris"],
    )


# ---------------------------------------------------------------------------
# 1. Answer & Request Validation Tests
# ---------------------------------------------------------------------------


def test_valid_research_request_passes_and_matches_schema() -> None:
    payload = make_valid_request_payload()
    req_schema = load_json_schema("research_request.schema.json")
    jsonschema.validate(instance=payload, schema=req_schema)

    parsed = ResearchRequest.model_validate(payload)
    assert parsed.project.client.city == "Paris"
    assert parsed.answers.budget == "5k_15k"
    assert parsed.answers.trust_requirements == ["licensed_insured", "written_quote"]


@pytest.mark.parametrize(
    "field_name,invalid_value",
    [
        ("budget", "million_dollars"),
        ("scope", "demolish_building"),
        ("timeline", "yesterday"),
        ("priority", "fastest_cheapest"),
        ("trust_requirements", []),
        ("trust_requirements", ["invalid_trust_flag"]),
        ("trust_requirements", ["licensed_insured", "licensed_insured"]),
    ],
)
def test_invalid_quiz_answers_fail_validation(
    field_name: str, invalid_value: Any
) -> None:
    payload = make_valid_request_payload()
    payload["answers"][field_name] = invalid_value
    with pytest.raises(ValidationError):
        ResearchRequest.model_validate(payload)


# ---------------------------------------------------------------------------
# 2. Phone Normalisation Tests
# ---------------------------------------------------------------------------


def test_phone_normalisation_french_uk_e164_and_invalid() -> None:
    # French national format -> E.164
    assert normalize_phone_e164("01 42 68 55 00", "France") == "+33142685500"
    assert normalize_phone_e164("01.42.68.55.00", "FR") == "+33142685500"

    # UK national format -> E.164
    assert normalize_phone_e164("020 7946 0921", "UK") == "+442079460921"
    assert normalize_phone_e164("020 7946 0921", "United Kingdom") == "+442079460921"

    # Already E.164
    assert normalize_phone_e164("+33142685500", "France") == "+33142685500"
    assert normalize_phone_e164("+442079460921", "United Kingdom") == "+442079460921"

    # Invalid / unconfirmed strings -> None
    assert normalize_phone_e164("not found", "France") is None
    assert normalize_phone_e164("123", "France") is None
    assert normalize_phone_e164("", "France") is None
    assert normalize_phone_e164(None, "France") is None


# ---------------------------------------------------------------------------
# 3. Phone Verification Tests (Mocked httpx)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_phone_verification_matches_formatted_numbers() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "intl-format" in url:
            return httpx.Response(
                200,
                text="<html><body>Contactez-nous au +33 1 42 68 55 00</body></html>",
            )
        if "dots-format" in url:
            return httpx.Response(
                200,
                text="<html><body>Tél : 01.42.68.55.00 - Paris</body></html>",
            )
        if "wrong-digits" in url:
            return httpx.Response(
                200,
                text="<html><body>Tél : 01 99 88 77 66</body></html>",
            )
        if "server-error" in url:
            return httpx.Response(500, text="Internal Server Error")
        raise httpx.ConnectTimeout("Simulated timeout")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as mock_client:
        assert (
            await verify_phone_on_page(
                "+33142685500",
                "https://atelier.example/intl-format",
                http_client=mock_client,
            )
            is True
        )
        assert (
            await verify_phone_on_page(
                "+33142685500",
                "https://atelier.example/dots-format",
                http_client=mock_client,
            )
            is True
        )
        assert (
            await verify_phone_on_page(
                "+33142685500",
                "https://atelier.example/wrong-digits",
                http_client=mock_client,
            )
            is False
        )
        assert (
            await verify_phone_on_page(
                "+33142685500",
                "https://atelier.example/server-error",
                http_client=mock_client,
            )
            is False
        )
        assert (
            await verify_phone_on_page(
                "+33142685500",
                "https://atelier.example/timeout",
                http_client=mock_client,
            )
            is False
        )
        assert await verify_phone_on_page("+33142685500", None, http_client=mock_client) is False


# ---------------------------------------------------------------------------
# 4. Deterministic Ranking & Filtering Tests
# ---------------------------------------------------------------------------


def test_deterministic_priority_weight_formulas() -> None:
    subscores = Subscores(price=100, reputation=60, fit=40, availability=80)

    # lowest_price: 0.45*100 + 0.25*60 + 0.20*40 + 0.10*80 = 45 + 15 + 8 + 8 = 76
    assert compute_score(subscores, "lowest_price") == 76

    # balanced: 0.30*100 + 0.30*60 + 0.30*40 + 0.10*80 = 30 + 18 + 12 + 8 = 68
    assert compute_score(subscores, "balanced") == 68

    # quality: 0.10*100 + 0.45*60 + 0.35*40 + 0.10*80 = 10 + 27 + 14 + 8 = 59
    assert compute_score(subscores, "quality") == 59

    # design_match: 0.10*100 + 0.25*60 + 0.55*40 + 0.10*80 = 10 + 15 + 22 + 8 = 55
    assert compute_score(subscores, "design_match") == 55


@pytest.mark.asyncio
async def test_filtering_and_verified_first_sorting_and_under_five_warning() -> None:
    request = ResearchRequest.model_validate(make_valid_request_payload(priority="balanced"))

    # Verified contractor with moderate score (balanced score = 80)
    c_verified = make_extracted_contractor(
        name="Verified Renovator",
        phone_raw="01 42 68 55 01",
        phone_source_url="https://verified.example/contact",
        website="https://verified.example",
        price_sub=80,
        rep_sub=80,
        fit_sub=80,
        avail_sub=80,
    )
    # Unverified contractor with higher raw score (balanced score = 95)
    c_unverified = make_extracted_contractor(
        name="Unverified High Score",
        phone_raw="01 42 68 55 02",
        phone_source_url="https://unverified.example/contact",
        website="https://unverified.example",
        price_sub=95,
        rep_sub=95,
        fit_sub=95,
        avail_sub=95,
    )
    # Closed contractor -> must be filtered out
    c_closed = make_extracted_contractor(
        name="Closed SARL",
        phone_raw="01 42 68 55 03",
        website="https://closed.example",
        is_closed=True,
    )
    # No phone contractor -> must be filtered out
    c_no_phone = make_extracted_contractor(
        name="No Phone Co",
        phone_raw="not found",
        website="https://nophone.example",
    )
    # Missing flooring trade -> must be filtered out
    c_missing_trade = make_extracted_contractor(
        name="Paint Only Co",
        phone_raw="01 42 68 55 04",
        website="https://paintonly.example",
        trades=["painting"],
    )

    extraction = StructuringExtraction(
        price_estimate=make_price_estimate(),
        contractors=[c_unverified, c_closed, c_no_phone, c_missing_trade, c_verified],
        warnings=[],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        if "verified.example" in str(req.url):
            return httpx.Response(200, text="Tel: 01 42 68 55 01")
        return httpx.Response(200, text="No phone listed here")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as mock_client:
        result = await verify_and_rank_contractors(
            request, extraction, http_client=mock_client
        )

    assert len(result.contractors) == 2
    # phone_verified=True must rank #1 ahead of phone_verified=False despite 80 < 95
    assert result.contractors[0].name == "Verified Renovator"
    assert result.contractors[0].phone_verified is True
    assert result.contractors[0].rank == 1
    assert result.contractors[0].id == "c1"

    assert result.contractors[1].name == "Unverified High Score"
    assert result.contractors[1].phone_verified is False
    assert result.contractors[1].rank == 2
    assert result.contractors[1].id == "c2"

    # Fewer than 5 qualifying contractors -> warning appended, list not padded
    assert any("Only 2 qualifying contractors" in w for w in result.warnings)


# ---------------------------------------------------------------------------
# 5. Deduplication Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_deduplication_by_phone_and_normalized_website() -> None:
    assert normalize_website_url("https://www.atelier.fr/") == "atelier.fr"
    assert normalize_website_url("http://atelier.fr") == "atelier.fr"

    request = ResearchRequest.model_validate(make_valid_request_payload(priority="balanced"))

    # Duplicate phone number (same E.164 +33142685500), different scores
    c_phone_low = make_extracted_contractor(
        name="Atelier Dup Phone Low",
        phone_raw="01 42 68 55 00",
        website="https://dup-one.fr",
        price_sub=70,
        rep_sub=70,
        fit_sub=70,
        avail_sub=70,
    )
    c_phone_high = make_extracted_contractor(
        name="Atelier Dup Phone High",
        phone_raw="+33 1 42 68 55 00",
        website="https://dup-two.fr",
        price_sub=90,
        rep_sub=90,
        fit_sub=90,
        avail_sub=90,
    )

    # Duplicate website URL (https://www.atelier.fr/ vs http://atelier.fr), different phones
    c_web_1 = make_extracted_contractor(
        name="Atelier Website 1",
        phone_raw="01 42 68 55 10",
        website="https://www.atelier.fr/",
        price_sub=88,
        rep_sub=88,
        fit_sub=88,
        avail_sub=88,
    )
    c_web_2 = make_extracted_contractor(
        name="Atelier Website 2",
        phone_raw="01 42 68 55 11",
        website="http://atelier.fr",
        price_sub=75,
        rep_sub=75,
        fit_sub=75,
        avail_sub=75,
    )

    extraction = StructuringExtraction(
        price_estimate=make_price_estimate(),
        contractors=[c_phone_low, c_phone_high, c_web_1, c_web_2],
        warnings=[],
    )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda r: httpx.Response(404))
    ) as mock_client:
        result = await verify_and_rank_contractors(
            request, extraction, http_client=mock_client
        )

    assert len(result.contractors) == 2
    names = [c.name for c in result.contractors]
    assert "Atelier Dup Phone High" in names
    assert "Atelier Dup Phone Low" not in names
    assert "Atelier Website 1" in names
    assert "Atelier Website 2" not in names


# ---------------------------------------------------------------------------
# 6. Phase 1 Polling & Phase 2 Structuring Retry / Fallback Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_phase1_researcher_polls_and_extracts_steps_and_citations() -> None:
    request = ResearchRequest.model_validate(make_valid_request_payload())
    prompt = build_research_prompt(request)
    assert "Paris" in prompt
    assert "painting" in prompt
    assert "flooring" in prompt
    assert "not found" in prompt

    created_kwargs: dict[str, Any] = {}
    poll_count = 0

    class FakeInteractions:
        def create(self, **kwargs: Any) -> Any:
            created_kwargs.update(kwargs)
            return SimpleNamespace(id="inter-123", status="in_progress")

        def get(self, interaction_id: str) -> Any:
            nonlocal poll_count
            assert interaction_id == "inter-123"
            poll_count += 1
            if poll_count == 1:
                return SimpleNamespace(id="inter-123", status="in_progress")
            return SimpleNamespace(
                id="inter-123",
                status="completed",
                steps=[
                    SimpleNamespace(
                        type="model_output",
                        content=[
                            SimpleNamespace(
                                type="text",
                                text="Found 10 Paris contractors including Atelier Kanso (+33142685500).",
                                annotations=[
                                    SimpleNamespace(
                                        type="url_citation",
                                        url="https://atelier-kanso.example/contact",
                                    )
                                ],
                            )
                        ],
                    )
                ],
            )

    fake_client = SimpleNamespace(interactions=FakeInteractions())
    recorded_ids: list[str] = []

    report = await run_deep_research(
        request,
        client=fake_client,
        on_interaction_created=recorded_ids.append,
        poll_interval_seconds=0.01,
        timeout_seconds=5.0,
    )

    assert created_kwargs["background"] is True
    assert "store" not in created_kwargs  # Must never set store=False
    assert recorded_ids == ["inter-123"]
    assert poll_count == 2
    assert "Atelier Kanso" in report
    assert "https://atelier-kanso.example/contact" in report


@pytest.mark.asyncio
async def test_phase2_structuring_retries_once_on_invalid_json_then_succeeds() -> None:
    request = ResearchRequest.model_validate(make_valid_request_payload())
    valid_extraction = StructuringExtraction(
        price_estimate=make_price_estimate(),
        contractors=[make_extracted_contractor()],
        warnings=[],
    )

    calls: list[str] = []

    class FakeModels:
        def generate_content(self, model: str, contents: str, config: Any) -> Any:
            calls.append(model)
            if len(calls) == 1:
                return SimpleNamespace(text="{invalid_json: true")
            return SimpleNamespace(text=valid_extraction.model_dump_json())

    fake_client = SimpleNamespace(models=FakeModels())
    result = await structure_research_report(
        request, "Sample Phase 1 Report", client=fake_client
    )
    assert len(calls) == 2
    assert len(result.contractors) == 1
    assert result.contractors[0].name == "Atelier Test"


@pytest.mark.asyncio
async def test_phase2_structuring_fails_after_second_invalid_output() -> None:
    request = ResearchRequest.model_validate(make_valid_request_payload())
    calls = 0

    class FakeModels:
        def generate_content(self, model: str, contents: str, config: Any) -> Any:
            nonlocal calls
            calls += 1
            return SimpleNamespace(text="not valid json at all")

    fake_client = SimpleNamespace(models=FakeModels())
    with pytest.raises(StructuringError):
        await structure_research_report(
            request, "Sample Phase 1 Report", client=fake_client
        )
    assert calls == 2


@pytest.mark.asyncio
async def test_phase2_structuring_falls_back_to_fallback_model_on_api_error() -> None:
    request = ResearchRequest.model_validate(make_valid_request_payload())
    valid_extraction = StructuringExtraction(
        price_estimate=make_price_estimate(),
        contractors=[make_extracted_contractor()],
        warnings=[],
    )
    models_called: list[str] = []

    class FakeModels:
        def generate_content(self, model: str, contents: str, config: Any) -> Any:
            models_called.append(model)
            if model == settings.structuring_model:
                raise RuntimeError("Primary model unavailable")
            return SimpleNamespace(text=valid_extraction.model_dump_json())

    fake_client = SimpleNamespace(models=FakeModels())
    result = await structure_research_report(
        request, "Sample Phase 1 Report", client=fake_client
    )
    assert models_called == [settings.structuring_model, settings.fallback_model]
    assert len(result.contractors) == 1


# ---------------------------------------------------------------------------
# 7. FastAPI Endpoints & Demo Mode Schema Conformance Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_api_health_and_demo_mode_full_lifecycle(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "demo_mode", True)
    monkeypatch.setattr(settings, "demo_phase_durations", (0.02, 0.02, 0.02))
    JOBS.clear()

    job_status_schema = load_json_schema("job_status.schema.json")
    response_schema = load_json_schema("research_response.schema.json")

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. GET /health
        health_resp = await client.get("/health")
        assert health_resp.status_code == 200
        assert health_resp.json() == {"status": "ok", "demo_mode": True}

        # 2. POST /research with invalid payload -> 422
        bad_payload = make_valid_request_payload()
        bad_payload["answers"]["budget"] = "not_a_budget"
        bad_resp = await client.post("/research", json=bad_payload)
        assert bad_resp.status_code == 422

        # 3. POST /research with valid payload -> 200 + job_id
        valid_payload = make_valid_request_payload(priority="lowest_price")
        create_resp = await client.post("/research", json=valid_payload)
        assert create_resp.status_code == 200
        job_id = create_resp.json()["job_id"]
        assert isinstance(job_id, str) and len(job_id) > 0

        # 4. Poll GET /research/{job_id} until completed
        final_body: dict[str, Any] | None = None
        for _ in range(30):
            status_resp = await client.get(f"/research/{job_id}")
            assert status_resp.status_code == 200
            body = status_resp.json()
            if body["status"] == "completed":
                final_body = body
                break
            await asyncio.sleep(0.02)

        assert final_body is not None
        assert final_body["status"] == "completed"
        assert final_body["phase"] == "done"
        assert final_body["error"] is None
        assert final_body["result"] is not None
        assert final_body["result"]["is_demo"] is True
        assert final_body["result"]["project_id"] == "demo-001"

        # Validate result against /shared/schemas/research_response.schema.json
        jsonschema.validate(instance=final_body["result"], schema=response_schema)

        # Verify 404 on unknown job_id
        not_found_resp = await client.get("/research/non-existent-job-id")
        assert not_found_resp.status_code == 404
