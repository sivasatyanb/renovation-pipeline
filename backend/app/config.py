"""Application configuration loaded from backend/.env and environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from dotenv import dotenv_values, load_dotenv

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_DIR.parent
SHARED_DIR = REPO_ROOT / "shared"
ENV_FILE = BACKEND_DIR / ".env"
ENV_EXAMPLE_FILE = BACKEND_DIR / ".env.example"

# Load backend/.env into environment without overriding existing environment variables
if ENV_FILE.exists():
    load_dotenv(dotenv_path=ENV_FILE, override=False)

_EXAMPLE_VALUES: dict[str, str] = {}
if ENV_EXAMPLE_FILE.exists():
    _EXAMPLE_VALUES = {
        k: v for k, v in dotenv_values(ENV_EXAMPLE_FILE).items() if k and v is not None
    }


def _parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def _parse_origins(value: str | None) -> list[str]:
    if not value:
        return [
            "http://localhost:3000",
            "http://localhost:8080",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:8080",
            "http://10.0.2.2:8000",
        ]
    return [origin.strip() for origin in value.split(",") if origin.strip()]


def _parse_allowlist(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip().lower() for item in value.split(",") if item.strip()]


@dataclass
class Settings:
    """Runtime settings for the renovation research and voice bargaining pipeline."""

    gemini_api_key: str = field(default="", repr=False)
    deep_research_agent: str = ""
    structuring_model: str = ""
    fallback_model: str = ""
    talk_model: str = "gemini-3.8-flash"
    tts_model: str = "gemini-3.8-flash-tts"
    buyer_voice: str = "Kore"
    seller_voice: str = "Puck"
    call_language: str = "en-US"
    max_call_turns: int = 10
    call_timeout_seconds: float = 120.0
    call_replay: bool = False
    calendar_timezone: str = "Europe/Paris"
    invite_allowlist: list[str] = field(default_factory=list)
    google_credentials_file: str = "credentials.json"
    google_token_file: str = "token.json"
    render_plan_model: str = "gemini-3.8-flash"
    image_model: str = "gemini-2.5-flash-image"
    image_fallback_model: str = "gemini-3.1-flash-image"
    render_replay: bool = False
    demo_mode: bool = False
    cors_allowed_origins: list[str] = field(default_factory=list)
    cors_origin_regex: str = r"^http://(localhost|127\.0\.0\.1|10\.0\.2\.2)(:\d+)?$"
    deep_research_poll_interval_seconds: float = 10.0
    deep_research_timeout_seconds: float = 600.0
    phone_verify_timeout_seconds: float = 5.0
    demo_phase_durations: tuple[float, float, float] = (3.5, 3.5, 3.0)


def load_settings() -> Settings:
    """Create a Settings object from current environment variables."""
    return Settings(
        gemini_api_key=os.environ.get("GEMINI_API_KEY", "").strip(),
        deep_research_agent=os.environ.get(
            "DEEP_RESEARCH_AGENT",
            _EXAMPLE_VALUES.get("DEEP_RESEARCH_AGENT", ""),
        ).strip(),
        structuring_model=os.environ.get(
            "STRUCTURING_MODEL",
            _EXAMPLE_VALUES.get("STRUCTURING_MODEL", ""),
        ).strip(),
        fallback_model=os.environ.get(
            "FALLBACK_MODEL",
            _EXAMPLE_VALUES.get("FALLBACK_MODEL", ""),
        ).strip(),
        talk_model=os.environ.get(
            "TALK_MODEL",
            _EXAMPLE_VALUES.get("TALK_MODEL", "gemini-3.8-flash"),
        ).strip(),
        tts_model=os.environ.get(
            "TTS_MODEL",
            _EXAMPLE_VALUES.get("TTS_MODEL", "gemini-3.8-flash-tts"),
        ).strip(),
        buyer_voice=os.environ.get(
            "BUYER_VOICE",
            _EXAMPLE_VALUES.get("BUYER_VOICE", "Kore"),
        ).strip(),
        seller_voice=os.environ.get(
            "SELLER_VOICE",
            _EXAMPLE_VALUES.get("SELLER_VOICE", "Puck"),
        ).strip(),
        call_language=os.environ.get(
            "CALL_LANGUAGE",
            _EXAMPLE_VALUES.get("CALL_LANGUAGE", "en-US"),
        ).strip(),
        max_call_turns=int(
            os.environ.get(
                "MAX_CALL_TURNS",
                _EXAMPLE_VALUES.get("MAX_CALL_TURNS", "10"),
            )
        ),
        call_timeout_seconds=float(
            os.environ.get(
                "CALL_TIMEOUT_SECONDS",
                _EXAMPLE_VALUES.get("CALL_TIMEOUT_SECONDS", "120"),
            )
        ),
        call_replay=_parse_bool(
            os.environ.get(
                "CALL_REPLAY",
                _EXAMPLE_VALUES.get("CALL_REPLAY", "false"),
            ),
            default=False,
        ),
        calendar_timezone=os.environ.get(
            "CALENDAR_TIMEZONE",
            _EXAMPLE_VALUES.get("CALENDAR_TIMEZONE", "Europe/Paris"),
        ).strip(),
        invite_allowlist=_parse_allowlist(
            os.environ.get(
                "INVITE_ALLOWLIST",
                _EXAMPLE_VALUES.get("INVITE_ALLOWLIST", ""),
            )
        ),
        google_credentials_file=os.environ.get(
            "GOOGLE_CREDENTIALS_FILE",
            _EXAMPLE_VALUES.get("GOOGLE_CREDENTIALS_FILE", "credentials.json"),
        ).strip(),
        google_token_file=os.environ.get(
            "GOOGLE_TOKEN_FILE",
            _EXAMPLE_VALUES.get("GOOGLE_TOKEN_FILE", "token.json"),
        ).strip(),
        render_plan_model=os.environ.get(
            "RENDER_PLAN_MODEL",
            _EXAMPLE_VALUES.get("RENDER_PLAN_MODEL", "gemini-3.8-flash"),
        ).strip(),
        image_model=os.environ.get(
            "IMAGE_MODEL",
            _EXAMPLE_VALUES.get("IMAGE_MODEL", "gemini-2.5-flash-image"),
        ).strip(),
        image_fallback_model=os.environ.get(
            "IMAGE_FALLBACK_MODEL",
            _EXAMPLE_VALUES.get("IMAGE_FALLBACK_MODEL", "gemini-3.1-flash-image"),
        ).strip(),
        render_replay=_parse_bool(
            os.environ.get(
                "RENDER_REPLAY",
                _EXAMPLE_VALUES.get("RENDER_REPLAY", "false"),
            ),
            default=False,
        ),
        demo_mode=_parse_bool(os.environ.get("DEMO_MODE"), default=False),
        cors_allowed_origins=_parse_origins(
            os.environ.get(
                "CORS_ALLOWED_ORIGINS",
                _EXAMPLE_VALUES.get("CORS_ALLOWED_ORIGINS"),
            )
        ),
        cors_origin_regex=os.environ.get(
            "CORS_ORIGIN_REGEX",
            _EXAMPLE_VALUES.get(
                "CORS_ORIGIN_REGEX",
                r"^http://(localhost|127\.0\.0\.1|10\.0\.2\.2)(:\d+)?$",
            ),
        ).strip(),
        deep_research_poll_interval_seconds=float(
            os.environ.get(
                "DEEP_RESEARCH_POLL_INTERVAL_SECONDS",
                _EXAMPLE_VALUES.get("DEEP_RESEARCH_POLL_INTERVAL_SECONDS", "10"),
            )
        ),
        deep_research_timeout_seconds=float(
            os.environ.get(
                "DEEP_RESEARCH_TIMEOUT_SECONDS",
                _EXAMPLE_VALUES.get("DEEP_RESEARCH_TIMEOUT_SECONDS", "600"),
            )
        ),
        phone_verify_timeout_seconds=float(
            os.environ.get(
                "PHONE_VERIFY_TIMEOUT_SECONDS",
                _EXAMPLE_VALUES.get("PHONE_VERIFY_TIMEOUT_SECONDS", "5.0"),
            )
        ),
    )


settings = load_settings()
