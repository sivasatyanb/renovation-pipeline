"""Comprehensive mocked pytest suite for Studio Room Renovation Rendering (/renders)."""

from __future__ import annotations

import asyncio
import base64
import json
from types import SimpleNamespace
from typing import Any

import httpx
import jsonschema
import pytest

import app.calls.tts as tts_mod
from app.config import SHARED_DIR, settings
from app.main import RENDERS, app
from app.models import RenderPlanExtraction, RoomInfo, WorkItem
import app.rendering.service as render_service_mod
from app.rendering.service import (
    MAX_IMAGE_BYTES,
    build_default_project_fields,
    build_natural_replacement_prompt,
    build_plan_user_prompt,
    detect_image_mime,
)

# Minimal valid magic-byte payloads for JPEG, PNG, and WebP
FAKE_JPEG_BYTES: bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"
FAKE_PNG_BYTES: bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00"
FAKE_WEBP_BYTES: bytes = b"RIFF\x1a\x00\x00\x00WEBPVP8 \x0e\x00\x00\x000\x01\x00\x9d\x01*\x01\x00\x01\x00"


def make_pcm_samples(num_samples: int = 800) -> bytes:
    return b"\x10\x00" * num_samples


def load_json_schema(filename: str) -> dict[str, Any]:
    schema_path = SHARED_DIR / "schemas" / filename
    return json.loads(schema_path.read_text(encoding="utf-8"))


def make_valid_plan_extraction() -> RenderPlanExtraction:
    return RenderPlanExtraction(
        renovation_prompt=(
            "Strictly preserve the exact camera angle, perspective, room geometry, doors, "
            "and window position from the input photo. Renovate into a serene Japandi bedroom "
            "with matte warm off-white walls and wide-plank light oak parquet flooring. "
            "Photorealistic architectural interior render."
        ),
        voice_confirmation=(
            "Your Japandi bedroom render is ready, featuring warm off-white walls "
            "and natural oak parquet flooring while preserving your room layout."
        ),
        room=RoomInfo(type="bedroom", surface_m2=14, confidence="low"),
        style="japandi",
        work_items=[
            WorkItem(
                trade="painting",
                description="Walls and ceiling",
                quantity=38,
                unit="m2",
            ),
            WorkItem(
                trade="flooring",
                description="Oak parquet installation",
                quantity=14,
                unit="m2",
            ),
        ],
    )


def make_image_generation_response(image_bytes: bytes = FAKE_PNG_BYTES, mime_type: str = "image/png") -> Any:
    return SimpleNamespace(
        candidates=[
            SimpleNamespace(
                content=SimpleNamespace(
                    parts=[
                        SimpleNamespace(
                            inline_data=SimpleNamespace(
                                data=image_bytes,
                                mime_type=mime_type,
                            )
                        )
                    ]
                )
            )
        ]
    )


def make_tts_generation_response() -> Any:
    return SimpleNamespace(
        candidates=[
            SimpleNamespace(
                content=SimpleNamespace(
                    parts=[
                        SimpleNamespace(
                            inline_data=SimpleNamespace(
                                data=make_pcm_samples(600),
                                mime_type="audio/L16;rate=24000",
                            )
                        )
                    ]
                )
            )
        ]
    )


