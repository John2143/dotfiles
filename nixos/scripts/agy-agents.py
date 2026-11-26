#!/usr/bin/env python3
"""Translate OMP task agents (.omp/agent/agents/*.md) into Antigravity agents.

The prompt body is kept. The frontmatter is rewritten:

* `name` and `description` carry over.
* `subagent: true`, `mainAgent: false` — they stay task agents, as in OMP.
* `tools` maps OMP tool names to agy's. agy gives an agent with no `tools`
  only a small read-only set, so an OMP agent without `tools` (meaning all of
  them) gets the full list. An unmapped OMP tool fails the build.
* `spawns` naming another agent in this set becomes `agents: [<name>.md]` plus
  the `invoke_subagent` tool. agy has no `scout`; agents that spawn it get a
  note to do that reading themselves.
* `model`, `thinking-level` and other OMP-only keys are dropped: agy runs
  Gemini models, so the agent inherits the session's model.

Usage: agy-agents.py <out-dir> <agent.md> [<agent.md> ...]
"""

import json
import sys
from pathlib import Path

import yaml

TOOLS = {
    "read": ["read_file"],
    "write": ["write_file"],
    "edit": ["edit_file"],
    "bash": ["run_command", "manage_task"],
    "web_search": ["search_web"],
    "task": ["invoke_subagent"],
}
ALL_TOOLS = ["read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"]

SCOUT_NOTE = """

## Antigravity

There is no `scout` agent in this harness. Do the reading you would have
handed to `scout` yourself."""


def split(text: str, path: Path) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        raise SystemExit(f"{path}: no frontmatter")
    head, _, body = text[4:].partition("\n---\n")
    return yaml.safe_load(head), body


def names(value) -> list[str]:
    if not value:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value]
    return [v.strip() for v in str(value).split(",") if v.strip()]


def convert(meta: dict, body: str, shipped: set[str], path: Path) -> str:
    spawns = names(meta.get("spawns"))
    children = [s for s in spawns if s in shipped]

    omp_tools = names(meta.get("tools"))
    unmapped = [t for t in omp_tools if t not in TOOLS]
    if unmapped:
        raise SystemExit(f"{path}: no agy tool for {unmapped}")
    tools = [t for o in omp_tools for t in TOOLS[o]] if omp_tools else list(ALL_TOOLS)
    if children:
        tools.append("invoke_subagent")
    tools = list(dict.fromkeys(tools))

    front = {
        "name": meta["name"],
        "description": meta["description"],
        "subagent": True,
        "mainAgent": False,
        "tools": tools,
    }
    if children:
        front["agents"] = [f"{c}.md" for c in children]

    lines = [f"{k}: {json.dumps(v, ensure_ascii=False)}" for k, v in front.items()]
    if "scout" in spawns:
        body = body.rstrip("\n") + SCOUT_NOTE + "\n"
    return "---\n" + "\n".join(lines) + "\n---\n" + body


def main(args: list[str]) -> int:
    if len(args) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(args[0])
    agents = {Path(a): split(Path(a).read_text(), Path(a)) for a in args[1:]}
    shipped = {meta["name"] for meta, _ in agents.values()}
    for path, (meta, body) in agents.items():
        (out / f"{meta['name']}.md").write_text(convert(meta, body, shipped, path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
