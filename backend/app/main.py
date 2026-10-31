"""FastAPI application and endpoints for the Automated Home-Renovation Pipeline."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Any
import uuid

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response

from app.calls.agents import (
    RenovatorPersona,
    build_customer_agent_system_prompt,
    build_renovator_agent_system_prompt,
    build_renovator_persona,
    ensure_meeting_slots,
)
from app.calls.outcome import (
    extract_and_evaluate_outcome,
    load_call_replay,
    save_call_replay,
)
from app.calls.transport import SimulatedCallTransport
from app.config import SHARED_DIR, settings
from app.models import (
    BookingResult,
    CallOutcome,
    CallPhase,
    CallRequest,
    CallStatus,
    CallStatusResponse,
    CallTurn,
    Contractor,
    CreateCallResponse,
    CreateJobResponse,
    JobPhase,
    JobStatus,
    JobStatusResponse,
    MatchDecision,
    MeetingInput,
    ResearchRequest,
    ResearchResult,
)
from app.pipeline.researcher import run_deep_research
from app.pipeline.structurer import structure_research_report
from app.pipeline.verifier import compute_score, verify_and_rank_contractors
from app.scheduling.calendar import schedule_in_person_meeting

DEMO_RESULT_PATH: Path = SHARED_DIR / "fixtures" / "demo_result.json"


@dataclass
class JobRecord:
    """In-memory state for a running or completed research job."""

    job_id: str
    request: ResearchRequest
    status: JobStatus = "queued"
    phase: JobPhase = "researching"
    interaction_id: str | None = None
    result: ResearchResult | None = None
    error: str | None = None
    task: asyncio.Task[None] | None = field(default=None, repr=False)


@dataclass
class CallRecord:
    """In-memory state for a running or completed voice bargaining call."""

    call_id: str
    job_id: str
    contractor_id: str
    research_request: ResearchRequest
    contractor: Contractor
    is_demo: bool
    meeting: MeetingInput
    slots: list[str]
    persona: RenovatorPersona = field(repr=False)
    customer_prompt: str = field(default="", repr=False)
    renovator_prompt: str = field(default="", repr=False)
    status: CallStatus = "queued"
    phase: CallPhase = "negotiating"
    simulated: bool = True
    is_replay: bool = False
    turns: list[CallTurn] = field(default_factory=list)
    audio_by_turn: dict[int, bytes] = field(default_factory=dict, repr=False)
    outcome: CallOutcome | None = None
    match: MatchDecision | None = None
    booking: BookingResult | None = None
    warnings: list[str] = field(default_factory=list)
    error: str | None = None
    stop_requested: bool = False
    timed_out: bool = False
    hit_turn_limit: bool = False
    agent_end_reason: str | None = None
    gemini_client: Any | None = field(default=None, repr=False)
    calendar_service: Any | None = field(default=None, repr=False)
    task: asyncio.Task[None] | None = field(default=None, repr=False)


JOBS: dict[str, JobRecord] = {}
CALLS: dict[str, CallRecord] = {}

app = FastAPI(
    title="Automated Home-Renovation Research & Voice Bargaining API",
    version="0.2.0",
    description="Deep Research, Structuring, Verification, AI Voice Bargaining, and Scheduling Pipeline",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def load_demo_result(request: ResearchRequest) -> ResearchResult:
    """Load /shared/fixtures/demo_result.json and adapt project_id and priority ranking."""
    if not DEMO_RESULT_PATH.exists():
        raise FileNotFoundError(f"Demo fixture not found at {DEMO_RESULT_PATH}")

    raw_data = json.loads(DEMO_RESULT_PATH.read_text(encoding="utf-8"))
    result = ResearchResult.model_validate(raw_data)
    result.project_id = request.project.project_id
    result.is_demo = True

    if request.answers.priority != "balanced":
        for contractor in result.contractors:
            contractor.score = compute_score(
                contractor.subscores, request.answers.priority
            )
        result.contractors.sort(
            key=lambda c: (c.phone_verified, c.score),
            reverse=True,
        )
        for idx, contractor in enumerate(result.contractors, start=1):
            contractor.rank = idx

    return result


async def _run_demo_job(job: JobRecord) -> None:
    """Simulate the 3 pipeline phases over ~10 seconds and return demo_result.json."""
    try:
        d1, d2, d3 = settings.demo_phase_durations
        job.status = "running"
        job.phase = "researching"
        await asyncio.sleep(d1)

        job.phase = "structuring"
        await asyncio.sleep(d2)

        job.phase = "verifying"
        await asyncio.sleep(d3)

        job.result = load_demo_result(job.request)
        job.phase = "done"
        job.status = "completed"
    except Exception as exc:
        job.status = "failed"
        job.error = f"Demo job failed: {exc}"


async def _run_live_job(job: JobRecord) -> None:
    """Execute the live 3-phase Deep Research -> Structuring -> Verification pipeline."""
    try:
        job.status = "running"
        job.phase = "researching"

        def _store_interaction_id(interaction_id: str) -> None:
            job.interaction_id = interaction_id

        raw_report = await run_deep_research(
            job.request,
            on_interaction_created=_store_interaction_id,
        )

        job.phase = "structuring"
        extraction = await structure_research_report(job.request, raw_report)

        job.phase = "verifying"
        result = await verify_and_rank_contractors(job.request, extraction)

        job.result = result
        job.phase = "done"
        job.status = "completed"
    except Exception as exc:
        job.status = "failed"
        job.error = str(exc)


async def _run_call(call: CallRecord) -> None:
    """Execute the voice bargaining call, outcome analysis, and conditional calendar booking."""
    try:
        if call.stop_requested:
            call.status = "stopped"
            call.phase = "done"
            return

        call.status = "running"
        call.phase = "negotiating"

        if settings.call_replay:
            call.is_replay = True
            (
                turns,
                audio_by_turn,
                outcome,
                match_decision,
                replay_warnings,
            ) = load_call_replay(
                call_id=call.call_id,
                customer_slots=call.slots,
                contractor=call.contractor,
            )
            call.turns = turns
            call.audio_by_turn = audio_by_turn
            call.outcome = outcome
            call.match = match_decision
            call.warnings.extend(replay_warnings)
        else:
            transport = SimulatedCallTransport(gemini_client=call.gemini_client)
            await transport.run_conversation(call)

            if call.stop_requested:
                call.status = "stopped"
                call.phase = "done"
                call.booking = None
                return

            call.phase = "analyzing"
            (
                outcome,
                match_decision,
                verify_warnings,
            ) = await extract_and_evaluate_outcome(
                turns=call.turns,
                customer_slots=call.slots,
                contractor=call.contractor,
                timed_out=call.timed_out,
                stop_requested=call.stop_requested,
                hit_turn_limit=call.hit_turn_limit,
                client=call.gemini_client,
            )
            call.outcome = outcome
            call.match = match_decision
            call.warnings.extend(verify_warnings)

        if call.stop_requested:
            call.status = "stopped"
            call.phase = "done"
            call.booking = None
            return

        if (
            call.match is not None
            and call.match.match
            and call.outcome is not None
            and not call.stop_requested
        ):
            call.phase = "scheduling"
            call.booking = await schedule_in_person_meeting(
                research_request=call.research_request,
                contractor=call.contractor,
                meeting=call.meeting,
                outcome=call.outcome,
                is_demo=call.is_demo,
                stop_requested=call.stop_requested,
                calendar_service=call.calendar_service,
            )

        if call.stop_requested:
            call.status = "stopped"
            call.phase = "done"
            call.booking = None
            return

        call.phase = "done"
        call.status = "completed"

        if (
            not call.is_replay
            and call.outcome is not None
            and call.match is not None
        ):
            try:
                save_call_replay(
                    turns=call.turns,
                    audio_by_turn=call.audio_by_turn,
                    outcome=call.outcome,
                    match=call.match,
                    warnings=call.warnings,
                )
            except Exception:
                pass
    except asyncio.CancelledError:
        call.status = "stopped"
        call.phase = "done"
        call.booking = None
    except Exception as exc:
        if call.stop_requested:
            call.status = "stopped"
            call.phase = "done"
            call.booking = None
        else:
            call.status = "failed"
            call.phase = "done"
            call.error = str(exc)


def _build_call_status_response(
    call: CallRecord,
    after: int = 0,
) -> CallStatusResponse:
    """Build CallStatusResponse excluding RenovatorPersona and filtering turns >= after."""
    filtered_turns = [t for t in call.turns if t.index >= after]
    return CallStatusResponse(
        status=call.status,
        phase=call.phase,
        simulated=call.simulated,
        is_replay=call.is_replay,
        turns=filtered_turns,
        outcome=call.outcome,
        match=call.match,
        booking=call.booking,
        warnings=list(call.warnings),
        error=call.error,
    )


@app.get("/health")
async def get_health() -> dict[str, object]:
    """Return service health and current demo_mode status."""
    return {
        "status": "ok",
        "demo_mode": settings.demo_mode,
    }


@app.post("/research", response_model=CreateJobResponse)
async def create_research_job(request: ResearchRequest) -> CreateJobResponse:
    """Validate ResearchRequest, enqueue a background job, and return job_id."""
    job_id = str(uuid.uuid4())
    job = JobRecord(
        job_id=job_id,
        request=request,
        status="queued",
        phase="researching",
    )
    JOBS[job_id] = job

    runner = _run_demo_job if settings.demo_mode else _run_live_job
    job.task = asyncio.create_task(runner(job))

    return CreateJobResponse(job_id=job_id)


@app.get("/research/{job_id}", response_model=JobStatusResponse)
async def get_research_job_status(job_id: str) -> JobStatusResponse:
    """Return current status, phase, and result/error for a research job."""
    job = JOBS.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found")

    return JobStatusResponse(
        status=job.status,
        phase=job.phase,
        result=job.result,
        error=job.error,
    )


@app.post("/calls", response_model=CreateCallResponse)
async def create_call(request: CallRequest) -> CreateCallResponse:
    """Start a simulated AI bargaining call for a contractor in a completed research job."""
    job = JOBS.get(request.job_id)
    if job is None:
        raise HTTPException(
            status_code=404, detail=f"Job '{request.job_id}' not found"
        )

    if job.status != "completed" or job.result is None:
        raise HTTPException(
            status_code=409,
            detail=f"Research job '{request.job_id}' is not completed (status={job.status})",
        )

    contractor = next(
        (c for c in job.result.contractors if c.id == request.contractor_id),
        None,
    )
    if contractor is None:
        raise HTTPException(
            status_code=404,
            detail=f"Contractor '{request.contractor_id}' not found in job '{request.job_id}'",
        )

    slots = ensure_meeting_slots(
        request.meeting.slots, settings.calendar_timezone
    )
    normalized_meeting = MeetingInput(
        customer_email=request.meeting.customer_email,
        address=request.meeting.address,
        slots=slots,
    )

    try:
        persona = build_renovator_persona(
            contractor=contractor,
            customer_slots=slots,
            is_demo=job.result.is_demo,
            timezone_name=settings.calendar_timezone,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    customer_prompt = build_customer_agent_system_prompt(
        research_request=job.request,
        contractor=contractor,
        slots=slots,
        is_demo=job.result.is_demo,
        call_language=settings.call_language,
    )
    renovator_prompt = build_renovator_agent_system_prompt(
        persona=persona,
        currency=contractor.expected_price.currency,
        call_language=settings.call_language,
    )

    call_id = str(uuid.uuid4())
    call_record = CallRecord(
        call_id=call_id,
        job_id=request.job_id,
        contractor_id=request.contractor_id,
        research_request=job.request,
        contractor=contractor,
        is_demo=job.result.is_demo,
        meeting=normalized_meeting,
        slots=slots,
        persona=persona,
        customer_prompt=customer_prompt,
        renovator_prompt=renovator_prompt,
        status="queued",
        phase="negotiating",
        simulated=True,
        is_replay=settings.call_replay,
    )
    CALLS[call_id] = call_record
    call_record.task = asyncio.create_task(_run_call(call_record))

    return CreateCallResponse(call_id=call_id)


@app.get("/calls/{call_id}", response_model=CallStatusResponse)
async def get_call_status(
    call_id: str,
    after: int = Query(default=0, ge=0),
) -> CallStatusResponse:
    """Return call status, turns with index >= after, outcome, match, and booking."""
    call = CALLS.get(call_id)
    if call is None:
        raise HTTPException(
            status_code=404, detail=f"Call '{call_id}' not found"
        )
    return _build_call_status_response(call, after=after)


@app.get("/calls/{call_id}/audio/{index}")
async def get_call_turn_audio(call_id: str, index: int) -> Response:
    """Return WAV audio bytes for turn `index` of call `call_id`."""
    call = CALLS.get(call_id)
    if call is None:
        raise HTTPException(
            status_code=404, detail=f"Call '{call_id}' not found"
        )
    wav_bytes = call.audio_by_turn.get(index)
    if wav_bytes is None:
        raise HTTPException(
            status_code=404,
            detail=f"Audio for turn {index} in call '{call_id}' not found",
        )
    return Response(content=wav_bytes, media_type="audio/wav")


@app.post("/calls/{call_id}/stop", response_model=CallStatusResponse)
async def stop_call(call_id: str) -> CallStatusResponse:
    """Stop a running or queued call immediately and ensure no meeting is scheduled."""
    call = CALLS.get(call_id)
    if call is None:
        raise HTTPException(
            status_code=404, detail=f"Call '{call_id}' not found"
        )

    call.stop_requested = True
    call.status = "stopped"
    call.phase = "done"
    call.booking = None

    if call.outcome is not None:
        call.outcome.end_reason = "stopped"
    if call.match is not None:
        call.match = MatchDecision(
            match=False, reasons=["Call was stopped by user"]
        )

    if call.task is not None and not call.task.done():
        call.task.cancel()

    return _build_call_status_response(call, after=0)