# ---------------------------------------------------------------------------
# 1. Mocked End-to-End Render Success & Schema Validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_render_end_to_end_success_and_schema_validation(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    RENDERS.clear()
    monkeypatch.setattr(settings, "render_replay", False)
    monkeypatch.setattr(settings, "gemini_api_key", "fake-test-key")

    req_schema = load_json_schema("render_request.schema.json")
    status_schema = load_json_schema("render_status.schema.json")

    plan_extraction = make_valid_plan_extraction()
    called_models: list[str] = []

    class FakeGeminiClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: Any, config: Any) -> Any:
                called_models.append(model)
                if model == settings.render_plan_model:
                    return SimpleNamespace(text=plan_extraction.model_dump_json())
                if model == settings.image_model:
                    return make_image_generation_response(FAKE_PNG_BYTES, "image/png")
                if model == settings.tts_model:
                    return make_tts_generation_response()
                raise AssertionError(f"Unexpected model call: {model}")

    monkeypatch.setattr(
        render_service_mod.genai, "Client", lambda **kw: FakeGeminiClient()
    )
    monkeypatch.setattr(
        tts_mod.genai, "Client", lambda **kw: FakeGeminiClient()
    )

    payload = {
        "image_base64": base64.b64encode(FAKE_JPEG_BYTES).decode("ascii"),
        "mime_type": "image/jpeg",
        "instruction": "Transform this bedroom into a serene Japandi style with warm off-white walls and light oak parquet flooring.",
        "city": "Paris",
        "country": "France",
    }
    jsonschema.validate(instance=payload, schema=req_schema)

    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        create_resp = await client.post("/renders", json=payload)
        assert create_resp.status_code == 202
        create_body = create_resp.json()
        assert create_body["status"] == "queued"
        render_id = create_body["render_id"]

        final_body: dict[str, Any] | None = None
        for _ in range(30):
            st_resp = await client.get(f"/renders/{render_id}")
            assert st_resp.status_code == 200
            body = st_resp.json()
            jsonschema.validate(instance=body, schema=status_schema)
            if body["status"] == "completed":
                final_body = body
                break
            await asyncio.sleep(0.02)

        assert final_body is not None
        assert final_body["status"] == "completed"
        assert final_body["phase"] == "done"
        assert final_body["is_replay"] is False
        assert final_body["error"] is None
        assert final_body["warnings"] == []

        result = final_body["result"]
        assert result is not None
        assert result["before_url"] == f"/renders/{render_id}/image/before"
        assert result["after_url"] == f"/renders/{render_id}/image/after"
        assert result["audio_url"] == f"/renders/{render_id}/audio"
        assert result["model_used"] == settings.image_model
        assert result["latency_ms"] >= 0
        assert result["room"]["type"] == "bedroom"
        assert result["style"] == "japandi"
        assert len(result["work_items"]) == 2

        # Verify before image endpoint
        before_resp = await client.get(result["before_url"])
        assert before_resp.status_code == 200
        assert before_resp.headers["content-type"] == "image/jpeg"
        assert before_resp.content == FAKE_JPEG_BYTES

        # Verify after image endpoint
        after_resp = await client.get(result["after_url"])
        assert after_resp.status_code == 200
        assert after_resp.headers["content-type"] == "image/png"
        assert after_resp.content == FAKE_PNG_BYTES

        # Verify audio endpoint returns valid RIFF WAV
        audio_resp = await client.get(result["audio_url"])
        assert audio_resp.status_code == 200
        assert audio_resp.headers["content-type"].startswith("audio/wav")
        assert audio_resp.content[:4] == b"RIFF"

    assert called_models == [
        settings.render_plan_model,
        settings.image_model,
        settings.tts_model,
    ]


# ---------------------------------------------------------------------------
# 2. Plan Fallback When RENDER_PLAN_MODEL Fails
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_render_plan_fallback_when_plan_model_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    RENDERS.clear()
    monkeypatch.setattr(settings, "render_replay", False)
    monkeypatch.setattr(settings, "gemini_api_key", "fake-test-key")

    class PlanFailingGeminiClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: Any, config: Any) -> Any:
                if model == settings.render_plan_model:
                    raise RuntimeError("Simulated RENDER_PLAN_MODEL 503 Unavailable")
                if model == settings.image_model:
                    return make_image_generation_response(FAKE_PNG_BYTES, "image/png")
                if model == settings.tts_model:
                    return make_tts_generation_response()
                raise AssertionError(f"Unexpected model: {model}")

    monkeypatch.setattr(
        render_service_mod.genai, "Client", lambda **kw: PlanFailingGeminiClient()
    )
    monkeypatch.setattr(
        tts_mod.genai, "Client", lambda **kw: PlanFailingGeminiClient()
    )

    brief = "Repaint walls warm off-white and install light oak parquet."
    payload = {
        "image_base64": base64.b64encode(FAKE_JPEG_BYTES).decode("ascii"),
        "mime_type": "image/jpeg",
        "instruction": brief,
    }

    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        create_resp = await client.post("/renders", json=payload)
        assert create_resp.status_code == 202
        render_id = create_resp.json()["render_id"]

        final_body: dict[str, Any] | None = None
        for _ in range(30):
            st_resp = await client.get(f"/renders/{render_id}")
            if st_resp.json()["status"] in ("completed", "failed"):
                final_body = st_resp.json()
                break
            await asyncio.sleep(0.02)

        assert final_body is not None
        assert final_body["status"] == "completed"
        assert final_body["phase"] == "done"
        assert any("Render plan model" in w for w in final_body["warnings"])
        assert final_body["result"]["renovation_prompt"] == build_natural_replacement_prompt(brief)
        default_room, default_style, default_items, _ = build_default_project_fields(brief)
        assert final_body["result"]["room"] == default_room.model_dump()
        assert final_body["result"]["style"] == default_style
        assert len(final_body["result"]["work_items"]) == len(default_items)


