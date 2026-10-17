"""Entry point for frigate-genai sidecar. Run via: python -m frigate_genai"""

import argparse
import asyncio
import os
import sys

# Must run before anything imports openai: the SDK defers pydantic schema
# builds by default, and concurrent first use from activity threads races
# ("'MockCoreSchema' object does not support item assignment").
os.environ.setdefault("DEFER_PYDANTIC_BUILD", "false")

from frigate_genai.worker import async_main  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description="Frigate GenAI Sidecar")
    parser.add_argument("--mode", default="triggers",
                        choices=["triggers", "ffmpeg", "genai-gemini", "genai-ollama", "mqtt-listener", "dashboard"])
    args = parser.parse_args()

    prompts_path = "/var/lib/frigate-genai-sidecar/prompts.json"
    provider_path = "/var/lib/frigate-genai-sidecar/provider.json"

    try:
        asyncio.run(async_main(prompts_path, provider_path, mode=args.mode))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
