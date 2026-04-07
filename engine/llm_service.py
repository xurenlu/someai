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
    else ["qwen3.5:0.8b", "qwen2.5:0.5b", "llama3.2:3b", "phi3:mini", "tinyllama"]
)

MODEL_TYPE = "llm"

# Cached model: (model_obj, tokenizer_or_processor, model_id, backend)
# backend: "causal_lm" | "gemma4"
_llm_cache: tuple[object, object, str, str] | None = None


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


def _llm_backend_for_path(model_path: Path) -> str:
    """根据 config.json 判断加载方式：Gemma 4 多模态用 AutoModelForImageTextToText。"""
    cfg_path = model_path / "config.json"
    if not cfg_path.is_file():
        return "causal_lm"
    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return "causal_lm"
    arch = (cfg.get("architectures") or [None])[0]
    if arch == "Gemma4ForConditionalGeneration":
        return "gemma4"
    return "causal_lm"


def _pick_device_dtype():
    """M2/M3 优先 MPS + float16，其次 CUDA，否则 CPU float16 以节省内存。"""
    import torch

    if torch.backends.mps.is_available():
        return torch.device("mps"), torch.float16
    if torch.cuda.is_available():
        return torch.device("cuda"), torch.bfloat16
    return torch.device("cpu"), torch.float16


def _load_causal_lm_model(model_path: Path) -> tuple[object, object]:
    from transformers import AutoModelForCausalLM, AutoTokenizer

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


def _load_gemma4_model(model_path: Path) -> tuple[object, object]:
    from transformers import AutoModelForImageTextToText, AutoProcessor
    import torch

    device, dtype = _pick_device_dtype()
    processor = AutoProcessor.from_pretrained(str(model_path), trust_remote_code=True)
    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message="Some weights of .* were not initialized",
            category=UserWarning,
            module="transformers",
        )
        model = AutoModelForImageTextToText.from_pretrained(
            str(model_path),
            trust_remote_code=True,
            torch_dtype=dtype,
            low_cpu_mem_usage=True,
        )
    model = model.to(device)
    model.eval()
    return model, processor


def _load_transformers_model(model_id: str) -> tuple[object, object, str]:
    """Load model and tokenizer/processor. Returns (model, tokenizer_or_processor, backend)."""
    model_path = _get_llm_path(model_id)
    if not model_path:
        raise RuntimeError(
            f"未找到已安装的 LLM 模型 {model_id}。请先在 Model Manager 下载模型。"
        )

    backend = _llm_backend_for_path(model_path)
    if backend == "gemma4":
        model, processor = _load_gemma4_model(model_path)
        return model, processor, backend
    model, tokenizer = _load_causal_lm_model(model_path)
    return model, tokenizer, "causal_lm"


def _unload_llm() -> None:
    """Unload cached LLM to free memory."""
    global _llm_cache
    if _llm_cache is not None:
        _llm_cache = None
        gc.collect()
        mark_unloaded(MODEL_TYPE)
        logger.info("LLM model unloaded (idle timeout)")


def _ensure_loaded(model_id: str) -> tuple[object, object, str]:
    """Ensure model is loaded. Returns (model, tokenizer_or_processor, backend)."""
    global _llm_cache
    if _llm_cache is not None:
        _, _, cached_id, _ = _llm_cache
        if cached_id == model_id:
            return _llm_cache[0], _llm_cache[1], _llm_cache[3]
        _unload_llm()
    model, handler, backend = _load_transformers_model(model_id)
    _llm_cache = (model, handler, model_id, backend)
    record_usage(MODEL_TYPE, model_id)
    return model, handler, backend


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


def _generate_causal_lm(
    model: object,
    tokenizer: object,
    prompt: str,
    temperature: float,
    max_tokens: int,
) -> str:
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


