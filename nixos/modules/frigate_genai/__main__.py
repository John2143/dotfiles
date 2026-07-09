"""Entry point for frigate-genai sidecar. Run via: python -m frigate_genai"""

import argparse
import asyncio
import sys

from frigate_genai.worker import async_main


def main():
    parser = argparse.ArgumentParser(description="Frigate GenAI Sidecar")
    parser.add_argument("--mode", default="triggers",
                        choices=["triggers", "ffmpeg", "genai-gemini", "genai-ollama"])
    args = parser.parse_args()

    prompts_path = "/var/lib/frigate-genai-sidecar/prompts.json"
    provider_path = "/var/lib/frigate-genai-sidecar/provider.json"

    try:
        asyncio.run(async_main(prompts_path, provider_path, mode=args.mode))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
