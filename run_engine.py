#!/usr/bin/env python3
"""
Run MacAIStudio engine server.
Usage: uv run python run_engine.py
       ENGINE_PORT=18080 uv run python run_engine.py   # custom port
"""
import os

import uvicorn

if __name__ == "__main__":
    port = int(os.environ.get("ENGINE_PORT", "18080"))
    uvicorn.run(
        "engine.server:app",
        host="127.0.0.1",
        port=port,
        reload=True,
    )
