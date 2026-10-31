"""End-to-end stage script verification test."""

import asyncio
import base64
import json
from pathlib import Path
import httpx
import pytest

from app.config import SHARED_DIR, settings
from app.main import app, JOBS, CALLS, RENDERS

@pytest.mark.asyncio
async def test_full_stage_script_e2e(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "demo_mode", True)
    monkeypatch.setattr(settings, "call_replay", True)
    monkeypatch.setattr(settings, "render_replay", True)
    monkeypatch.setattr(settings, "demo_phase_durations", (0.01, 0.01, 0.01))

    # Read fixtures
    before_jpg_path = SHARED_DIR / "fixtures" / "demo_render" / "before.jpg"
    before_bytes = before_jpg_path.read_bytes()
    before_b64 = base64.b64encode(before_bytes).decode("ascii")

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # Step 1: POST /renders
        instruction = "Keep the window and room layout. Paint the walls and ceiling warm off-white and lay oak parquet for a Japandi bedroom."
        render_payload = {
            "image_base64": f"data:image/jpeg;base64,{before_b64}",
            "mime_type": "image/jpeg",
            "instruction": instruction,
            "city": "Paris",
            "country": "France",
        }
        res = await client.post("/renders", json=render_payload)
        assert res.status_code == 202, f"POST /renders failed: {res.text}"
        render_id = res.json()["render_id"]
        assert render_id

        # Step 2: Poll GET /renders/{render_id}
        render_result = None
        for _ in range(30):
            st = await client.get(f"/renders/{render_id}")
            assert st.status_code == 200
            data = st.json()
            if data["status"] == "completed":
                render_result = data
                break
            await asyncio.sleep(0.02)

        assert render_result is not None, "Render did not complete in time"
        assert render_result["status"] == "completed"
        assert render_result["phase"] == "done"
        assert render_result["is_replay"] is True

        res_body = render_result["result"]
        assert res_body is not None
        assert res_body["room"]["type"] == "bedroom"
        assert res_body["room"]["surface_m2"] == 14
        assert res_body["style"].lower() == "japandi"

        work_items = res_body["work_items"]
        trades = {w["trade"]: w for w in work_items}
        assert "painting" in trades
        assert trades["painting"]["quantity"] == 38
        assert "flooring" in trades
        assert trades["flooring"]["quantity"] == 14

        # Check endpoints
        before_resp = await client.get(f"/renders/{render_id}/image/before")
        assert before_resp.status_code == 200
        assert before_resp.content[:3] == b"\xff\xd8\xff", "Magic bytes for JPEG match"

        after_resp = await client.get(f"/renders/{render_id}/image/after")
        assert after_resp.status_code == 200
        assert after_resp.content[:8] == b"\x89PNG\r\n\x1a\n", "Magic bytes for PNG match"

        audio_resp = await client.get(f"/renders/{render_id}/audio")
        assert audio_resp.status_code == 200
        assert audio_resp.content[:4] == b"RIFF", "Magic bytes for WAV audio match"

        # Step 3: Construct ResearchRequest using Studio output
        research_payload = {
            "project": {
                "project_id": f"proj-{render_id}",
                "client": {"city": "Paris", "country": "France"},
                "room": res_body["room"],
                "style": res_body["style"],
                "work_items": res_body["work_items"],
                "render_urls": [res_body["after_url"]],
            },
            "answers": {
                "budget": "5k_15k",
                "scope": "partial",
                "timeline": "one_to_three_months",
                "priority": "balanced",
                "trust_requirements": ["licensed_insured"],
            },
        }

        # Step 4: POST /research -> poll GET /research/{job_id}
        res_res = await client.post("/research", json=research_payload)
        assert res_res.status_code == 200, f"POST /research failed: {res_res.text}"
        job_id = res_res.json()["job_id"]

        job_result = None
        for _ in range(30):
            st = await client.get(f"/research/{job_id}")
            assert st.status_code == 200
            data = st.json()
            if data["status"] == "completed":
                job_result = data
                break
            await asyncio.sleep(0.02)

        assert job_result is not None, "Research did not complete in time"
        contractors = job_result["result"]["contractors"]
        assert len(contractors) > 0
        top_contractor = contractors[0]
        assert "Atelier Kanso" in top_contractor["name"], f"Expected Atelier Kanso, got {top_contractor['name']}"
        top_contractor_id = top_contractor["id"]

        # Step 5: POST /calls for Atelier Kanso -> poll GET /calls/{call_id}
        call_payload = {
            "job_id": job_id,
            "contractor_id": top_contractor_id,
            "meeting": {
                "customer_email": "demo.customer@example.com",
                "address": "12 Rue de Rivoli, 75004 Paris, France",
                "slots": [
                    "2026-11-02T10:00:00+01:00",
                    "2026-11-02T14:00:00+01:00",
                    "2026-11-02T17:00:00+01:00",
                ],
            },
        }

        call_res = await client.post("/calls", json=call_payload)
        assert call_res.status_code == 200, f"POST /calls failed: {call_res.text}"
        call_id = call_res.json()["call_id"]

        call_result = None
        for _ in range(30):
            st = await client.get(f"/calls/{call_id}")
            assert st.status_code == 200
            data = st.json()
            if data["status"] == "completed":
                call_result = data
                break
            await asyncio.sleep(0.02)

        assert call_result is not None, "Call did not complete in time"
        assert call_result["is_replay"] is True
        assert len(call_result["turns"]) == 7

        # Confirm all 7 turns have RIFF audio
        for i in range(7):
            audio_turn_res = await client.get(f"/calls/{call_id}/audio/{i}")
            assert audio_turn_res.status_code == 200, f"Turn audio {i} status was {audio_turn_res.status_code}"
            assert audio_turn_res.content[:4] == b"RIFF", f"Turn audio {i} does not have RIFF magic bytes"

        outcome = call_result["outcome"]
        assert outcome["opening_price"] == 9200.0
        assert outcome["final_price"] == 8200.0
        assert outcome["currency"] == "EUR"

        match = call_result["match"]
        assert match["match"] is True

        booking = call_result["booking"]
        assert booking is not None
        assert booking["event_url"] is not None
        assert "calendar" in booking["event_url"].lower()
