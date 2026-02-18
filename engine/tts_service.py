"""
TTS service - 优先使用已下载的 Qwen3-TTS 本地模型，无则 fallback edge-tts（免费，无需 token）。
支持模型缓存、空闲超时卸载、预加载。
"""
from __future__ import annotations

import asyncio
import gc
import io
import json
from pathlib import Path

from .config import MODELS_DIR, MODELS_JSON
from .model_registry import (
    is_loaded,
    mark_unloaded,
    record_usage,
    register_unload_callback,
)

# Qwen3-TTS CustomVoice 支持的 speaker
QWEN_SPEAKERS = ["Vivian", "Serena", "Uncle_Fu", "Dylan", "Eric", "Ryan", "Aiden", "Ono_Anna", "Sohee"]
LANG_MAP = {"zh": "Chinese", "en": "English"}

MODEL_TYPE = "tts"
DEFAULT_TTS_MODEL_ID = "qwen3-tts-12hz-0.6b"

_tts_model = None
_tts_model_id: str | None = None


class ModelNotLoadedError(RuntimeError):
    """Raised when model is unloaded and needs to be loaded first."""

    def __init__(self, model_id: str):
        self.model_id = model_id
        super().__init__(f"模型 {model_id} 需要先加载，请调用 POST /models/{model_id}/load 预加载")


def _get_first_installed_tts_id() -> str | None:
    """Find first installed TTS model id."""
    if not MODELS_JSON.exists():
        return None
    try:
        data = json.loads(MODELS_JSON.read_text(encoding="utf-8"))
        for m in data.get("models", []):
            if m.get("type") != "tts":
                continue
            model_id = m.get("id", "")
            local = MODELS_DIR / "tts" / model_id
            if local.exists() and any(local.iterdir()):
                return model_id
    except Exception:
        pass
    return None


def _get_tts_path(model_id: str) -> Path | None:
    """Return local path for TTS model if installed."""
    local = MODELS_DIR / "tts" / model_id
    return local if local.exists() and any(local.iterdir()) else None


def _load_qwen_tts(model_id: str) -> object:
    """Load Qwen3-TTS model."""
    try:
        from qwen_tts import Qwen3TTSModel
    except ImportError as e:
        raise RuntimeError(
            "未安装 qwen-tts，无法使用本地 Qwen3-TTS 模型。"
            "请运行: uv sync --extra qwen-tts（若遇依赖冲突，建议使用 Python 3.10 或 3.11）"
        ) from e

    model_path = _get_tts_path(model_id)
    if not model_path:
        raise RuntimeError(f"未找到已安装的 TTS 模型 {model_id}，请先在 Model Manager 下载")

    return Qwen3TTSModel.from_pretrained(
        str(model_path),
        device_map="cpu",
        torch_dtype="float32",
    )


def _unload_tts() -> None:
    """Unload cached TTS model to free memory."""
    global _tts_model, _tts_model_id
    if _tts_model is not None:
        _tts_model = None
        _tts_model_id = None
        gc.collect()
        mark_unloaded(MODEL_TYPE)


def _ensure_loaded(model_id: str) -> object:
    """Ensure TTS model is loaded. Load if needed."""
    global _tts_model, _tts_model_id
    if _tts_model is not None and _tts_model_id == model_id:
        record_usage(MODEL_TYPE, model_id)
        return _tts_model
    if _tts_model is not None:
        _unload_tts()
    _tts_model = _load_qwen_tts(model_id)
    _tts_model_id = model_id
    record_usage(MODEL_TYPE, model_id)
    return _tts_model


def load_model(model_id: str) -> bool:
    """Preload TTS model. Returns True if loaded successfully."""
    if not _get_tts_path(model_id):
        return False
    try:
        _ensure_loaded(model_id)
        return True
    except Exception:
        return False


def _generate_qwen_tts(text: str, language: str, speaker: str, model_id: str) -> tuple[bytes, str]:
    """Generate using Qwen3-TTS (本地模型). Returns (wav_bytes, 'audio/wav')."""
    import soundfile as sf

    model = _ensure_loaded(model_id)
    lang = LANG_MAP.get(language, "Chinese")
    spk = speaker if speaker in QWEN_SPEAKERS else "Vivian"

    wavs, sr = model.generate_custom_voice(
        text=text,
        language=lang,
        speaker=spk,
    )

    buf = io.BytesIO()
    sf.write(buf, wavs[0], sr, format="WAV")
    return buf.getvalue(), "audio/wav"


async def _generate_edge_tts(text: str, language: str, speaker: str) -> tuple[bytes, str]:
    """Fallback: edge-tts（微软 Edge 内置 TTS，完全免费，无需 token/账号）."""
    import edge_tts

    voice_map = {
        ("zh", "default"): "zh-CN-XiaoxiaoNeural",
        ("zh", "female"): "zh-CN-XiaoxiaoNeural",
        ("zh", "male"): "zh-CN-YunxiNeural",
        ("en", "default"): "en-US-JennyNeural",
        ("en", "female"): "en-US-JennyNeural",
        ("en", "male"): "en-US-GuyNeural",
    }
    voice = voice_map.get((language, speaker)) or voice_map.get((language, "default")) or "zh-CN-XiaoxiaoNeural"

    communicate = edge_tts.Communicate(text, voice)
    chunks = []
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            chunks.append(chunk["data"])
    return b"".join(chunks), "audio/mpeg"


async def generate(text: str, language: str = "zh", speaker: str = "default", model_id: str | None = None) -> tuple[bytes, str]:
    """Generate audio. 优先本地 Qwen3-TTS，无则 edge-tts. Returns (bytes, media_type)."""
    text = (text or "").strip() or "。"
    model_id = model_id or _get_first_installed_tts_id()

    if model_id is not None:
        if not is_loaded(MODEL_TYPE, model_id):
            raise ModelNotLoadedError(model_id)

        def _run():
            return _generate_qwen_tts(text, language, speaker, model_id)

        try:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(None, _run)
        except (RuntimeError, ImportError) as e:
            print(f"[TTS] Qwen3-TTS 不可用: {e}，使用 edge-tts")

    return await _generate_edge_tts(text, language, speaker)


# Register idle unload callback
register_unload_callback(MODEL_TYPE, _unload_tts)
