"""
Memory watchdog - placeholder for M5.
Monitors process memory and can trigger model unload when threshold exceeded.
Supports setting process memory limit via RLIMIT_AS (Unix).
"""
from __future__ import annotations

import os
import resource

_high_water_mb = 0


def set_memory_limit(mb: int) -> bool:
    """Set process memory limit (RLIMIT_AS). Returns True if successful."""
    if mb <= 0:
        return False
    try:
        limit_bytes = mb * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (limit_bytes, limit_bytes))
        return True
    except (ValueError, OSError):
        return False


def get_current_memory_mb() -> float:
    """Return current process RSS in MB. macOS ru_maxrss is in bytes."""
    try:
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        return rss / (1024 * 1024)  # bytes to MB
    except Exception:
        return 0.0


def check_memory(threshold_mb: float = 12000) -> bool:
    """Return True if memory is below threshold."""
    return get_current_memory_mb() < threshold_mb
