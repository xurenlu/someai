"""
LLM service - 优先使用已下载的本地模型 (transformers)，Ollama 仅作 fallback。
支持模型缓存、空闲超时卸载、预加载。
"""
from __future__ import annotations

import asyncio
import gc
import json
import logging
import warnings
from pathlib import Path

import httpx

from .config import MODELS_DIR, MODELS_JSON
from .model_registry import (
    get_loaded_model_id,
    is_loaded,
    mark_unloaded,
    record_usage,
    register_unload_callback,
)

logger = logging.getLogger(__name__)

OLLAMA_BASE = __import__("os").environ.get("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_MODELS: list[str] = (
    [m.strip() for m in __import__("os").environ.get("OLLAMA_MODEL", "").split(",") if m.strip()]
    if __import__("os").environ.get("OLLAMA_MODEL")
    else ["qwen2.5:0.5b", "llama3.2:3b", "phi3:mini", "tinyllama"]
)

MODEL_TYPE = "llm"

# Cached model: (model_obj, tokenizer, model_id)
_llm_cache: tuple[object, object, str] | None = None


class ModelNotLoadedError(RuntimeError):
    """Raised when model is unloaded and needs to be loaded first."""

    def __init__(self, model_id: str):
        self.model_id = model_id
        super().__init__(f"模型 {model_id} 需要先加载，请调用 POST /models/{model_id}/load 预加载")


def _get_llm_path(model_id: str) -> Path | None:
    """Return local path for LLM model_id if installed."""
    if not MODELS_JSON.exists():
        return None
    try:
        data = json.loads(MODELS_JSON.read_text(encoding="utf-8"))
        for m in data.get("models", []):
            if m.get("type") != "llm" or m.get("id") != model_id:
                continue
            local = MODELS_DIR / "llm" / model_id
            if local.exists() and any(local.iterdir()):
                return local
    except Exception:
        pass
    return None


def _get_first_installed_llm_id() -> str | None:
    """Find first installed LLM model id from config."""
    if not MODELS_JSON.exists():
        return None
    try:
        data = json.loads(MODELS_JSON.read_text(encoding="utf-8"))
        for m in data.get("models", []):
            if m.get("type") != "llm":
                continue
            model_id = m.get("id", "")
            local = MODELS_DIR / "llm" / model_id
            if local.exists() and any(local.iterdir()):
                return model_id
    except Exception:
        pass
    return None


def _load_transformers_model(model_id: str) -> tuple[object, object]:
    """Load model and tokenizer. Returns (model, tokenizer)."""
    from transformers import AutoModelForCausalLM, AutoTokenizer

    model_path = _get_llm_path(model_id)
    if not model_path:
        raise RuntimeError(
            f"未找到已安装的 LLM 模型 {model_id}。请先在 Model Manager 下载模型。"
        )

    tokenizer = AutoTokenizer.from_pretrained(str(model_path), trust_remote_code=True)
    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message="Some weights of .* were not initialized",
            category=UserWarning,
            module="transformers",
        )
        model = AutoModelForCausalLM.from_pretrained(
            str(model_path),
            trust_remote_code=True,
            device_map="cpu",
            low_cpu_mem_usage=False,
        )
    return model, tokenizer


def _unload_llm() -> None:
    """Unload cached LLM to free memory."""
    global _llm_cache
    if _llm_cache is not None:
        _llm_cache = None
        gc.collect()
        mark_unloaded(MODEL_TYPE)
        logger.info("LLM model unloaded (idle timeout)")


def _ensure_loaded(model_id: str) -> tuple[object, object]:
    """Ensure model is loaded. Load if needed. Returns (model, tokenizer)."""
    global _llm_cache
    if _llm_cache is not None:
        _, _, cached_id = _llm_cache
        if cached_id == model_id:
            return _llm_cache[0], _llm_cache[1]
        _unload_llm()
    model, tokenizer = _load_transformers_model(model_id)
    _llm_cache = (model, tokenizer, model_id)
    record_usage(MODEL_TYPE, model_id)
    return model, tokenizer


def load_model(model_id: str) -> bool:
    """Preload LLM model. Returns True if loaded successfully."""
    model_path = _get_llm_path(model_id)
    if not model_path:
        return False
    try:
        _ensure_loaded(model_id)
        return True
    except Exception as e:
        logger.warning("Preload LLM %s failed: %s", model_id, e)
        return False


def _generate_transformers(prompt: str, temperature: float, max_tokens: int, model_id: str) -> str:
    """Generate using cached transformers model."""
    model, tokenizer = _ensure_loaded(model_id)
    record_usage(MODEL_TYPE, model_id)

    messages = [{"role": "user", "content": prompt}]
    try:
        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
    except Exception:
        text = prompt

    inputs = tokenizer(text, return_tensors="pt")
    outputs = model.generate(
        **inputs,
        max_new_tokens=max_tokens,
        temperature=temperature,
        do_sample=temperature > 0,
        pad_token_id=tokenizer.eos_token_id,
    )
    out = tokenizer.decode(outputs[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True)
    return out.strip()


async def _try_ollama(prompt: str, temperature: float, max_tokens: int) -> str | None:
    """Try Ollama API. Return None if unavailable."""
    for model in OLLAMA_MODELS:
        model = model.strip()
        if not model:
            continue
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                r = await client.post(
                    f"{OLLAMA_BASE}/api/generate",
                    json={
                        "model": model,
                        "prompt": prompt,
                        "stream": False,
                        "options": {"temperature": temperature, "num_predict": max_tokens},
                    },
                )
                if r.status_code != 200:
                    continue
                data = r.json()
                out = data.get("response", "").strip()
                if out:
                    return out
        except Exception:
            continue
    return None


async def generate(
    prompt: str,
    temperature: float = 0.7,
    max_tokens: int = 512,
    model_id: str | None = None,
) -> str:
    """Generate text from prompt. 优先本地模型，无则 fallback Ollama."""
    model_id = model_id or _get_first_installed_llm_id()
    if model_id is None:
        result = await _try_ollama(prompt, temperature, max_tokens)
        if result is not None:
            return result
        raise RuntimeError(
            "未找到可用的 LLM。请先在 Model Manager 下载模型（如 qwen2.5-0.5b-instruct），"
            "或安装 Ollama 并拉取：ollama pull qwen2.5:0.5b"
        )

    if not is_loaded(MODEL_TYPE, model_id):
        raise ModelNotLoadedError(model_id)

    def _run():
        return _generate_transformers(prompt, temperature, max_tokens, model_id)

    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(None, _run)
    if result:
        return result

    result = await _try_ollama(prompt, temperature, max_tokens)
    if result is not None:
        return result
    raise RuntimeError(
        "未找到可用的 LLM。请先在 Model Manager 下载模型，或安装 Ollama 并拉取模型。"
    )


# Register idle unload callback
register_unload_callback(MODEL_TYPE, _unload_llm)
