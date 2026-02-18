"""
MacAIStudio Local AI Engine - FastAPI Server
Base URL: http://127.0.0.1:18080
"""
from __future__ import annotations

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
from .stt_api import router as stt_router
from .tts_api import router as tts_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    runtime.engine_start_time = time.monotonic()
    yield
    # cleanup if needed


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
    return JSONResponse(
        content={
            "status": "ok",
            "models_loaded": [],  # Will be populated when models are loaded
        },
        headers=_version_header(),
    )


app.include_router(download_router, prefix="", tags=["download"])
app.include_router(image_router, prefix="", tags=["image"])
app.include_router(llm_router, prefix="", tags=["llm"])
app.include_router(models_router, prefix="", tags=["models"])
app.include_router(stt_router, prefix="", tags=["stt"])
app.include_router(tts_router, prefix="", tags=["tts"])


@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc: HTTPException):
    detail = exc.detail
    if isinstance(detail, dict):
        code = detail.get("code", "UNKNOWN")
        message = detail.get("message", str(detail))
    else:
        code = "UNKNOWN"
        message = str(detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": code,
                "message": message,
                "request_id": getattr(request.state, "request_id", "unknown"),
            }
        },
        headers=_version_header(),
    )
