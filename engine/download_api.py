"""Model download API - POST /models/download, GET /models/download/stream"""
from __future__ import annotations

import asyncio
import json
from pathlib import Path
from queue import Empty, Queue

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel

from .config import APP_VERSION
from .models_api import _get_model_by_id

router = APIRouter()

# HuggingFace repo mapping (16GB M2 Mac friendly)
HF_REPOS = {
    "qwen2.5-0.5b-instruct": "Qwen/Qwen2.5-0.5B-Instruct",
    "qwen2.5-1.5b-instruct": "Qwen/Qwen2.5-1.5B-Instruct",
    "qwen2.5-3b-instruct": "Qwen/Qwen2.5-3B-Instruct",
    "qwen3.5-0.8b-instruct": "Qwen/Qwen3.5-0.8B",
    "qwen3.5-2b-instruct": "Qwen/Qwen3.5-2B",
    "qwen3.5-4b-instruct": "Qwen/Qwen3.5-4B",
    "qwen3.5-9b-instruct": "Qwen/Qwen3.5-9B",
    "tinyllama-1.1b-chat": "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    "phi-2": "microsoft/phi-2",
    "qwen3-tts-12hz-0.6b": "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice",
    "whisper-tiny": "openai/whisper-tiny",
    "whisper-small": "openai/whisper-small",
    "sd-1.5": "runwayml/stable-diffusion-v1-5",
    # Visual tokenizers
    "vtp-small-f16d64": "MiniMaxAI/VTP-Small-f16d64",
    "vtp-base-f16d64": "MiniMaxAI/VTP-Base-f16d64",
    "vtp-large-f16d64": "MiniMaxAI/VTP-Large-f16d64",
    "siglip-base-patch16-224": "google/siglip-base-patch16-224",
    "siglip-base-patch16-384": "google/siglip-base-patch16-384",
    "trocr-base-printed": "microsoft/trocr-base-printed",
    "google-gemma-4-e2b-it": "google/gemma-4-E2B-it",
    "google-gemma-4-e4b-it": "google/gemma-4-E4B-it",
}

def _version_header():
    return {"X-App-Version": APP_VERSION}


def _make_progress_tqdm(queue: Queue):
    """Create a tqdm subclass that pushes progress to a queue."""
    from tqdm.auto import tqdm as base_tqdm

    class ProgressTqdm(base_tqdm):
        def update(self, n=1):
            super().update(n)
            try:
                queue.put_nowait({
                    "downloaded": self.n,
                    "total": self.total if self.total else 0,
                    "unit": getattr(self, "unit", "B"),
                    "unit_scale": getattr(self, "unit_scale", True),
                })
            except Exception:
                pass

    return ProgressTqdm


def _do_download(repo: str, local_dir: Path, progress_queue: Queue | None = None):
    """Run snapshot_download, optionally with progress reporting. Puts sentinel when done."""
    from huggingface_hub import snapshot_download

    kwargs = {"repo_id": repo, "local_dir": str(local_dir)}
    if progress_queue is not None:
        kwargs["tqdm_class"] = _make_progress_tqdm(progress_queue)
    try:
        result = snapshot_download(**kwargs)
        if progress_queue is not None:
            progress_queue.put({"done": True, "local_dir": str(local_dir)})
        return result
    except Exception as e:
        if progress_queue is not None:
            progress_queue.put({"done": True, "error": str(e)})
        raise


class DownloadRequest(BaseModel):
    model_id: str


def _get_hf_repo(model: dict, model_id: str) -> str | None:
    """Get HuggingFace repo: from model.hf_repo first, else from HF_REPOS mapping."""
    return model.get("hf_repo") or HF_REPOS.get(model_id)


@router.post("/models/download", response_class=JSONResponse)
async def download_model(req: DownloadRequest):
    """Trigger model download via huggingface_hub. Supports resume on retry (skips already-downloaded files)."""
    model = _get_model_by_id(req.model_id)
    if not model:
        raise HTTPException(
            status_code=404,
            detail={"code": "MODEL_NOT_FOUND", "message": f"model not found: {req.model_id}"},
        )
    repo = _get_hf_repo(model, req.model_id)
    if not repo:
        raise HTTPException(
            status_code=400,
            detail={"code": "DOWNLOAD_NOT_SUPPORTED", "message": f"download not configured for {req.model_id}"},
        )
    models_dir = Path(__file__).resolve().parent.parent / "models"
    model_type = model.get("type", "llm")
    subdir = {"llm": "llm", "tts": "tts", "stt": "stt", "image": "sd", "vision": "vision", "ocr": "ocr"}.get(model_type, model_type)
    local_dir = models_dir / subdir / req.model_id
    local_dir.mkdir(parents=True, exist_ok=True)
    try:
        loop = asyncio.get_running_loop()
        await asyncio.wait_for(
            loop.run_in_executor(
                None,
                lambda: _do_download(repo, local_dir),
            ),
            timeout=3600,
        )
        return JSONResponse(
            content={"status": "ok", "model_id": req.model_id, "local_dir": str(local_dir)},
            headers=_version_header(),
        )
    except HTTPException:
        raise
    except asyncio.TimeoutError:
        raise HTTPException(
            status_code=504,
            detail={"code": "DOWNLOAD_TIMEOUT", "message": "download timed out"},
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"code": "DOWNLOAD_FAILED", "message": str(e)},
        )


@router.get("/models/download/stream")
async def download_model_stream(
    model_id: str = Query(..., description="Model ID to download"),
):
    """Stream download progress via Server-Sent Events. Supports resume on retry."""
    model = _get_model_by_id(model_id)
    if not model:
        raise HTTPException(
            status_code=404,
            detail={"code": "MODEL_NOT_FOUND", "message": f"model not found: {model_id}"},
        )
    repo = _get_hf_repo(model, model_id)
    if not repo:
        raise HTTPException(
            status_code=400,
            detail={"code": "DOWNLOAD_NOT_SUPPORTED", "message": f"download not configured for {model_id}"},
        )
    models_dir = Path(__file__).resolve().parent.parent / "models"
    model_type = model.get("type", "llm")
    subdir = {"llm": "llm", "tts": "tts", "stt": "stt", "image": "sd", "vision": "vision", "ocr": "ocr"}.get(model_type, model_type)
    local_dir = models_dir / subdir / model_id
    local_dir.mkdir(parents=True, exist_ok=True)

    progress_queue: Queue = Queue()

    async def event_generator():
        loop = asyncio.get_running_loop()
        download_task = asyncio.create_task(
            loop.run_in_executor(
                None,
                lambda: _do_download(repo, local_dir, progress_queue),
            ),
        )

        def get_progress():
            return progress_queue.get(timeout=0.8)

        last_progress: dict = {}
        while not download_task.done():
            try:
                progress = await asyncio.wait_for(
                    loop.run_in_executor(None, get_progress),
                    timeout=1.5,
                )
                last_progress = progress
                if progress.get("done"):
                    yield f"data: {json.dumps(progress)}\n\n"
                    return
                yield f"data: {json.dumps(progress)}\n\n"
            except (Empty, asyncio.TimeoutError):
                yield f"data: {json.dumps({**last_progress, 'heartbeat': True})}\n\n"

        try:
            await download_task
            if "local_dir" not in last_progress:
                yield f"data: {json.dumps({'done': True, 'local_dir': str(local_dir)})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'done': True, 'error': str(e)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            **_version_header(),
        },
    )
