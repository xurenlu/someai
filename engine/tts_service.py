"""
TTS service - placeholder for M2, real model loading in M5.
"""
from __future__ import annotations

import io
import struct
import wave


def generate_placeholder_wav(duration_sec: float = 0.5, sample_rate: int = 22050) -> bytes:
    """Generate a short silent WAV as placeholder."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        nframes = int(sample_rate * duration_sec)
        w.writeframes(struct.pack(f"<{nframes}h", *([0] * nframes)))
    return buf.getvalue()


async def generate(text: str, language: str = "zh", speaker: str = "default") -> bytes:
    """Generate audio from text. Placeholder until model is loaded."""
    return generate_placeholder_wav(0.5)
