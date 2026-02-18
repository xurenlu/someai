"""LLM API - POST /llm/generate"""
from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .config import APP_VERSION
from .llm_service import generate as llm_generate

router = APIRouter()


class LLMGenerateRequest(BaseModel):
    prompt: str
    temperature: float = 0.7
    max_tokens: int = 512


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/llm/generate", response_class=JSONResponse)
async def llm_generate_endpoint(req: LLMGenerateRequest):
    text = await llm_generate(req.prompt, req.temperature, req.max_tokens)
    return JSONResponse(content={"text": text}, headers=_version_header())