# ---------------------------------------------------------------------------
# 3. Image Model Fallback When IMAGE_MODEL Fails
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_image_model_fallback_to_secondary_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    RENDERS.clear()
    monkeypatch.setattr(settings, "render_replay", False)
    monkeypatch.setattr(settings, "gemini_api_key", "fake-test-key")

    plan_extraction = make_valid_plan_extraction()

    class PrimaryImageFailingGeminiClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: Any, config: Any) -> Any:
                if model == settings.render_plan_model:
                    return SimpleNamespace(text=plan_extraction.model_dump_json())
                if model == settings.image_model:
                    raise RuntimeError("Primary image model rate limited")
                if model == settings.image_fallback_model:
                    return make_image_generation_response(FAKE_PNG_BYTES, "image/png")
                if model == settings.tts_model:
                    return make_tts_generation_response()
                raise AssertionError(f"Unexpected model: {model}")

    monkeypatch.setattr(
        render_service_mod.genai,
        "Client",
        lambda **kw: PrimaryImageFailingGeminiClient(),
    )
    monkeypatch.setattr(
        tts_mod.genai, "Client", lambda **kw: PrimaryImageFailingGeminiClient()
    )

    payload = {
        "image_base64": base64.b64encode(FAKE_PNG_BYTES).decode("ascii"),
        "mime_type": "image/png",
        "instruction": "Renovate into Japandi bedroom.",
    }

    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        create_resp = await client.post("/renders", json=payload)
        assert create_resp.status_code == 202
        render_id = create_resp.json()["render_id"]

        final_body: dict[str, Any] | None = None
        for _ in range(30):
            st_resp = await client.get(f"/renders/{render_id}")
            if st_resp.json()["status"] in ("completed", "failed"):
                final_body = st_resp.json()
                break
            await asyncio.sleep(0.02)

        assert final_body is not None
        assert final_body["status"] == "completed"
        assert final_body["result"]["model_used"] == settings.image_fallback_model
        assert any("Primary image model" in w for w in final_body["warnings"])


