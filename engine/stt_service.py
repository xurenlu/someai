"""
STT service - Speech-to-Text using faster-whisper.
"""
from __future__ import annotations

import tempfile
from pathlib import Path

_whisper_model = None


def _get_whisper_model():
    """Lazy-load Whisper model. Uses tiny (auto-download ~75MB) for minimal footprint."""
    global _whisper_model
    if _whisper_model is not None:
        return _whisper_model
    from faster_whisper import WhisperModel

    _whisper_model = WhisperModel("tiny", device="cpu", compute_type="int8")
    return _whisper_model


async def transcribe(audio_bytes: bytes) -> str:
    """Transcribe audio to text using faster-whisper."""
    import asyncio

    def _run():
        model = _get_whisper_model()
        # faster-whisper expects file path or (bytes, sample_rate)
        # For raw bytes we need to know format - assume 16kHz mono WAV from iOS
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(audio_bytes)
            path = f.name
        try:
            segments, info = model.transcribe(path, language=None, beam_size=1, vad_filter=True)
            text = " ".join(s.text.strip() for s in segments if s.text.strip())
            return text or "(无语音识别结果)"
        finally:
            Path(path).unlink(missing_ok=True)

    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _run)
