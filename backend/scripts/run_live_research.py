"""Execute exactly ONE live pipeline execution against Gemini API and save output."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
import sys
import time

import jsonschema

# Ensure app is importable
REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from app.config import SHARED_DIR, settings
from app.models import (
    ProjectInput,
    QuizAnswers,
    ResearchRequest,
    ResearchResult,
    StructuringExtraction,
)
from app.pipeline.researcher import run_deep_research
from app.pipeline.structurer import structure_research_report
from app.pipeline.verifier import verify_and_rank_contractors

OUT_DIR = Path(r"C:\Users\sivas\.gemini\antigravity\brain\e81a0bf9-2fcf-4b7e-8bcb-2803c61fbf60\scratch")
INTERACTION_FILE = OUT_DIR / "live_interaction_id.txt"
RAW_REPORT_FILE = OUT_DIR / "live_raw_report.txt"
STRUCTURING_FILE = OUT_DIR / "live_structuring_extraction.json"
RESULT_FILE = OUT_DIR / "live_research_result.json"

SCHEMA_PATH = SHARED_DIR / "schemas" / "research_response.schema.json"


async def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Prepare ResearchRequest
    demo_project_path = SHARED_DIR / "fixtures" / "demo_project.json"
    project_dict = json.loads(demo_project_path.read_text(encoding="utf-8"))
    project_input = ProjectInput.model_validate(project_dict)

    quiz_answers = QuizAnswers(
        budget="5k_15k",
        scope="partial",
        timeline="one_to_three_months",
        priority="balanced",
        trust_requirements=["licensed_insured", "style_portfolio"],
    )

    request = ResearchRequest(project=project_input, answers=quiz_answers)
    print(f"Loaded project: {request.project.project_id} ({request.project.client.city}, {request.project.client.country})")
    print(f"Answers: budget={request.answers.budget}, scope={request.answers.scope}, timeline={request.answers.timeline}, priority={request.answers.priority}, trust={request.answers.trust_requirements}")

    # Ensure demo_mode is False
    settings.demo_mode = False
    print(f"Live execution mode: demo_mode={settings.demo_mode}")
    print(f"Deep Research Agent: {settings.deep_research_agent}")
    print(f"Structuring Model: {settings.structuring_model}")
    print(f"Fallback Model: {settings.fallback_model}")

    # Check if raw report already exists (to guard against running Phase 1 twice)
    raw_report = ""
    if RAW_REPORT_FILE.exists() and RAW_REPORT_FILE.stat().st_size > 100:
        print(f"[REUSE GUARD] Found existing Phase 1 raw report at {RAW_REPORT_FILE} ({RAW_REPORT_FILE.stat().st_size} bytes). Reusing existing report to avoid duplicate live calls.")
        raw_report = RAW_REPORT_FILE.read_text(encoding="utf-8")
    else:
        print("\n--- PHASE 1: Running Deep Research Interaction ---")
        start_p1 = time.monotonic()

        def on_interaction_created(iid: str):
            print(f"[PHASE 1] Created Deep Research Interaction ID: {iid}")
            INTERACTION_FILE.write_text(iid, encoding="utf-8")

        raw_report = await run_deep_research(
            request,
            on_interaction_created=on_interaction_created,
            poll_interval_seconds=10.0,
            timeout_seconds=600.0,
        )
        elapsed_p1 = time.monotonic() - start_p1
        print(f"[PHASE 1] Completed in {elapsed_p1:.1f}s. Report length: {len(raw_report)} chars.")
        RAW_REPORT_FILE.write_text(raw_report, encoding="utf-8")

    # 2. Phase 2: Structuring
    print("\n--- PHASE 2: Structuring Extraction ---")
    start_p2 = time.monotonic()
    extraction = await structure_research_report(request, raw_report)
    elapsed_p2 = time.monotonic() - start_p2
    print(f"[PHASE 2] Completed in {elapsed_p2:.1f}s. Extracted {len(extraction.contractors)} candidate contractors.")
    STRUCTURING_FILE.write_text(
        json.dumps(extraction.model_dump(mode="json"), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    # 3. Phase 3: Verification & Ranking
    print("\n--- PHASE 3: Verification & Ranking ---")
    start_p3 = time.monotonic()
    result = await verify_and_rank_contractors(request, extraction)
    elapsed_p3 = time.monotonic() - start_p3
    print(f"[PHASE 3] Completed in {elapsed_p3:.1f}s. Final ranked contractors: {len(result.contractors)}.")

    # 4. Save final result JSON
    result_dict = result.model_dump(mode="json")
    result_json = json.dumps(result_dict, indent=2, ensure_ascii=False)
    RESULT_FILE.write_text(result_json, encoding="utf-8")
    print(f"Saved final live research result to: {RESULT_FILE} ({len(result_json)} bytes)")

    # 5. Schema Validation
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    jsonschema.validate(instance=result_dict, schema=schema)
    print("[VALIDATION] Successfully validated against shared/schemas/research_response.schema.json!")

    # Summary of contractors
    print("\n=== TOP CONTRACTORS SUMMARY ===")
    for c in result.contractors:
        print(f"Rank #{c.rank}: {c.name}")
        print(f"  Phone: {c.phone_e164} (verified: {c.phone_verified})")
        print(f"  Score: {c.score}/100 (Price: {c.subscores.price}, Rep: {c.subscores.reputation}, Fit: {c.subscores.fit}, Avail: {c.subscores.availability})")
        print(f"  Website: {c.website}")
        print(f"  Trades: {c.trades}")
        print(f"  Expected Price: {c.expected_price.low} - {c.expected_price.high} {c.expected_price.currency}")
        print(f"  Red Flags: {len(c.red_flags)}")
        print()

    print(f"Price Estimate: {result.price_estimate.low} - {result.price_estimate.high} {result.price_estimate.currency}")
    print(f"Warnings: {result.warnings}")


if __name__ == "__main__":
    asyncio.run(main())
