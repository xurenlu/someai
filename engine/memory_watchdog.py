"""
Memory watchdog - placeholder for M5.
Monitors process memory and can trigger model unload when threshold exceeded.
"""
from __future__ import annotations

import os
import resource

_high_water_mb = 0


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
