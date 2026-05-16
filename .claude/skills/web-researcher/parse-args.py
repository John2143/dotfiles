#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Deterministic argument parser for web-researcher skill.

Parses $ARGUMENTS into RESEARCH_QUESTION, CONTEXT, and TOPIC_SLUG following
the exact rules from SKILL.md. Outputs shell-safe variable assignments
for `eval`.

Usage:
  # Via environment variable (preferred — bypasses all shell quoting issues):
  ARGUMENTS='...' python3 parse-args.py

  # Via stdin:
  echo '...' | python3 parse-args.py

  # Via argv:
  python3 parse-args.py '...'
"""
import os
import re
import shlex
import sys


def slugify(s: str) -> str:
    """Lowercase, replace non-alnum with hyphens, collapse, trim, truncate to 64."""
    s = s.lower()
    s = re.sub(r'[^a-z0-9]', '-', s)
    s = re.sub(r'-+', '-', s)
    s = s.strip('-')
    return s[:64] if s else "EMPTY_SLUG"


def parse(raw: str) -> dict:
    stripped = raw

    # Step 1: Strip outer quotes — only when the string BOTH starts AND ends
    # with the same quote character.
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ('"', "'"):
        stripped = raw[1:-1]

    # Step 2: Extract RESEARCH_QUESTION from the first pair of double-quotes
    # inside the stripped string.
    first_dq = stripped.find('"')
    if first_dq != -1:
        second_dq = stripped.find('"', first_dq + 1)
        if second_dq != -1:
            research_question = stripped[first_dq + 1 : second_dq]
            context = stripped[second_dq + 1 :].strip()
        else:
            # Unclosed quote — take everything after it as the question.
            research_question = stripped[first_dq + 1 :]
            context = ""
    else:
        # Step 2 alt: No double-quotes found — entire stripped string is
        # the research question.
        research_question = stripped
        context = ""

    # Step 3: Emptiness check.
    empty = not research_question.strip()

    # Step 4: Derive TOPIC_SLUG.
    topic_slug = slugify(research_question) if not empty else "EMPTY_SLUG"

    return {
        "RESEARCH_QUESTION": research_question,
        "CONTEXT": context,
        "TOPIC_SLUG": topic_slug,
        "EMPTY": "true" if empty else "false",
    }


def main() -> None:
    # Read from ARGUMENTS env var, else argv[1], else stdin.
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
