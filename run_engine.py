#!/usr/bin/env python3
"""
Run MacAIStudio engine server.
Usage: uv run python run_engine.py   (or: uv run uvicorn engine.server:app --host 127.0.0.1 --port 8001 --reload)
"""
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "engine.server:app",
        host="127.0.0.1",
        port=8001,
        reload=True,
    )
