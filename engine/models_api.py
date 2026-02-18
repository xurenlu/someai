"""
Ollama-style model query API.
GET /models, GET /models/loaded, GET /models/{id}
"""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from .config import APP_VERSION, MODELS_JSON

router = APIRouter()


def _version_header():
    return {"X-App-Version": APP_VERSION}


def _load_models_config() -> list[dict]:
    """Load model metadata from config/models.json."""
    if not MODELS_JSON.exists():
        return []
    try:
        with open(MODELS_JSON, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("models", [])
    except (json.JSONDecodeError, IOError):
        return []


def _get_model_by_id(model_id: str) -> dict | None:
    """Find model by id in config."""
    models = _load_models_config()
    for m in models:
        if m.get("id") == model_id:
            return m
    return None


def _check_installed(model: dict) -> bool:
    """Check if model files exist (placeholder - will be enhanced in M5)."""
    models_dir = Path(__file__).resolve().parent.parent / "models"
    model_type = model.get("type", "")
    subdir = {"llm": "llm", "tts": "tts", "stt": "stt", "image": "sd"}.get(model_type, model_type)
    model_path = models_dir / subdir / model.get("id", "")
    return model_path.exists() if model_path else False


@router.get("/models", response_class=JSONResponse)
async def list_models():
    """List all installed/available models for Model Manager."""
    models = _load_models_config()
    result = []
    for m in models:
        installed = _check_installed(m)
        result.append({
            "id": m.get("id", ""),
            "name": m.get("name", m.get("id", "")),
            "type": m.get("type", "llm"),
            "capabilities": m.get("capabilities", []),
            "status": "installed" if installed else "not_downloaded",
            "size_bytes": m.get("size_bytes", 0),
            "quantization": m.get("quantization"),
            "version": m.get("version", APP_VERSION),
            "updated_at": m.get("updated_at"),
        })
    return JSONResponse(
        content={"models": result},
        headers=_version_header(),
    )


@router.get("/models/loaded", response_class=JSONResponse)
async def list_loaded_models():
    """List currently loaded models and resource usage."""
    import time
    from . import runtime
    from .memory_watchdog import get_current_memory_mb
    from .task_queue import queue_size
    uptime = int(time.monotonic() - runtime.engine_start_time) if runtime.engine_start_time else 0
    return JSONResponse(
        content={
            "loaded_models": [],
            "engine": {
                "queue_size": queue_size(),
                "uptime_sec": uptime,
                "memory_mb": round(get_current_memory_mb(), 1),
            },
        },
        headers=_version_header(),
    )


@router.get("/models/{model_id}", response_class=JSONResponse)
async def get_model(model_id: str):
    """Get single model details by id."""
    model = _get_model_by_id(model_id)
    if not model:
        raise HTTPException(
            status_code=404,
            detail={"code": "MODEL_NOT_FOUND", "message": f"model not found: {model_id}"},
        )
    installed = _check_installed(model)
    status = "installed" if installed else "not_downloaded"

    return JSONResponse(
        content={
            "id": model.get("id", ""),
            "name": model.get("name", model.get("id", "")),
            "type": model.get("type", "llm"),
            "family": model.get("family"),
            "capabilities": model.get("capabilities", []),
            "status": status,
            "context_length": model.get("context_length"),
            "languages": model.get("languages", []),
            "default_params": model.get("default_params", {}),
            "runtime": model.get("runtime") if status == "loaded" else None,
            "version": model.get("version", APP_VERSION),
        },
        headers=_version_header(),
    )
