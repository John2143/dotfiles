#!/usr/bin/env python3
"""Adapt an OMP-authored SKILL.md for Claude Code, rewriting it in place.

The skills in .claude/skills/ are written for OMP. Two things differ in
Claude Code and are translated here:

* `allowed-tools` vocabulary — OMP lists Search/Find/LSP/AstGrep/Browser/Ask/
  Debug; Claude Code knows Grep/Glob/WebFetch/AskUserQuestion instead. Tools
  without a Claude Code counterpart are dropped rather than widened to Bash.
* Slash commands — OMP invokes skills as `/skill:name`, Claude Code as `/name`.

`tool-hints` is an OMP-only frontmatter key that Claude Code ignores, so its
text moves into the body as a "## Tool hints" section instead of being lost.

Usage: claude-skills.py <SKILL.md> [<SKILL.md> ...]
"""

import re
import sys
from pathlib import Path

# OMP's tool vocabulary, lower-cased for lookup, mapped to the Claude Code
# equivalent. Claude Code only pre-approves names it knows, so anything left
# untranslated silently does nothing.
TOOL_ALIASES = {
    "read": "Read",
    "write": "Write",
    "edit": "Edit",
    "bash": "Bash",
    "grep": "Grep",
    "glob": "Glob",
    "search": "Grep",
    "find": "Glob",
    "lsp": "Grep",
    "astgrep": "Grep",
    "ast_grep": "Grep",
    "browser": "WebFetch",
    "webfetch": "WebFetch",
    "websearch": "WebSearch",
    "ask": "AskUserQuestion",
    "task": "Task",
    "todowrite": "TodoWrite",
    "todo_write": "TodoWrite",
    "notebookedit": "NotebookEdit",
    "exit_plan_mode": "ExitPlanMode",
    "exitplanmode": "ExitPlanMode",
}

# No Claude Code counterpart. Debug has none, and exit_loop_mode belongs to
# OMP's /loop harness; both are dropped rather than widened to Bash, which
# would pre-approve arbitrary shell for the turn the skill runs.
DROPPED_TOOLS = {"debug", "exit_loop_mode", "exitloopmode"}

# Claude Code names MCP tools mcp__<server>__<tool>; OMP joins them with a
# single underscore. Longest server name first so prefixes can't shadow.
MCP_SERVERS = ("personal_diary_admin", "ai_tasks")

# A tool name, optionally carrying a permission rule: Bash(git add *)
TOKEN_RE = re.compile(r"[A-Za-z_][\w.:/-]*(?:\([^)]*\))?")


def convert_tool(name: str) -> str | None:
    if "(" in name:
        return name  # Bash(git add *) style rule — keep the rule verbatim
    lower = name.lower()
    if lower in DROPPED_TOOLS:
        return None
    for server in MCP_SERVERS:
        prefix = f"mcp__{server}_"
        if name.startswith(prefix):
            return f"mcp__{server}__{name[len(prefix):]}"
    return TOOL_ALIASES.get(lower, name)


def convert_tools(value: str) -> str:
    tools: list[str] = []
    for token in TOKEN_RE.findall(value):
        tool = convert_tool(token)
        if tool and tool not in tools:
            tools.append(tool)
    return ", ".join(tools)


def dedent_block(lines: list[str]) -> str:
    indents = [len(line) - len(line.lstrip()) for line in lines if line.strip()]
    cut = min(indents) if indents else 0
    return "\n".join(line[cut:].rstrip() for line in lines).strip("\n")


def rewrite_frontmatter(frontmatter: list[str]) -> tuple[list[str], str | None]:
    """Translate allowed-tools and lift tool-hints out of the frontmatter."""
    out: list[str] = []
    hints: str | None = None
    i = 0
    while i < len(frontmatter):
        line = frontmatter[i]
        key = line.split(":", 1)[0].strip()
        if key == "allowed-tools":
            inline = line.split(":", 1)[1].strip()
            items = [inline] if inline else []
            i += 1
            while i < len(frontmatter) and frontmatter[i].lstrip().startswith("- "):
                items.append(frontmatter[i].lstrip()[2:].strip())
                i += 1
            converted = convert_tools(" ".join(items))
            if converted:
                out.append(f"allowed-tools: {converted}")
            continue
        if key == "tool-hints":
            block: list[str] = []
            i += 1
            while i < len(frontmatter) and (
                not frontmatter[i].strip() or frontmatter[i].startswith((" ", "\t"))
            ):
                block.append(frontmatter[i])
                i += 1
            hints = dedent_block(block)
            continue
        out.append(line)
        i += 1
    return out, hints


def convert_uris(text: str) -> str:
    """Rewrite OMP's internal URIs into things Claude Code can act on."""
    # /skill:name -> /name, and skill://name (how OMP names skills in prose).
    text = text.replace("/skill:", "/").replace("skill://", "/")
    # local://PATH is relative to the repo root for both harnesses.
    return text.replace("local://", "./")


def convert_self_paths(text: str, skill: str) -> str:
    """Point a skill's own asset references at ${CLAUDE_SKILL_DIR}.

    `.claude/skills/<skill>/...` only resolves when the session happens to run
    in a repo that has the skills checked out; the substitution variable works
    from wherever the skill is installed.
    """
    # Leading boundary keeps paths like `dotfiles/.claude/skills/...` intact.
    pattern = re.compile(
        rf"(?<![\w/.-])(?:~|\$HOME)?/?(?:\./)?\.claude/skills/{re.escape(skill)}/"
    )
    return pattern.sub("${CLAUDE_SKILL_DIR}/", text)


def convert(text: str, skill: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return text

    frontmatter, hints = rewrite_frontmatter(lines[1:end])
    body = convert_self_paths(convert_uris("\n".join(lines[end + 1 :])), skill)

    parts = ["---", *(convert_uris(line) for line in frontmatter), "---", ""]
    if hints:
        parts += ["## Tool hints", "", convert_self_paths(hints, skill), ""]
    parts.append(body.strip("\n"))
    return "\n".join(parts) + "\n"


def main(paths: list[str]) -> int:
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    for arg in paths:
        path = Path(arg)
        path.write_text(convert(path.read_text(), path.parent.name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
