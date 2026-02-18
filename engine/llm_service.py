"""
LLM service - placeholder for M2, real model loading in M5.
"""
from __future__ import annotations


async def generate(prompt: str, temperature: float = 0.7, max_tokens: int = 512) -> str:
    """Generate text from prompt. Placeholder until model is loaded."""
    # Stub: return placeholder when no model loaded
    return f"[LLM placeholder] Response to: {prompt[:50]}..."
