"""TTS synthesis using TTS_MODEL and PCM/WAV wrapping with Python's wave module."""

from __future__ import annotations

import asyncio
import io
import re
from typing import Any
import wave

from google import genai
from google.genai import types

from app.config import settings
from app.models import SpeakerRole


def pcm_or_wav_to_wav(raw_bytes: bytes, mime_type: str = "") -> bytes:
    """Convert raw PCM bytes or an existing RIFF WAV buffer into a clean WAV byte buffer."""
    if not raw_bytes:
        raise ValueError("Empty audio payload received from TTS model.")

    out_buf = io.BytesIO()
    if raw_bytes[:4] == b"RIFF":
        with wave.open(io.BytesIO(raw_bytes), "rb") as reader:
            nchannels = reader.getnchannels()
            sampwidth = reader.getsampwidth()
            framerate = reader.getframerate()
            frames = reader.readframes(reader.getnframes())
        with wave.open(out_buf, "wb") as writer:
            writer.setnchannels(nchannels)
            writer.setsampwidth(sampwidth)
            writer.setframerate(framerate)
            writer.writeframes(frames)
        return out_buf.getvalue()

    rate_match = re.search(r"rate=(\d+)", mime_type or "", flags=re.IGNORECASE)
    sample_rate = int(rate_match.group(1)) if rate_match else 24000

    with wave.open(out_buf, "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(sample_rate)
        writer.writeframes(raw_bytes)
    return out_buf.getvalue()


def _call_tts_model(
    client: Any,
    model_id: str,
    text: str,
    voice_name: str,
) -> tuple[bytes, str]:
    response = client.models.generate_content(
        model=model_id,
        contents=text,
        config=types.GenerateContentConfig(
            response_modalities=["AUDIO"],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=voice_name,
                    )
                )
            ),
        ),
    )
    candidates = getattr(response, "candidates", None) or []
    if not candidates:
        raise RuntimeError("TTS response contained no candidates.")
    content = getattr(candidates[0], "content", None)
    parts = getattr(content, "parts", None) or []
    if not parts:
        raise RuntimeError("TTS response candidate contained no parts.")
    inline_data = getattr(parts[0], "inline_data", None)
    if inline_data is None or not getattr(inline_data, "data", None):
        raise RuntimeError("TTS response part contained no inline audio data.")
    raw_bytes: bytes = inline_data.data
    mime_type: str = getattr(inline_data, "mime_type", "") or ""
    return raw_bytes, mime_type


async def synthesize_turn_wav(
    text: str,
    speaker: SpeakerRole,
    client: Any | None = None,
) -> tuple[bytes | None, str | None]:
    """Synthesize a turn's text into WAV bytes. Never raises; returns (None, warning) on failure."""
    voice_name = (
        settings.buyer_voice
        if speaker == "customer_agent"
        else settings.seller_voice
    )
    try:
        if client is None:
            if not settings.gemini_api_key:
                raise RuntimeError("GEMINI_API_KEY is not configured.")
            client = genai.Client(api_key=settings.gemini_api_key)

        raw_bytes, mime_type = await asyncio.to_thread(
            _call_tts_model,
            client,
            settings.tts_model,
            text,
            voice_name,
        )
        wav_bytes = pcm_or_wav_to_wav(raw_bytes, mime_type=mime_type)
        return wav_bytes, None
    except Exception as exc:
        return None, f"TTS synthesis failed for turn ({speaker}): {exc}"
