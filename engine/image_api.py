"""Image API - POST /image/generate"""
from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import Response
from pydantic import BaseModel

from .config import APP_VERSION
from .image_service import generate as image_generate

router = APIRouter()


class ImageGenerateRequest(BaseModel):
    prompt: str
    width: int = 512
    height: int = 512


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/image/generate")
async def image_generate_endpoint(req: ImageGenerateRequest):
    png_data = await image_generate(req.prompt, req.width, req.height)
    return Response(
        content=png_data,
        media_type="image/png",
        headers={**_version_header(), "Content-Disposition": "inline"},
    )
