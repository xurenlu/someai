"""TTS API - POST /tts/generate"""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from .config import APP_VERSION
from .tts_service import ModelNotLoadedError, generate as tts_generate

router = APIRouter()
logger = logging.getLogger(__name__)


class TTSGenerateRequest(BaseModel):
    text: str
    language: str = "zh"
    speaker: str = "default"
    model_id: str | None = None


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/tts/generate")
async def tts_generate_endpoint(req: TTSGenerateRequest):
    try:
        audio, media_type = await tts_generate(
            req.text, req.language, req.speaker, model_id=req.model_id
        )
        return Response(
            content=audio,
            media_type=media_type,
            headers={**_version_header(), "Content-Disposition": "inline"},
        )
    except ModelNotLoadedError as e:
        raise HTTPException(
            status_code=503,
            detail={"code": "MODEL_NOT_LOADED", "message": str(e), "model_id": e.model_id},
        )
