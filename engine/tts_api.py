"""TTS API - POST /tts/generate"""
from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import Response
from pydantic import BaseModel

from .config import APP_VERSION
from .tts_service import generate as tts_generate

router = APIRouter()


class TTSGenerateRequest(BaseModel):
    text: str
    language: str = "zh"
    speaker: str = "default"


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/tts/generate")
async def tts_generate_endpoint(req: TTSGenerateRequest):
    audio = await tts_generate(req.text, req.language, req.speaker)
    return Response(
        content=audio,
        media_type="audio/wav",
        headers={**_version_header(), "Content-Disposition": "inline"},
    )
