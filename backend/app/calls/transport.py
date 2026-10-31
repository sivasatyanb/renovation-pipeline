"""CallTransport interface and SimulatedCallTransport implementation."""

from __future__ import annotations

from abc import ABC, abstractmethod
import asyncio
import time
from typing import Any

from app.calls.agents import generate_agent_turn
from app.calls.tts import synthesize_turn_wav
from app.config import settings
from app.models import CallTurn, SpeakerRole


class CallTransport(ABC):
    """Abstract transport interface for running a two-sided voice call."""

    @abstractmethod
    async def run_conversation(self, call_record: Any) -> None:
        """Run the conversational turns and populate call_record.turns and audio_by_turn."""


class SimulatedCallTransport(CallTransport):
    """Alternates isolated Customer Agent and Renovator Agent turns with TTS synthesis."""

    def __init__(self, gemini_client: Any | None = None) -> None:
        self.gemini_client = gemini_client

    async def run_conversation(self, call_record: Any) -> None:
        max_turns = max(1, int(settings.max_call_turns))
        timeout_sec = float(settings.call_timeout_seconds)
        start_monotonic = time.monotonic()
        client = self.gemini_client or getattr(call_record, "gemini_client", None)

        async def _execute_turns() -> None:
            for index in range(max_turns):
                if call_record.stop_requested:
                    call_record.status = "stopped"
                    call_record.phase = "done"
                    return

                elapsed = time.monotonic() - start_monotonic
                remaining = timeout_sec - elapsed
                if remaining <= 0:
                    raise asyncio.TimeoutError("Call exceeded CALL_TIMEOUT_SECONDS.")

                speaker: SpeakerRole = (
                    "customer_agent" if index % 2 == 0 else "renovator_agent"
                )
                system_prompt = (
                    call_record.customer_prompt
                    if speaker == "customer_agent"
                    else call_record.renovator_prompt
                )

                turn_out = await asyncio.wait_for(
                    generate_agent_turn(
                        system_prompt=system_prompt,
                        transcript=list(call_record.turns),
                        speaker=speaker,
                        client=client,
                    ),
                    timeout=remaining,
                )

                if call_record.stop_requested:
                    call_record.status = "stopped"
                    call_record.phase = "done"
                    return

                elapsed = time.monotonic() - start_monotonic
                remaining = max(0.01, timeout_sec - elapsed)
                wav_bytes, tts_warning = await asyncio.wait_for(
                    synthesize_turn_wav(
                        text=turn_out.text,
                        speaker=speaker,
                        client=client,
                    ),
                    timeout=remaining,
                )

                if call_record.stop_requested:
                    call_record.status = "stopped"
                    call_record.phase = "done"
                    return

                if wav_bytes is not None:
                    call_record.audio_by_turn[index] = wav_bytes
                    audio_url: str | None = f"/calls/{call_record.call_id}/audio/{index}"
                else:
                    audio_url = None
                    if tts_warning:
                        call_record.warnings.append(tts_warning)

                call_record.turns.append(
                    CallTurn(
                        index=index,
                        speaker=speaker,
                        text=turn_out.text,
                        audio_url=audio_url,
                    )
                )

                if turn_out.end_call and index >= 1:
                    call_record.agent_end_reason = (
                        turn_out.end_reason or "agreement"
                    )
                    return

            call_record.hit_turn_limit = True

        try:
            await asyncio.wait_for(_execute_turns(), timeout=timeout_sec)
        except (asyncio.TimeoutError, TimeoutError):
            call_record.timed_out = True
            call_record.warnings.append(
                f"Call timed out after {timeout_sec}s limit."
            )
