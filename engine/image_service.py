"""
Image generation service - placeholder for M4, real model in M5.
"""
from __future__ import annotations

import zlib
import struct


def _make_png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    length = struct.pack(">I", len(data))
    crc = struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    return length + chunk_type + data + crc


async def generate(prompt: str, width: int = 512, height: int = 512) -> bytes:
    """Generate image from prompt. Placeholder until SD is loaded."""
    w, h = max(1, min(width, 512)), max(1, min(height, 512))
    raw = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    ihdr = _make_png_chunk(b"IHDR", raw)
    row = b"\x00" + (b"\x64\x64\x96" * w)  # placeholder gray-blue
    idat_data = zlib.compress(row * h, 9)
    idat = _make_png_chunk(b"IDAT", idat_data)
    iend = _make_png_chunk(b"IEND", b"")
    return b"\x89PNG\r\n\x1a\n" + ihdr + idat + iend
