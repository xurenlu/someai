"""STT API - POST /stt/transcribe"""
from __future__ import annotations

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import JSONResponse

from .config import APP_VERSION
from .stt_service import transcribe

router = APIRouter()


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/stt/transcribe", response_class=JSONResponse)
async def stt_transcribe_endpoint(file: UploadFile = File(...)):
    audio = await file.read()
    text = await transcribe(audio)
    return JSONResponse(content={"text": text}, headers=_version_header())