def _generate_gemma4(
    model: object,
    processor: object,
    prompt: str,
    temperature: float,
    max_tokens: int,
    thinking: bool,
) -> str:
    import torch

    messages = [{"role": "user", "content": prompt}]
    try:
        text = processor.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=thinking,
        )
    except TypeError:
        text = processor.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )
    except Exception:
        text = prompt

    inputs = processor(text=text, return_tensors="pt")
    device = next(model.parameters()).device
    inputs = {k: v.to(device) if hasattr(v, "to") else v for k, v in inputs.items()}
    input_len = inputs["input_ids"].shape[-1]

    tok = getattr(processor, "tokenizer", None)
    pad_id = getattr(tok, "pad_token_id", None) if tok is not None else None
    if pad_id is None and tok is not None:
        pad_id = getattr(tok, "eos_token_id", None)

    gen_kwargs: dict = {
        "max_new_tokens": max_tokens,
        "do_sample": temperature > 0,
    }
    if temperature > 0:
        gen_kwargs["temperature"] = temperature
    if pad_id is not None:
        gen_kwargs["pad_token_id"] = pad_id

    with torch.inference_mode():
        outputs = model.generate(**inputs, **gen_kwargs)

    new_tokens = outputs[0][input_len:]
    if tok is None:
        raise RuntimeError("Gemma 4 processor 缺少 tokenizer，无法解码输出")
    out = tok.decode(new_tokens, skip_special_tokens=True)
    return out.strip()


def _generate_transformers(
    prompt: str, temperature: float, max_tokens: int, model_id: str, thinking: bool
) -> str:
    """Generate using cached transformers model."""
    model, handler, backend = _ensure_loaded(model_id)
    record_usage(MODEL_TYPE, model_id)

    if backend == "gemma4":
        return _generate_gemma4(model, handler, prompt, temperature, max_tokens, thinking)
    return _generate_causal_lm(model, handler, prompt, temperature, max_tokens)


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
    thinking: bool = False,
) -> str | dict:
    """Generate text from prompt. 优先本地模型，无则 fallback Ollama.

    Args:
        prompt: 输入提示
        temperature: 温度参数
        max_tokens: 最大生成 token 数
        model_id: 模型 ID
        thinking: 是否启用 thinking 模式（返回包含 thinking 的字典）

    Returns:
        如果 thinking=True，返回 {"text": str, "thinking": str | None}
        否则返回 str（向后兼容）
    """
    model_id = model_id or _get_first_installed_llm_id()
    if model_id is None:
        result = await _try_ollama(prompt, temperature, max_tokens)
        if result is not None:
            return _process_thinking(result, thinking)
        raise RuntimeError(
            "未找到可用的 LLM。请先在 Model Manager 下载模型（如 qwen2.5-0.5b-instruct），"
            "或安装 Ollama 并拉取：ollama pull qwen2.5:0.5b"
        )

    if not is_loaded(MODEL_TYPE, model_id):
        raise ModelNotLoadedError(model_id)

    def _run():
        return _generate_transformers(prompt, temperature, max_tokens, model_id, thinking)

    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(None, _run)
    if result:
        return _process_thinking(result, thinking)

    result = await _try_ollama(prompt, temperature, max_tokens)
    if result is not None:
        return _process_thinking(result, thinking)
    raise RuntimeError(
        "未找到可用的 LLM。请先在 Model Manager 下载模型，或安装 Ollama 并拉取模型。"
    )


def _process_thinking(text: str, enabled: bool) -> str | dict:
    """处理 thinking 内容。

    如果启用了 thinking，从输出中提取 <think>...</think> 标签内容。
    Qwen 模型的 thinking 输出格式：
    <think>思考内容...</think>最终回答
    """
    if not enabled:
        return text

    # 尝试提取 thinking 内容
    import re
    think_pattern = r'<think>(.*?)</think>'
    matches = re.findall(think_pattern, text, re.DOTALL)

    if matches:
        # 合并所有 thinking 块
        thinking_content = "\n\n".join(matches).strip()
        # 移除 thinking 标签，得到最终回答
        final_answer = re.sub(think_pattern, '', text, flags=re.DOTALL).strip()
        return {
            "text": final_answer,
            "thinking": thinking_content
        }

    # 没有找到 thinking 标签，返回原始文本
    return {"text": text, "thinking": None}


# Register idle unload callback
register_unload_callback(MODEL_TYPE, _unload_llm)
