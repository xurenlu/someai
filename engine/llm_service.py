"""
LLM service - 优先使用已下载的本地模型 (transformers)，Ollama 仅作 fallback。
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import warnings
from pathlib import Path

import httpx

from .config import MODELS_DIR, MODELS_JSON

logger = logging.getLogger(__name__)

OLLAMA_BASE = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_MODELS: list[str] = (
    [m.strip() for m in os.environ.get("OLLAMA_MODEL", "").split(",") if m.strip()]
    if os.environ.get("OLLAMA_MODEL")
    else ["qwen2.5:0.5b", "llama3.2:3b", "phi3:mini", "tinyllama"]
)


def _get_first_installed_llm_path() -> Path | None:
    """Find first installed LLM model directory from config."""
    if not MODELS_JSON.exists():
        return None
    try:
        data = json.loads(MODELS_JSON.read_text(encoding="utf-8"))
        for m in data.get("models", []):
            if m.get("type") != "llm":
                continue
            local = MODELS_DIR / "llm" / m.get("id", "")
            if local.exists() and any(local.iterdir()):
                return local
    except Exception:
        pass
    return None


def _generate_transformers(prompt: str, temperature: float, max_tokens: int) -> str:
    """Generate using transformers (纯 Python 本地推理)."""
    from transformers import AutoModelForCausalLM, AutoTokenizer

    model_path = _get_first_installed_llm_path()
    if not model_path:
        raise RuntimeError(
            "未找到已安装的 LLM 模型。请先在 Model Manager 下载模型（如 qwen2.5-0.5b-instruct），"
            "或安装 Ollama 并拉取模型：ollama pull qwen2.5:0.5b"
        )

    tokenizer = AutoTokenizer.from_pretrained(str(model_path), trust_remote_code=True)
    # Qwen2 等模型 tie_word_embeddings=true 时，safetensors 只存 embed_tokens，lm_head 会共享
    # 抑制 "lm_head.weight not initialized" 警告（属预期行为，不影响推理）
    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message="Some weights of .* were not initialized",
            category=UserWarning,
            module="transformers",
        )
        # low_cpu_mem_usage=True 会使用 meta 设备初始化，在 CPU 上会导致 "Cannot copy out of meta tensor"
        # 纯 CPU 推理时需设为 False
        model = AutoModelForCausalLM.from_pretrained(
            str(model_path),
            trust_remote_code=True,
            device_map="cpu",
            low_cpu_mem_usage=False,
        )

    # Use chat template for instruct models (Qwen, etc.)
    messages = [{"role": "user", "content": prompt}]
    try:
        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
    except Exception:
        text = prompt  # Fallback for non-chat models

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


async def generate(prompt: str, temperature: float = 0.7, max_tokens: int = 512) -> str:
    """Generate text from prompt. 优先本地模型，无则 fallback Ollama."""
    # 1. 优先使用已下载的本地模型 (纯 Python，不依赖 Ollama)
    model_path = _get_first_installed_llm_path()
    if model_path is not None:
        def _run():
            return _generate_transformers(prompt, temperature, max_tokens)

        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, _run)

    # 2. 无本地模型时 fallback 到 Ollama
    result = await _try_ollama(prompt, temperature, max_tokens)
    if result is not None:
        return result

    raise RuntimeError(
        "未找到可用的 LLM。请先在 Model Manager 下载模型（如 qwen2.5-0.5b-instruct），"
        "或安装 Ollama 并拉取：ollama pull qwen2.5:0.5b"
    )
