"""FastAPI application and endpoints for the Automated Home-Renovation Pipeline."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import json
from pathlib import Path
import uuid

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.config import SHARED_DIR, settings
from app.models import (
    CreateJobResponse,
    JobPhase,
    JobStatus,
    JobStatusResponse,
    ResearchRequest,
    ResearchResult,
)
from app.pipeline.researcher import run_deep_research
from app.pipeline.structurer import structure_research_report
from app.pipeline.verifier import compute_score, verify_and_rank_contractors

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


JOBS: dict[str, JobRecord] = {}

app = FastAPI(
    title="Automated Home-Renovation Research API",
    version="0.1.0",
    description="Deep Research, Structuring, and Phone/Scope Verification Pipeline",
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
