"""
OCR service - Image to text using TrOCR (Microsoft).
"""
from __future__ import annotations

from pathlib import Path

from .config import MODELS_DIR

_trocr_processor = None
_trocr_model = None


def _get_first_installed_ocr_path() -> Path | None:
    """Return local path of first installed OCR model from config."""
    from .models_api import _load_models_config

    models = _load_models_config()
    for m in models:
        if m.get("type") != "ocr":
            continue
        local = MODELS_DIR / "ocr" / m.get("id", "")
        if local.exists() and any(local.iterdir()):
            return local
    return None


def _get_trocr_model():
    """Lazy-load TrOCR processor and model. Uses local path if downloaded."""
    global _trocr_processor, _trocr_model
    if _trocr_model is not None:
        return _trocr_processor, _trocr_model

    from transformers import TrOCRProcessor, VisionEncoderDecoderModel

    model_path = _get_first_installed_ocr_path()
    if model_path is None:
        raise RuntimeError(
            "未找到已安装的 OCR 模型。请先在 Model Manager 下载 trocr-base-printed"
        )

    _trocr_processor = TrOCRProcessor.from_pretrained(str(model_path))
    _trocr_model = VisionEncoderDecoderModel.from_pretrained(
        str(model_path), device_map="cpu"
    )
    return _trocr_processor, _trocr_model


async def recognize(image_bytes: bytes, output_format: str = "text") -> str | dict:
    """
    Run OCR on image. Returns text or structured JSON.
    output_format: "text" | "json" (json wraps {"text": "..."})
    """
    import asyncio
    from io import BytesIO

    from PIL import Image

    def _run():
        processor, model = _get_trocr_model()
        img = Image.open(BytesIO(image_bytes)).convert("RGB")
        pixel_values = processor(img, return_tensors="pt").pixel_values
        generated_ids = model.generate(pixel_values)
        text = processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
        return text.strip() or "(无识别结果)"

    loop = asyncio.get_running_loop()
    text = await loop.run_in_executor(None, _run)

    if output_format == "json":
        return {"text": text}
    return text
