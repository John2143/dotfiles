---
description: Guide the user through creating a new skill: scope definition, plan generation, and task decomposition
argument-hint: [idea] [--name name] [--refine]
allowed-tools: Read, Search, Find, Write, Edit, AstGrep, Bash
tool-hints: |
  Use `read` (with selectors like :50-100) instead of cat/head/tail.
  Use `search` instead of grep/rg.
  Use `find` instead of ls or find via bash.
  Use `write` instead of heredocs or cat <<EOF.
  Use `edit` instead of sed -i.
  Use `ast_grep` for structural code search and rewrites.
  This skill creates other skills; you will write a SKILL.md file and may need to invoke prompt-engineer.
---

Parse `$ARGUMENTS`:
- First positional argument is the `$IDEA` — a description of what the skill should do (e.g., "I want a skill which helps me check logs, diagnose, plan, and fix issues automatically in a loop"). If omitted, ask the user for the idea before proceeding.
- If `--name $SKILL_NAME` is provided, use it as the skill directory name and kebab-case identifier. If omitted, derive it from `$IDEA` by: lowercasing, replacing spaces and non-alphanumeric chars with hyphens, collapsing consecutive hyphens, then stripping leading/trailing hyphens. Truncate to 48 characters.
- If the user passes `--refine`, automatically run prompt-engineer on the resulting file after writing it (skip the Phase 5 offer).

---

## Mode: Interactive Skill Scaffolding

Your job is to produce a complete skill document (SKILL.md) under `.claude/skills/<skill-name>/` based on a user's idea. You work through five phases in order, presenting intermediate artifacts to the user before proceeding.

### Phase 1 — Clarify the idea

Ask clarifying questions to narrow scope. The user may have given only a one-line idea. Probe the following dimensions (skip any the user already answered):

1. **Input / invocation** — How will this skill be invoked? What arguments does it take? (e.g., `[path] [--focus correctness]`, `[symptom]`, `[scope]`)
2. **Output / deliverable** — What does the skill produce? A file? A report in chat? A side-effect like a commit? A loop prompt that writes state files?
3. **Loop vs one-shot** — Does this skill run once (one-shot) and produce a result, or does it run in a loop (each invocation does a small unit of work, maintaining state between runs)?
4. **Allowed tools** — What tools does this skill need? (Review existing skills for common patterns: Read, Search, Find, Write, Edit, LSP, Bash, Debug, AstGrep)
5. **Constraints** — What should the agent not do? Delete files? Modify production configs? Run destructive commands?
6. **Target repo/context** — What codebase or environment does this skill operate in? Is it generic or repo-specific?

Ask all questions at once in a numbered list, then wait for the user's response before proceeding.

After the user responds, produce a short **Scope Summary** (3-5 sentences) confirming your understanding. Present it in chat.

### Phase 2 — Design the skill structure

Design the SKILL.md document. Every skill follows this structure:

```yaml
---
description:       # One-line summary, imperative tone
argument-hint:     # Usage hint like '[path] [--option value]'
allowed-tools:     # Comma-separated list from existing patterns
tool-hints:        # Brief usage reminders, optional
---
```

```markdown
Parse `$ARGUMENTS`:       # Argument extraction rules
---

## Mode: [Mode Name]       # One or more modes

### Phase/Step X — ...
  Instructions for each mode.
```

For **one-shot skills**, the body contains sequential steps or phases in one or more modes.

For **loop skills**, the body must contain exactly these sections:
1. **One-line purpose**
2. **Key files** — state file layout
3. **How to start each session** — with a gap-evaluation checklist
4. **How to work** — execution rules, one category per session
5. **Constraints** — may/may-not rules
6. **TLDR** — 2-3 sentence summary with "stop" instruction

Present the proposed design to the user as a structured outline. Ask for confirmation before proceeding.

### Phase 3 — Research

Before writing, research the following using your tools:

- Read 2-3 existing skills from `.claude/skills/*/SKILL.md` to match conventions, argument patterns, and frontmatter style.
- If the skill targets a specific tool or runtime (e.g., `nix`, `docker`, `kubectl`), check whether it's available in the environment.
- If the skill references specific files or directories in the repo, verify they exist.

Report findings concisely. Flag any risks (e.g., tool unavailable, ambiguous naming).

### Phase 4 — Write the skill

Write the SKILL.md file to `.claude/skills/<skill-name>/SKILL.md`.

Include:
- Complete YAML frontmatter with `description`, `argument-hint`, `allowed-tools`, and `tool-hints`.
- Argument parsing section.
- One or more modes as designed in Phase 2.
- Every instruction must be self-contained — a fresh agent with no prior context must be able to follow it correctly on the first run.
- Use concrete examples where applicable.
- Do not add placeholder sections or "TODO" markers.
- Write the file using `write`.

After writing, present a brief **checklist** to the user:
- [ ] Name and description are correct
- [ ] Arguments are parsed correctly
- [ ] All modes are accounted for
- [ ] Instructions are self-contained

### Phase 5 — Refine

If the user passed `--refine`, run the prompt-engineer refinement automatically. Otherwise, offer to run it:

- For one-shot skills: `/skill:prompt-engineer .claude/skills/<skill-name>/SKILL.md`
- For loop skills: `/skill:prompt-engineer loop .claude/skills/<skill-name>/SKILL.md`

If the user accepts, follow the prompt-engineer skill instructions and apply the revised prompt back to the file.
