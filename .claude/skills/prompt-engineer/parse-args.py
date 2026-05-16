#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Deterministic argument parser for prompt-engineer skill.

Parses $ARGUMENTS into MODE, TEXT, PROMPT_PATH, and HAS_AT_PREFIX following the exact rules from
SKILL.md. Outputs shell-safe variable assignments for `eval`.

Usage:
  # Via environment variable (preferred):
  ARGUMENTS='...' ./parse-args.py

  # Via stdin:
  echo '...' | ./parse-args.py

  # Via argv:
  ./parse-args.py '...'
"""
import os
import shlex
import sys


def parse(raw: str) -> dict:
    # Step 1: Normalize — strip leading ./ trailing / and whitespace.
    normalized = raw
    if normalized.startswith("./"):
        normalized = normalized[2:]
    normalized = normalized.rstrip("/")
    normalized = normalized.strip()

    # Step 2: Check for @ prefix (harness auto-attached context files).
    has_at_prefix = False
    if normalized.startswith("@"):
        has_at_prefix = True
        normalized = normalized[1:]
        if normalized.startswith("./"):
            normalized = normalized[2:]
        normalized = normalized.rstrip("/")
        normalized = normalized.strip()

    # Step 3: Empty after normalization.
    if not normalized:
        return {
            "MODE": "ask",
            "TEXT": "",
            "PROMPT_PATH": "",
            "HAS_AT_PREFIX": "false",
        }

    # Step 4: Keyword detection — "loop" exactly.
    if normalized == "loop":
        return {
            "MODE": "loop",
            "TEXT": normalized,
            "PROMPT_PATH": "",
            "HAS_AT_PREFIX": "true" if has_at_prefix else "false",
        }

    # Step 5: Quoted string — starts and ends with matching ".
    if len(normalized) >= 2 and normalized[0] == '"' and normalized[-1] == '"':
        inner = normalized[1:-1]
        # Strip leading ./ and trailing / from inner text too (for paths in
        # quotes — the original spec treats quoted text as inline even if it
        # looks like a path, but we still normalize whitespace).
        inner = inner.strip()
        return {
            "MODE": "inline",
            "TEXT": inner,
            "PROMPT_PATH": "",
            "HAS_AT_PREFIX": "true" if has_at_prefix else "false",
        }

    # Step 6: File existence check.
    if os.path.isfile(normalized):
        return {
            "MODE": "file",
            "TEXT": "",
            "PROMPT_PATH": normalized,
            "HAS_AT_PREFIX": "true" if has_at_prefix else "false",
        }

    # Step 7: Fallback — raw text treated as inline prompt.
    return {
        "MODE": "inline",
        "TEXT": normalized,
        "PROMPT_PATH": "",
        "HAS_AT_PREFIX": "true" if has_at_prefix else "false",
    }


def main() -> None:
    if "ARGUMENTS" in os.environ:
        raw = os.environ["ARGUMENTS"]
    elif len(sys.argv) > 1:
        raw = sys.argv[1]
    else:
        raw = sys.stdin.read().strip()

    result = parse(raw)
    for key, value in result.items():
        print(f"{key}={shlex.quote(value)}")


if __name__ == "__main__":
    main()