# ---------------------------------------------------------------------------
# 4. Total Failure When Both Image Models Fail
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_render_total_failure_when_both_image_models_fail(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    RENDERS.clear()
    monkeypatch.setattr(settings, "render_replay", False)
    monkeypatch.setattr(settings, "gemini_api_key", "fake-test-key")

    plan_extraction = make_valid_plan_extraction()

    class AllImageModelsFailingClient:
        class models:
            @staticmethod
            def generate_content(model: str, contents: Any, config: Any) -> Any:
                if model == settings.render_plan_model:
                    return SimpleNamespace(text=plan_extraction.model_dump_json())
                raise RuntimeError(f"Model {model} unavailable")

    monkeypatch.setattr(
        render_service_mod.genai,
        "Client",
        lambda **kw: AllImageModelsFailingClient(),
    )

    payload = {
        "image_base64": base64.b64encode(FAKE_WEBP_BYTES).decode("ascii"),
        "mime_type": "image/webp",
        "instruction": "Renovate into Japandi bedroom.",
    }

    status_schema = load_json_schema("render_status.schema.json")
    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        create_resp = await client.post("/renders", json=payload)
        assert create_resp.status_code == 202
        render_id = create_resp.json()["render_id"]

        final_body: dict[str, Any] | None = None
        for _ in range(30):
            st_resp = await client.get(f"/renders/{render_id}")
            if st_resp.json()["status"] in ("completed", "failed"):
                final_body = st_resp.json()
                break
            await asyncio.sleep(0.02)

        assert final_body is not None
        jsonschema.validate(instance=final_body, schema=status_schema)
        assert final_body["status"] == "failed"
        assert final_body["phase"] == "done"
        assert final_body["result"] is None
        assert final_body["error"] is not None
        assert "Image generation failed on both" in final_body["error"]


# ---------------------------------------------------------------------------
# 5 & 6. 413 Payload Too Large & 415 Unsupported Media Type Validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_render_validation_413_and_415() -> None:
    RENDERS.clear()
    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        # 5. Exceeds 10 MB -> 413 Payload Too Large
        oversized_bytes = FAKE_JPEG_BYTES + (b"\x00" * (MAX_IMAGE_BYTES + 100))
        oversized_b64 = base64.b64encode(oversized_bytes).decode("ascii")
        resp_413 = await client.post(
            "/renders",
            json={
                "image_base64": oversized_b64,
                "mime_type": "image/jpeg",
                "instruction": "Renovate this room.",
            },
        )
        assert resp_413.status_code == 413

        # 6a. Non-image magic bytes -> 415 Unsupported Media Type
        non_image_b64 = base64.b64encode(b"not an image payload at all").decode("ascii")
        resp_415_magic = await client.post(
            "/renders",
            json={
                "image_base64": non_image_b64,
                "mime_type": "image/jpeg",
                "instruction": "Renovate this room.",
            },
        )
        assert resp_415_magic.status_code == 415

        # 6b. Valid PNG bytes but declared as image/jpeg -> 415 Mismatched mime_type
        png_b64 = base64.b64encode(FAKE_PNG_BYTES).decode("ascii")
        resp_415_mismatch = await client.post(
            "/renders",
            json={
                "image_base64": png_b64,
                "mime_type": "image/jpeg",
                "instruction": "Renovate this room.",
            },
        )
        assert resp_415_mismatch.status_code == 415


# ---------------------------------------------------------------------------
# 7. Replay Mode (RENDER_REPLAY=true) - Zero Gemini Calls & Fixture Parity
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_render_replay_mode_zero_gemini_calls_and_matches_demo_project(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    RENDERS.clear()
    monkeypatch.setattr(settings, "render_replay", True)

    def _forbid_gemini_client(**kwargs: Any) -> Any:
        raise AssertionError("genai.Client must not be called when RENDER_REPLAY=true")

    monkeypatch.setattr(render_service_mod.genai, "Client", _forbid_gemini_client)
    monkeypatch.setattr(tts_mod.genai, "Client", _forbid_gemini_client)

    demo_project = json.loads(
        (SHARED_DIR / "fixtures" / "demo_project.json").read_text(encoding="utf-8")
    )
    status_schema = load_json_schema("render_status.schema.json")

    payload = {
        "image_base64": f"data:image/jpeg;base64,{base64.b64encode(FAKE_JPEG_BYTES).decode('ascii')}",
        "mime_type": "image/jpeg",
        "instruction": "Renovate into a serene Japandi bedroom.",
    }

    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        create_resp = await client.post("/renders", json=payload)
        assert create_resp.status_code == 202
        render_id = create_resp.json()["render_id"]

        final_body: dict[str, Any] | None = None
        for _ in range(25):
            st_resp = await client.get(f"/renders/{render_id}")
            assert st_resp.status_code == 200
            body = st_resp.json()
            if body["status"] == "completed":
                final_body = body
                break
            await asyncio.sleep(0.01)

        assert final_body is not None
        jsonschema.validate(instance=final_body, schema=status_schema)
        assert final_body["is_replay"] is True
        assert final_body["status"] == "completed"
        assert final_body["phase"] == "done"

        result = final_body["result"]
        assert result is not None
        assert result["room"] == demo_project["room"]
        assert result["style"] == demo_project["style"]
        assert result["work_items"] == demo_project["work_items"]

        # Verify before, after, and audio endpoints serve the replay fixture assets
        before_resp = await client.get(result["before_url"])
        assert before_resp.status_code == 200
        assert before_resp.content[:3] == b"\xff\xd8\xff"

        after_resp = await client.get(result["after_url"])
        assert after_resp.status_code == 200
        assert after_resp.content[:8] == b"\x89PNG\r\n\x1a\n"

        audio_resp = await client.get(result["audio_url"])
        assert audio_resp.status_code == 200
        assert audio_resp.content[:4] == b"RIFF"


# ---------------------------------------------------------------------------
# 8 & 9. Unknown ID 404s, Prompt Delimiter Guardrail, and Schema Validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_unknown_render_id_returns_404_on_all_endpoints() -> None:
    RENDERS.clear()
    asgi_transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=asgi_transport, base_url="http://test"
    ) as client:
        for path in (
            "/renders/unknown-render-id",
            "/renders/unknown-render-id/image/before",
            "/renders/unknown-render-id/image/after",
            "/renders/unknown-render-id/audio",
        ):
            resp = await client.get(path)
            assert resp.status_code == 404


def test_prompt_delimiter_and_magic_byte_detection() -> None:
    assert detect_image_mime(FAKE_JPEG_BYTES) == "image/jpeg"
    assert detect_image_mime(FAKE_PNG_BYTES) == "image/png"
    assert detect_image_mime(FAKE_WEBP_BYTES) == "image/webp"
    assert detect_image_mime(b"GIF89a") is None

    prompt = build_plan_user_prompt(
        "Warm off-white walls and light oak parquet",
        city="Paris",
        country="France",
    )
    assert "<user_renovation_brief>" in prompt
    assert "</user_renovation_brief>" in prompt
    assert "Paris, France" in prompt
