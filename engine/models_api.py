"""
Ollama-style model query API.
GET /models, GET /models/loaded, GET /models/{id}
DELETE /models/{id} - remove local model files
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from .config import APP_VERSION, MODELS_JSON, MODELS_DIR

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


def _model_subdir(model_type: str) -> str:
    return {"llm": "llm", "tts": "tts", "stt": "stt", "image": "sd"}.get(model_type, model_type)


def _get_model_local_dir(model: dict) -> Path | None:
    """Return local directory path if it exists (may be empty)."""
    model_type = model.get("type", "")
    subdir = _model_subdir(model_type)
    local_path = MODELS_DIR / subdir / model.get("id", "")
    return local_path if local_path.exists() else None


def _dir_has_files(path: Path) -> bool:
    """Check if directory contains at least one file."""
    try:
        return any(p.is_file() for p in path.rglob("*"))
    except OSError:
        return False


def _dir_size_bytes(path: Path) -> int:
    """Recursively sum file sizes in directory."""
    total = 0
    try:
        for p in path.rglob("*"):
            if p.is_file():
                total += p.stat().st_size
    except OSError:
        pass
    return total


def _dir_file_extensions(path: Path) -> list[str]:
    """Return unique file extensions in directory (e.g. ['.safetensors', '.json'])."""
    exts = set()
    try:
        for p in path.rglob("*"):
            if p.is_file() and p.suffix:
                exts.add(p.suffix.lower())
    except OSError:
        pass
    return sorted(exts)


def _check_installed(model: dict) -> bool:
    """Check if model files exist (directory must have at least one file)."""
    local_dir = _get_model_local_dir(model)
    return local_dir is not None and _dir_has_files(local_dir)


@router.get("/models", response_class=JSONResponse)
async def list_models():
    """List all installed/available models for Model Manager."""
    models = _load_models_config()
    result = []
    for m in models:
        installed = _check_installed(m)
        local_dir = _get_model_local_dir(m)
        actual_size = _dir_size_bytes(local_dir) if local_dir else None
        file_types = _dir_file_extensions(local_dir) if local_dir else []
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
            "local_dir": str(local_dir) if local_dir else None,
            "actual_size_bytes": actual_size,
            "file_types": file_types,
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


@router.delete("/models/{model_id}", response_class=JSONResponse)
async def delete_model(model_id: str):
    """Delete local model files. Allows re-download."""
    model = _get_model_by_id(model_id)
    if not model:
        raise HTTPException(
            status_code=404,
            detail={"code": "MODEL_NOT_FOUND", "message": f"model not found: {model_id}"},
        )
    local_dir = _get_model_local_dir(model)
    if not local_dir:
        return JSONResponse(
            content={"status": "ok", "model_id": model_id, "message": "not installed"},
            headers=_version_header(),
        )
    try:
        shutil.rmtree(local_dir)
    except OSError as e:
        raise HTTPException(
            status_code=500,
            detail={"code": "DELETE_FAILED", "message": str(e)},
        )
    return JSONResponse(
        content={"status": "ok", "model_id": model_id},
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
