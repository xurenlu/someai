"""Model download API - POST /models/download"""
from __future__ import annotations

import subprocess
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .config import APP_VERSION, MODELS_JSON
from .models_api import _get_model_by_id

router = APIRouter()

# HuggingFace repo mapping
HF_REPOS = {
    "qwen2.5-1.5b-instruct": "Qwen/Qwen2.5-1.5B-Instruct",
    "qwen3-tts-12hz-0.6b": "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
    "whisper-small": "openai/whisper-small",
    "sd-1.5": "runwayml/stable-diffusion-v1-5",
}


def _version_header():
    return {"X-App-Version": APP_VERSION}


class DownloadRequest(BaseModel):
    model_id: str


@router.post("/models/download", response_class=JSONResponse)
async def download_model(req: DownloadRequest):
    """Trigger model download via huggingface_hub."""
    model = _get_model_by_id(req.model_id)
    if not model:
        raise HTTPException(
            status_code=404,
            detail={"code": "MODEL_NOT_FOUND", "message": f"model not found: {req.model_id}"},
        )
    repo = HF_REPOS.get(req.model_id)
    if not repo:
        raise HTTPException(
            status_code=400,
            detail={"code": "DOWNLOAD_NOT_SUPPORTED", "message": f"download not configured for {req.model_id}"},
        )
    models_dir = Path(__file__).resolve().parent.parent / "models"
    model_type = model.get("type", "llm")
    subdir = {"llm": "llm", "tts": "tts", "stt": "stt", "image": "sd"}.get(model_type, model_type)
    local_dir = models_dir / subdir / req.model_id
    local_dir.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["python3", "-m", "huggingface_hub", "download", repo, "--local-dir", str(local_dir)],
            capture_output=True,
            timeout=3600,
            check=False,
        )
        return JSONResponse(
            content={"status": "ok", "model_id": req.model_id, "local_dir": str(local_dir)},
            headers=_version_header(),
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(
            status_code=504,
            detail={"code": "DOWNLOAD_TIMEOUT", "message": "download timed out"},
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"code": "DOWNLOAD_FAILED", "message": str(e)},
        )
