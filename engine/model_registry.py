"""
Model registry - tracks loaded models and idle timeout.
When a model has no requests for idle_timeout_minutes, it should be unloaded.
Services call record_usage() on each request; a background task checks is_idle() and
triggers unload via registered callbacks.
"""
from __future__ import annotations

import asyncio
import logging
import os
import threading
import time
from typing import Callable

logger = logging.getLogger(__name__)

# Default 15 minutes, overridable via ENGINE_IDLE_TIMEOUT_MINUTES
def get_idle_timeout_minutes() -> int:
    try:
        v = int(os.environ.get("ENGINE_IDLE_TIMEOUT_MINUTES", "15") or "15")
        return max(1, min(1440, v))  # 1 min ~ 24h
    except ValueError:
        return 15


_lock = threading.Lock()
# model_type -> (model_id, last_used_ts). last_used_ts=0 means unloaded.
_state: dict[str, tuple[str, float]] = {}
_unload_callbacks: dict[str, Callable[[], None]] = {}  # model_type -> sync unload fn


def record_usage(model_type: str, model_id: str) -> None:
    """Record that a model was used (call at start of each request)."""
    with _lock:
        _state[model_type] = (model_id, time.monotonic())


def mark_unloaded(model_type: str) -> None:
    """Mark model as unloaded (call after unloading)."""
    with _lock:
        if model_type in _state:
            mid, _ = _state[model_type]
            _state[model_type] = (mid, 0.0)


def is_loaded(model_type: str, model_id: str | None = None) -> bool:
    """Return True if model is loaded. If model_id given, also check it matches."""
    with _lock:
        if model_type not in _state:
            return False
        mid, last_used = _state[model_type]
        if last_used <= 0:
            return False
        if model_id is not None and mid != model_id:
            return False
        return True


def get_loaded_model_id(model_type: str) -> str | None:
    """Return loaded model_id for type, or None if unloaded."""
    with _lock:
        if model_type not in _state:
            return None
        mid, last_used = _state[model_type]
        return mid if last_used > 0 else None


def get_loaded_models() -> list[str]:
    """Return list of 'type:id' for /models/loaded, /health."""
    with _lock:
        return [f"{t}:{mid}" for t, (mid, ts) in _state.items() if ts > 0]


def is_idle(model_type: str) -> bool:
    """Return True if model has exceeded idle timeout (should be unloaded)."""
    with _lock:
        if model_type not in _state:
            return True
        _, last_used = _state[model_type]
        if last_used <= 0:
            return True
        timeout_sec = get_idle_timeout_minutes() * 60
        return (time.monotonic() - last_used) >= timeout_sec


def register_unload_callback(model_type: str, callback: Callable[[], None]) -> None:
    """Register a sync callback to unload the model. Called by idle checker."""
    _unload_callbacks[model_type] = callback


def _run_idle_unloads() -> None:
    """Check all registered types and trigger unload if idle."""
    for model_type, callback in list(_unload_callbacks.items()):
        if is_idle(model_type):
            try:
                callback()
            except Exception as e:
                logger.warning("Idle unload failed for %s: %s", model_type, e)


async def idle_check_loop() -> None:
    """Background task: every minute, unload idle models."""
    while True:
        await asyncio.sleep(60)
        _run_idle_unloads()
