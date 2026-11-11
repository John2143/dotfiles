#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Deterministic argument parser for web-researcher skill.

Parses $ARGUMENTS into a list of research questions, their topic slugs, the
shared context, and an emptiness flag. Outputs shell-safe assignments for
`eval`, so the caller never reasons about quote positions.

Rule: every double-quoted span is one research question. Text outside the
spans is shared context, appended to every question's brief. With no quoted
span, the whole argument string is a single question. Slugs are deduplicated
within one invocation so two questions can never share a research directory.

Usage:
  # Via environment variable (preferred — bypasses all shell quoting issues):
  ARGUMENTS='...' python3 parse-args.py

  # Via stdin:
  echo '...' | python3 parse-args.py

  # Via argv:
  python3 parse-args.py '...'

Emits:
  QUESTIONS=('first question' 'second question')
  SLUGS=('first-question' 'second-question')
  COUNT=2
  CONTEXT='shared context or empty'
  EMPTY=false
"""
import os
import re
import shlex
import sys

QUESTION_RE = re.compile(r'"([^"]*)"')
SLUG_MAX = 64


def slugify(s: str) -> str:
    """Lowercase, replace non-alnum with hyphens, collapse, trim, truncate."""
    s = s.lower()
    s = re.sub(r"[^a-z0-9]", "-", s)
    s = re.sub(r"-+", "-", s)
    s = s.strip("-")
    return s[:SLUG_MAX] if s else "untitled"


def dedupe(slugs: list[str]) -> list[str]:
    """Suffix repeats (-2, -3, …) so sibling runs never share a directory."""
    seen: dict[str, int] = {}
    out: list[str] = []
    for slug in slugs:
        n = seen.get(slug, 0) + 1
        seen[slug] = n
        if n == 1:
            out.append(slug)
            continue
        suffix = f"-{n}"
        out.append(slug[: SLUG_MAX - len(suffix)].rstrip("-") + suffix)
    return out


def parse(raw: str) -> dict:
    stripped = raw.strip()

    # Strip one matching outer quote pair, but only when it wraps the whole
    # argument rather than delimiting the first of several questions.
    if (
        len(stripped) >= 2
        and stripped[0] == stripped[-1]
        and stripped[0] in ('"', "'")
        and '"' not in stripped[1:-1]
    ):
        stripped = stripped[1:-1]

    matches = list(QUESTION_RE.finditer(stripped))
    if matches:
        questions = [m.group(1).strip() for m in matches]
        remainder = QUESTION_RE.sub(" ", stripped)
    else:
        questions = [stripped]
        remainder = ""

    questions = [q for q in questions if q]
    context = re.sub(r"[\s,;]+", " ", remainder).strip(" ,;")

    slugs = dedupe([slugify(q) for q in questions])
    return {
        "QUESTIONS": questions,
        "SLUGS": slugs,
        "CONTEXT": context,
        "EMPTY": "true" if not questions else "false",
    }


def shell_array(name: str, values: list[str]) -> str:
    return f"{name}=({' '.join(shlex.quote(v) for v in values)})"


def main() -> None:
    # Read from ARGUMENTS env var, else argv[1], else stdin.
    if "ARGUMENTS" in os.environ:
        raw = os.environ["ARGUMENTS"]
    elif len(sys.argv) > 1:
        raw = sys.argv[1]
    else:
        raw = sys.stdin.read().strip()

    result = parse(raw)
    print(shell_array("QUESTIONS", result["QUESTIONS"]))
    print(shell_array("SLUGS", result["SLUGS"]))
    print(f"COUNT={len(result['QUESTIONS'])}")
    print(f"CONTEXT={shlex.quote(result['CONTEXT'])}")
    print(f"EMPTY={result['EMPTY']}")


if __name__ == "__main__":
    main()
