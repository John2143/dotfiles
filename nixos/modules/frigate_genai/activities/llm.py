"""Local LLM plumbing shared by every activity that calls the model.

_run_with_heartbeat: heartbeat wrapper for sync LLM calls
_resolve_provider: OpenAI-compatible client factory for ollama/ models
warm_openai_client: build the SDK's lazy schemas on the main thread
"""

import asyncio
import logging
import os
import random

from temporalio import activity

log = logging.getLogger("frigate-genai-sidecar")


async def _run_with_heartbeat(func, *args, interval: float = 2.0):
    """Run a sync function in a thread, heartbeating every `interval` seconds.

    Prevents Temporal from cancelling the activity while the thread is busy
    (e.g. waiting for a slow LLM). On cancellation the inner task is also
    cancelled to avoid orphaning the thread.
    """
    task = asyncio.create_task(asyncio.to_thread(func, *args))
    try:
        while not task.done():
            try:
                jittered = interval * (0.8 + 0.4 * random.random())
                await asyncio.wait_for(asyncio.shield(task), timeout=jittered)
            except TimeoutError:
                activity.heartbeat()
        return task.result()
    except asyncio.CancelledError:
        task.cancel()
        raise


def _resolve_provider(provider_cfg: dict, model: str, timeout: float = 120.0):
    """Return (OpenAI-compatible client, model_name) for an ollama/ model.

    Only `ollama/<name>` is accepted: inference goes straight to the host and
    the API key is a placeholder the server ignores.
    """
    from openai import OpenAI

    if not model.startswith("ollama/"):
        raise RuntimeError(f"Unsupported model {model!r}: only ollama/ models are configured")
    base_url = provider_cfg.get("ollama_base_url", "http://office.ts.2143.me:11434/v1")
    api_key = os.environ.get("OLLAMA_API_KEY", "ollama")
    model_name = model[len("ollama/"):]
    client = OpenAI(api_key=api_key, base_url=base_url, timeout=timeout)
    return client, model_name


def warm_openai_client() -> bool:
    """Import the OpenAI SDK's lazy chat resources and build their pydantic
    schemas on the calling (main) thread, before any activity thread can race
    on first use. Requires DEFER_PYDANTIC_BUILD=false (set in __main__) before
    openai is first imported. Returns ChatCompletion.__pydantic_complete__."""
    from openai import OpenAI
    from openai.types.chat import ChatCompletion

    client = OpenAI(api_key="warmup", base_url="http://127.0.0.1:9/v1")
    client.chat.completions  # first access imports openai.resources.chat
    client.close()
    return ChatCompletion.__pydantic_complete__
