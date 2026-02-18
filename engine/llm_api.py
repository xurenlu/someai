"""LLM API - POST /llm/generate"""
from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .config import APP_VERSION
from .llm_service import generate as llm_generate

router = APIRouter()
logger = logging.getLogger(__name__)


class LLMGenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.7
    max_tokens: int = 512


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/llm/generate", response_class=JSONResponse)
async def llm_generate_endpoint(req: LLMGenerateRequest):
    try:
        text = await llm_generate(req.prompt, req.temperature, req.max_tokens)
        return JSONResponse(content={"text": text}, headers=_version_header())
    except RuntimeError as e:
        logger.exception("LLM generate failed")
        raise HTTPException(
            status_code=503,
            detail={"code": "LLM_ERROR", "message": str(e)},
        )
    except Exception as e:
        logger.exception("LLM generate unexpected error")
        raise HTTPException(
            status_code=500,
            detail={"code": "LLM_INTERNAL_ERROR", "message": str(e)},
        )
