"""
Spike script to verify configured Gemini model and Deep Research agent IDs against the live API.
Reads configuration from backend/.env (or environment variables).

Usage:
    python backend/scripts/spike_gemini.py [--skip-deep-research]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def load_env_file(env_path: Path) -> None:
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        if key and key not in os.environ:
            os.environ[key] = value


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Gemini API models and Deep Research agent ID.")
    parser.add_argument(
        "--skip-deep-research",
        action="store_true",
        help="Skip creating a live background interaction on DEEP_RESEARCH_AGENT to save quota.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    env_path = repo_root / "backend" / ".env"
    example_env_path = repo_root / "backend" / ".env.example"

    load_env_file(env_path)
    load_env_file(example_env_path)

    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    deep_research_agent = os.environ.get("DEEP_RESEARCH_AGENT", "deep-research-preview-04-2026")
    structuring_model = os.environ.get("STRUCTURING_MODEL", "gemini-4-argon")
    fallback_model = os.environ.get("FALLBACK_MODEL", "gemini-3.8-flash")

    report: dict[str, object] = {
        "configured": {
            "DEEP_RESEARCH_AGENT": deep_research_agent,
            "STRUCTURING_MODEL": structuring_model,
            "FALLBACK_MODEL": fallback_model,
        },
        "env_file_exists": env_path.exists(),
        "api_key_present": bool(api_key and api_key != "your_gemini_api_key_here"),
        "results": {},
    }

    if not report["api_key_present"]:
        report["blocker"] = (
            f"Missing valid GEMINI_API_KEY. Create {env_path} from {example_env_path} "
            "and set GEMINI_API_KEY before running live API checks."
        )
        print(json.dumps(report, indent=2))
        return 2

    try:
        from google import genai
        from google.genai import types
        from pydantic import BaseModel

        class SpikeStructuredCheck(BaseModel):
            ok: bool
            model_echo: str
    except ImportError as exc:
        report["blocker"] = f"Required SDK not installed in active environment: {exc}"
        print(json.dumps(report, indent=2))
        return 3

    client = genai.Client(api_key=api_key)
    results: dict[str, object] = {}

    # 1. Test STRUCTURING_MODEL and FALLBACK_MODEL with structured JSON output
    for label, model_id in [
        ("STRUCTURING_MODEL", structuring_model),
        ("FALLBACK_MODEL", fallback_model),
    ]:
        try:
            resp = client.models.generate_content(
                model=model_id,
                contents=f"Return ok=true and model_echo='{model_id}'.",
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=SpikeStructuredCheck,
                    temperature=0.0,
                ),
            )
            parsed = SpikeStructuredCheck.model_validate_json(resp.text)
            results[label] = {
                "model_id": model_id,
                "status": "ok",
                "parsed": parsed.model_dump(),
            }
        except Exception as exc:
            results[label] = {
                "model_id": model_id,
                "status": "failed",
                "error": f"{type(exc).__name__}: {exc}",
            }

    # 2. Check available models listing for any deep-research / flash / pro / argon IDs
    try:
        available_ids = []
        for m in client.models.list():
            name = getattr(m, "name", "")
            if any(k in name.lower() for k in ("deep-research", "argon", "3.8", "3.1", "flash", "pro")):
                available_ids.append(name)
        results["available_matching_models"] = available_ids[:40]
    except Exception as exc:
        results["available_matching_models_error"] = f"{type(exc).__name__}: {exc}"

    # 3. Test DEEP_RESEARCH_AGENT via Interactions API
    if not args.skip_deep_research:
        try:
            interaction = client.interactions.create(
                agent=deep_research_agent,
                input="Reply with the single word OK.",
                background=True,
            )
            interaction_id = getattr(interaction, "id", None)
            status = getattr(interaction, "status", None)
            results["DEEP_RESEARCH_AGENT"] = {
                "agent_id": deep_research_agent,
                "status": "ok",
                "interaction_id": interaction_id,
                "initial_interaction_status": status,
            }
        except Exception as exc:
            results["DEEP_RESEARCH_AGENT"] = {
                "agent_id": deep_research_agent,
                "status": "failed",
                "error": f"{type(exc).__name__}: {exc}",
            }
    else:
        results["DEEP_RESEARCH_AGENT"] = {
            "agent_id": deep_research_agent,
            "status": "skipped",
        }

    report["results"] = results
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
