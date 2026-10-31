"""
Spike script to verify configured Gemini model, Deep Research agent, TALK_MODEL, and TTS_MODEL IDs
against the live API. Reads configuration from backend/.env (or environment variables).

Usage:
    python backend/scripts/spike_gemini.py [--skip-deep-research] [--calls-only]
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import wave
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


def wrap_pcm_to_wav(pcm_bytes: bytes, sample_rate: int = 24000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_bytes)
    return buf.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Gemini API models, Deep Research, TALK_MODEL, and TTS_MODEL.")
    parser.add_argument(
        "--skip-deep-research",
        action="store_true",
        help="Skip creating a live background interaction on DEEP_RESEARCH_AGENT to save quota.",
    )
    parser.add_argument(
        "--calls-only",
        action="store_true",
        help="Run only the smallest possible TALK_MODEL text call and TTS_MODEL audio call.",
    )
    parser.add_argument(
        "--poll-id",
        type=str,
        default=None,
        help="Poll an existing Deep Research interaction ID until completion.",
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
    talk_model = os.environ.get("TALK_MODEL", "gemini-3.8-flash")
    tts_model = os.environ.get("TTS_MODEL", "gemini-3.8-flash-tts")
    buyer_voice = os.environ.get("BUYER_VOICE", "Kore")
    seller_voice = os.environ.get("SELLER_VOICE", "Puck")

    report: dict[str, object] = {
        "configured": {
            "DEEP_RESEARCH_AGENT": deep_research_agent,
            "STRUCTURING_MODEL": structuring_model,
            "FALLBACK_MODEL": fallback_model,
            "TALK_MODEL": talk_model,
            "TTS_MODEL": tts_model,
            "BUYER_VOICE": buyer_voice,
            "SELLER_VOICE": seller_voice,
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

        class SpikeTurnCheck(BaseModel):
            text: str
            end_call: bool
            end_reason: str | None = None
    except ImportError as exc:
        report["blocker"] = f"Required SDK not installed in active environment: {exc}"
        print(json.dumps(report, indent=2))
        return 3

    client = genai.Client(api_key=api_key)
    results: dict[str, object] = {}

    if args.calls_only:
        # 1. Smallest possible TALK_MODEL text call with cleaned schema
        try:
            raw_schema = SpikeTurnCheck.model_json_schema()
            for key in ("title", "additionalProperties", "additional_properties"):
                raw_schema.pop(key, None)
            resp = client.models.generate_content(
                model=talk_model,
                contents="Say 'Hello from AI assistant' with end_call=false and end_reason=null.",
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=raw_schema,
                    temperature=0.0,
                ),
            )
            parsed = SpikeTurnCheck.model_validate_json(resp.text)
            results["TALK_MODEL"] = {
                "model_id": talk_model,
                "status": "ok",
                "parsed": parsed.model_dump(),
            }
        except Exception as exc:
            results["TALK_MODEL"] = {
                "model_id": talk_model,
                "status": "failed",
                "error": f"{type(exc).__name__}: {exc}",
            }

        # 2. One short TTS_MODEL audio call
        try:
            tts_resp = client.models.generate_content(
                model=tts_model,
                contents="Hello, I am an AI assistant calling for a customer.",
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"],
                    speech_config=types.SpeechConfig(
                        voice_config=types.VoiceConfig(
                            prebuilt_voice_config=types.PrebuiltVoiceConfig(
                                voice_name=buyer_voice,
                            )
                        )
                    ),
                ),
            )
            part = tts_resp.candidates[0].content.parts[0]
            inline_data = part.inline_data
            pcm_bytes = inline_data.data
            mime_type = getattr(inline_data, "mime_type", "")
            wav_bytes = wrap_pcm_to_wav(pcm_bytes, sample_rate=24000)
            results["TTS_MODEL"] = {
                "model_id": tts_model,
                "voice": buyer_voice,
                "status": "ok",
                "mime_type": mime_type,
                "pcm_bytes_len": len(pcm_bytes),
                "wav_bytes_len": len(wav_bytes),
                "wav_header_valid": wav_bytes[:4] == b"RIFF",
            }
        except Exception as exc:
            results["TTS_MODEL"] = {
                "model_id": tts_model,
                "voice": buyer_voice,
                "status": "failed",
                "error": f"{type(exc).__name__}: {exc}",
            }

        report["results"] = results
        print(json.dumps(report, indent=2))
        return 0

    # Standard mode:
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

    if not args.skip_deep_research:
        try:
            interaction = client.interactions.create(
                agent=deep_research_agent,
                input="Reply with the single word OK.",
                background=True,
            )
            results["DEEP_RESEARCH_AGENT"] = {
                "agent_id": deep_research_agent,
                "status": "ok",
                "interaction_id": getattr(interaction, "id", None),
                "initial_interaction_status": getattr(interaction, "status", None),
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
