"""
Simple task queue for serializing heavy model operations.
"""
from __future__ import annotations

import asyncio
from collections.abc import Coroutine
from typing import Any

_queue: asyncio.Queue[tuple[Coroutine[Any, Any, Any], asyncio.Future[Any]]] = asyncio.Queue()
_worker_started = False


async def _worker():
    while True:
        coro, future = await _queue.get()
        try:
            result = await coro
            future.set_result(result)
        except Exception as e:
            future.set_exception(e)
        finally:
            _queue.task_done()


def ensure_worker_started():
    global _worker_started
    if not _worker_started:
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(_worker())
            _worker_started = True
        except RuntimeError:
            pass


async def enqueue(coro: Coroutine[Any, Any, Any]) -> Any:
    ensure_worker_started()
    future: asyncio.Future[Any] = asyncio.get_running_loop().create_future()
    await _queue.put((coro, future))
    return await future


def queue_size() -> int:
    return _queue.qsize()
