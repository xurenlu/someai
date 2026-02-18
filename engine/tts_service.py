"""
TTS service - 优先使用已下载的 Qwen3-TTS 本地模型，无则 fallback edge-tts（免费，无需 token）。
"""
from __future__ import annotations

import asyncio
import io
import json
from pathlib import Path

from .config import MODELS_DIR, MODELS_JSON

# Qwen3-TTS CustomVoice 支持的 speaker
QWEN_SPEAKERS = ["Vivian", "Serena", "Uncle_Fu", "Dylan", "Eric", "Ryan", "Aiden", "Ono_Anna", "Sohee"]
LANG_MAP = {"zh": "Chinese", "en": "English"}

_tts_model = None


def _get_first_installed_tts_path() -> Path | None:
    """Find first installed TTS model directory."""
    if not MODELS_JSON.exists():
        return None
    try:
        data = json.loads(MODELS_JSON.read_text(encoding="utf-8"))
        for m in data.get("models", []):
            if m.get("type") != "tts":
                continue
            local = MODELS_DIR / "tts" / m.get("id", "")
            if local.exists() and any(local.iterdir()):
                return local
    except Exception:
        pass
    return None


def _generate_qwen_tts(text: str, language: str, speaker: str) -> tuple[bytes, str]:
    """Generate using Qwen3-TTS (本地模型). Returns (wav_bytes, 'audio/wav')."""
    try:
        import soundfile as sf
        from qwen_tts import Qwen3TTSModel
    except ImportError as e:
        raise RuntimeError(
            "未安装 qwen-tts，无法使用本地 Qwen3-TTS 模型。"
            "请运行: uv sync --extra qwen-tts（若遇依赖冲突，建议使用 Python 3.10 或 3.11）"
        ) from e

    global _tts_model
    model_path = _get_first_installed_tts_path()
    if not model_path:
        raise RuntimeError("未找到已安装的 TTS 模型，请先在 Model Manager 下载 qwen3-tts-12hz-0.6b")

    if _tts_model is None:
        _tts_model = Qwen3TTSModel.from_pretrained(
            str(model_path),
            device_map="cpu",
            torch_dtype="float32",
        )

    lang = LANG_MAP.get(language, "Chinese")
    spk = speaker if speaker in QWEN_SPEAKERS else "Vivian"

    wavs, sr = _tts_model.generate_custom_voice(
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


async def generate(text: str, language: str = "zh", speaker: str = "default") -> tuple[bytes, str]:
    """Generate audio. 优先本地 Qwen3-TTS，无则 edge-tts. Returns (bytes, media_type)."""
    text = (text or "").strip() or "。"

    # 1. 优先本地模型（需已安装 qwen-tts）
    tts_path = _get_first_installed_tts_path()
    if tts_path is not None:
        def _run():
            return _generate_qwen_tts(text, language, speaker)

        try:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(None, _run)
        except (RuntimeError, ImportError) as e:
            # qwen-tts 未安装或导入失败，fallback edge-tts
            print(f"[TTS] Qwen3-TTS 不可用: {e}，使用 edge-tts")

    # 2. Fallback edge-tts（免费，无需 token）
    return await _generate_edge_tts(text, language, speaker)
