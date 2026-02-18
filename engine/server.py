"""
MacAIStudio Local AI Engine - FastAPI Server
Base URL: http://127.0.0.1:18080
"""
from __future__ import annotations

import asyncio
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse

from .config import APP_VERSION
from .llms_txt import generate_llms_txt
from . import runtime
from .download_api import router as download_router
from .image_api import router as image_router
from .llm_api import router as llm_router
from .models_api import router as models_router
from .ocr_api import router as ocr_router
from .stt_api import router as stt_router
from .tts_api import router as tts_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    runtime.engine_start_time = time.monotonic()
    # Apply memory limit from env (set by Swift app when configured)
    try:
        limit_mb = int(os.environ.get("ENGINE_MEMORY_LIMIT_MB", "0") or "0")
    except ValueError:
        limit_mb = 0
    if limit_mb > 0:
        from .memory_watchdog import set_memory_limit

        if set_memory_limit(limit_mb):
            import logging

            logging.getLogger(__name__).info("Memory limit set to %d MB", limit_mb)
    # Start model idle check loop (unloads models after ENGINE_IDLE_TIMEOUT_MINUTES)
    from .model_registry import idle_check_loop
    idle_task = asyncio.create_task(idle_check_loop())
    try:
        yield
    finally:
        idle_task.cancel()
        try:
            await idle_task
        except asyncio.CancelledError:
            pass


app = FastAPI(
    title="MacAIStudio Engine",
    version=APP_VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _version_header():
    return {"X-App-Version": APP_VERSION}


@app.get("/llms.txt", response_class=PlainTextResponse)
@app.get("/llm.txt", response_class=PlainTextResponse)
async def llms_txt(request: Request):
    """Serve llms.txt manifest for LLM-friendly API documentation."""
    base = str(request.base_url).rstrip("/")
    return PlainTextResponse(
        content=generate_llms_txt(base),
        headers={"X-App-Version": APP_VERSION, "Content-Type": "text/plain; charset=utf-8"},
    )


@app.get("/health", response_class=JSONResponse)
async def health():
    """Health check - returns status and loaded model types."""
    from .model_registry import get_loaded_models
    return JSONResponse(
        content={
            "status": "ok",
            "models_loaded": get_loaded_models(),
        },
        headers=_version_header(),
    )


app.include_router(download_router, prefix="", tags=["download"])
app.include_router(image_router, prefix="", tags=["image"])
app.include_router(llm_router, prefix="", tags=["llm"])
app.include_router(models_router, prefix="", tags=["models"])
app.include_router(ocr_router, prefix="", tags=["ocr"])
app.include_router(stt_router, prefix="", tags=["stt"])
app.include_router(tts_router, prefix="", tags=["tts"])


@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc: HTTPException):
    detail = exc.detail
    if isinstance(detail, dict):
        code = detail.get("code", "UNKNOWN")
        message = detail.get("message", str(detail))
        model_id = detail.get("model_id")
    else:
        code = "UNKNOWN"
        message = str(detail)
        model_id = None
    error_body = {
        "code": code,
        "message": message,
        "request_id": getattr(request.state, "request_id", "unknown"),
    }
    if model_id is not None:
        error_body["model_id"] = model_id
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": error_body},
        headers=_version_header(),
    )
