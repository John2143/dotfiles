#!/usr/bin/env python3
"""Adapt an OMP-authored SKILL.md for another harness, rewriting it in place.

The skills in .claude/skills/ are written for OMP. Two things differ in
Claude Code and are translated here:

* `allowed-tools` vocabulary — OMP lists Search/Find/LSP/AstGrep/Browser/Ask/
  Debug; Claude Code knows Grep/Glob/WebFetch/AskUserQuestion instead. Tools
  without a Claude Code counterpart are dropped rather than widened to Bash.
* Slash commands — OMP invokes skills as `/skill:name`, Claude Code as `/name`.

`tool-hints` is an OMP-only frontmatter key that Claude Code ignores, so its
text moves into the body as a "## Tool hints" section instead of being lost.

`--agy ROOT` targets the Antigravity CLI instead, for skills installed under
ROOT (one directory per skill). agy differs from Claude Code in three ways:

* It parses frontmatter as strict YAML and silently skips a skill that fails,
  so `argument-hint: [a] [b]` (two flow sequences) kills the skill. The
  free-text values (description, argument-hint) are re-emitted as quoted
  strings, and the result is checked with a YAML parser so a bad skill fails
  the build instead of vanishing.
* It requires `name`; OMP takes the folder name, so it is added.
* It has no `allowed-tools` and no ${CLAUDE_SKILL_DIR}: the key is dropped and
  a skill's references to its own files point at ROOT/<skill>/.

Usage: convert-skills.py [--agy ROOT] <SKILL.md> [<SKILL.md> ...]
"""

import json
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
    "todo": "TodoWrite",
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
# Wildcards do not survive this rewrite — mcp__ai_tasks__* comes out as
# mcp__ai_tasks___* — so enumerate the tools the skill actually needs.
MCP_SERVERS = ("personal_diary_admin", "ai_tasks")

# A tool name, optionally carrying a permission rule: Bash(git add *)
TOKEN_RE = re.compile(r"[A-Za-z_][\w.:/-]*(?:\([^)]*\))?")

# Free-text frontmatter values agy's strict YAML parser can trip on. Other keys
# keep their YAML types (disable-model-invocation: true stays a boolean).
QUOTED_KEYS = {"description", "argument-hint"}


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


def quote_scalar(line: str) -> str:
    """Re-emit a plain `key: value` line with its value as a quoted string.

    Quoted values, block scalars (| and >) and empty values (a nested block
    follows) are left alone. A JSON string is a valid YAML double-quoted one.
    """
    key, _, value = line.partition(":")
    value = value.strip()
    if not value or value[0] in "\"'|>":
        return line
    return f"{key}: {json.dumps(value, ensure_ascii=False)}"


def rewrite_frontmatter(
    frontmatter: list[str], agy: bool = False
) -> tuple[list[str], str | None]:
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
            if converted and not agy:
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
        if agy and key in QUOTED_KEYS:
            line = quote_scalar(line)
        out.append(line)
        i += 1
    return out, hints


def convert_uris(text: str) -> str:
    """Rewrite OMP's internal URIs into things Claude Code can act on."""
    # /skill:name -> /name, and skill://name (how OMP names skills in prose).
    text = text.replace("/skill:", "/").replace("skill://", "/")
    # local://PATH is relative to the repo root for both harnesses.
    return text.replace("local://", "./")


def convert_self_paths(text: str, skill: str, skill_dir: str) -> str:
    """Point a skill's own asset references at where it is installed.

    `.claude/skills/<skill>/...` only resolves when the session happens to run
    in a repo that has the skills checked out; the install location works
    from anywhere. For Claude Code that is the ${CLAUDE_SKILL_DIR} variable.
    """
    # Leading boundary keeps paths like `dotfiles/.claude/skills/...` intact.
    pattern = re.compile(
        rf"(?<![\w/.-])(?:~|\$HOME)?/?(?:\./)?\.claude/skills/{re.escape(skill)}/"
    )
    return pattern.sub(lambda _: skill_dir, text)


def check_yaml(frontmatter: list[str], skill: str) -> None:
    import yaml

    data = yaml.safe_load("\n".join(frontmatter))
    if not isinstance(data, dict) or not data.get("description"):
        raise SystemExit(f"{skill}: frontmatter has no description")


def convert(text: str, skill: str, agy_root: str | None = None) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return text

    agy = agy_root is not None
    skill_dir = f"{agy_root}/{skill}/" if agy else "${CLAUDE_SKILL_DIR}/"
    frontmatter, hints = rewrite_frontmatter(lines[1:end], agy)
    body = convert_self_paths(
        convert_uris("\n".join(lines[end + 1 :])), skill, skill_dir
    )
    frontmatter = [convert_uris(line) for line in frontmatter]
    if agy:
        if not any(line.startswith("name:") for line in frontmatter):
            frontmatter.insert(0, f"name: {skill}")
        check_yaml(frontmatter, skill)

    parts = ["---", *frontmatter, "---", ""]
    if hints:
        parts += ["## Tool hints", "", convert_self_paths(hints, skill, skill_dir), ""]
    parts.append(body.strip("\n"))
    return "\n".join(parts) + "\n"


def main(args: list[str]) -> int:
    agy_root = None
    if args[:1] == ["--agy"] and len(args) > 1:
        agy_root, args = args[1].rstrip("/"), args[2:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    for arg in args:
        path = Path(arg)
        path.write_text(convert(path.read_text(), path.parent.name, agy_root))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
