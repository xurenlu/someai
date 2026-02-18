"""OCR API - POST /ocr/recognize"""
from __future__ import annotations

from fastapi import APIRouter, File, Query, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse

from .config import APP_VERSION
from .ocr_service import recognize

router = APIRouter()


def _version_header():
    return {"X-App-Version": APP_VERSION}


@router.post("/ocr/recognize")
async def ocr_recognize_endpoint(
    file: UploadFile = File(...),
    format: str = Query("text", description="Output format: text or json"),
):
    """
    Run OCR on uploaded image. Returns text or JSON.
    format: "text" (default) or "json"
    """
    image_data = await file.read()
    if not image_data:
        return JSONResponse(
            status_code=400,
            content={"error": {"code": "EMPTY_FILE", "message": "Empty file"}},
            headers=_version_header(),
        )

    try:
        result = await recognize(image_data, output_format=format)
    except RuntimeError as e:
        return JSONResponse(
            status_code=503,
            content={"error": {"code": "OCR_UNAVAILABLE", "message": str(e)}},
            headers=_version_header(),
        )

    if format == "json":
        return JSONResponse(content=result, headers=_version_header())
    return PlainTextResponse(content=result, headers=_version_header())
