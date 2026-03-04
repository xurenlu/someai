"""
OCR service - Image to text using TrOCR (Microsoft).
"""
from __future__ import annotations

from pathlib import Path

from .config import MODELS_DIR

_trocr_processor = None
_trocr_model = None


_MODEL_WEIGHT_NAMES = ("pytorch_model.bin", "model.safetensors", "tf_model.h5")


def _get_first_installed_ocr_path() -> Path | None:
    """Return local path of first installed OCR model from config. Must have model weights."""
    from .models_api import _load_models_config

    models = _load_models_config()
    for m in models:
        if m.get("type") != "ocr":
            continue
        local = MODELS_DIR / "ocr" / m.get("id", "")
        if not local.exists() or not any(local.iterdir()):
            continue
        # 必须有模型权重文件才算完整安装
        has_weights = any((local / name).exists() for name in _MODEL_WEIGHT_NAMES)
        if has_weights:
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
            "未找到完整的 OCR 模型。请在 Model Manager 下载 trocr-base-printed；"
            "若已下载仍报错，可能是下载不完整，请删除 models/ocr/trocr-base-printed 后重新下载。"
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
