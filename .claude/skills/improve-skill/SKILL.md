---
description: Improve an existing skill's SKILL.md by applying user-described enhancements in-place, with follow-up questions when deeper refinement is warranted
argument-hint: '<skill-path> "<improvement>" ["<improvement>" ...]'
allowed-tools: Read, Search, Find, Write, Edit, Bash, Task, LSP
tool-hints: |
  Use `read` (with selectors like :50-100) instead of cat/head/tail.
  Use `search` instead of grep/rg.
  Use `find` instead of ls or find via bash.
  Use `write` instead of heredocs or cat <<EOF.
  Use `edit` instead of sed -i.
  Use `lsp diagnostics` to validate the skill file after edits.
  Use `bash` to dry-run argument parsing when the target skill has a parser script.
  Use `Task` subagents to cross-reference other skills for conventions in parallel.
---

Parse `$ARGUMENTS`:
- The first positional argument is `$SKILL_REF` — a reference to an existing skill. It can be:
  - A full path to a SKILL.md file: `.claude/skills/web-researcher/SKILL.md`
  - A path to a skill directory: `.claude/skills/web-researcher/` or `.claude/skills/web-researcher`
  - A bare skill name: `web-researcher` (resolves to `.claude/skills/web-researcher/SKILL.md`)
- All remaining positional arguments are `$IMPROVEMENTS` — one or more quoted strings, each describing a specific change, addition, or removal.
- If `$SKILL_REF` is empty or cannot be resolved to an existing SKILL.md file, ask "Which skill would you like to improve?" and provide examples of valid references.
- If no improvements are provided, ask "What would you like to improve about this skill?" and invite the user to describe one or more changes.
- Resolve `$SKILL_REF` to a concrete `$SKILL_PATH` before proceeding.

Example invocation:
```
/skill:improve-skill .claude/skills/web-researcher/SKILL.md \
  "Add instructions to ask questions or do preliminary searches to understand the topic before breaking it into subtopics." \
  "Don't limit yourself or aim for a specific number of sub-searches. Come up with a number needed based on the complexity of the research topic."
```

Resolution rules for `$SKILL_REF`:
```bash
# If SKILL_REF ends with .md, use it directly
# If SKILL_REF ends with /, strip the trailing slash, then append /SKILL.md
# If SKILL_REF contains no slashes, prepend .claude/skills/ and append /SKILL.md
# Verify the resolved path exists and is readable
SKILL_PATH=$(realpath -- "$SKILL_REF" 2>/dev/null)
if [ -z "$SKILL_PATH" ]; then
  # Try as directory
  if [ -d "$SKILL_REF" ]; then
    SKILL_PATH="$SKILL_REF/SKILL.md"
  else
    # Try as bare name
    SKILL_PATH=".claude/skills/$SKILL_REF/SKILL.md"
  fi
fi
```

---

## Mode: Improve

Your job is to read the target skill, understand its structure, interpret the user's improvement instructions, apply them to the SKILL.md in-place, and report what changed. You work through sequential phases in one session.

### Phase 1 — Locate and validate

1. Resolve `$SKILL_REF` to a concrete `$SKILL_PATH` using the resolution rules above.
2. Verify the file exists and is readable with `read`. If the file does not exist, stop with: "Skill not found: `<path>`. Check the path or skill name and try again."
3. Confirm: "Found skill at `<resolved-path>`." Proceed.

### Phase 2 — Study the target skill

1. Read the full SKILL.md at `$SKILL_PATH`.
2. Identify and note its structural patterns:
   - Frontmatter fields (description, argument-hint, allowed-tools, tool-hints)
   - Argument parsing approach (inline bash, a parser script like parse-args.py, etc.)
   - Mode structure (how many modes, how they are delimited — `## Mode:` vs other headings)
   - Phase/step numbering conventions
   - Constraint formatting and location
   - Whether it references external scripts or state files
3. Read 1-2 related skills from `.claude/skills/*/SKILL.md` if needed to cross-reference conventions (e.g., if the target skill is a loop prompt, read another loop prompt skill; if it has a parser script, read a skill with a similar parser). Use `Task` subagents for parallel reads when comparing multiple skills.
4. Build a mental model of how the skill works end-to-end. You must understand the
   skill before you can improve it:
   - For **one-shot skills**: trace the full phase sequence. Know what each phase
     produces and hands off to the next.
   - For **multi-session skills**: trace the state machine through every state
     transition. Know which categories write which state files, and which state
     fields drive the routing.
   - For **loop prompts**: understand the gap-evaluation logic. Know what
     conditions trigger `sleep()` vs `exit_loop_mode()`.
   - If you cannot trace it end-to-end, you are not ready to edit — re-read the
     skill more carefully or cross-reference a similar skill.

### Phase 3 — Interpret and clarify improvements

For each improvement instruction in `$IMPROVEMENTS`:

1. **Interpret**: What specific change does this instruction call for? Is it a new section, a modification to existing text, a removal, a restructuring?
2. **Validate against the skill**: Does the instruction make sense given the skill's structure? Example: "Add a STOP line after Phase 3" only makes sense for multi-session skills with phase/category boundaries. If it does not apply, flag it rather than forcing it.
3. **Check for conflicts**: Do any improvement instructions contradict each other? (e.g., one says "make it more concise" and another says "add more detail to every step"). Flag conflicts explicitly with both instructions quoted.
4. **Go deeper**: If an instruction could be implemented in multiple materially different ways, or if you see a better approach than a literal reading of the instruction suggests, formulate a follow-up question. Examples of when to go deeper:
   - "Add a validation step" — Where in the skill's flow should validation happen? What exactly should it validate — argument parsing, output format, state consistency?
   - "Make it run faster" — Faster at what cost? Parallel subagents vs. fewer steps vs. skip optional checks?
   - An instruction that conflicts with the skill's design pattern (e.g., "remove all STOP lines" from a multi-session skill where STOP lines are load-bearing for context-window isolation).
   - An instruction that could be done literally but has a clearly superior alternative (e.g., "add a bullet list of all 20 sub-topics" when a state file table would be more maintainable).
5. **Present the plan**: After interpreting all improvements, present a brief plan:
   - For each improvement: the instruction, your interpretation, and the concrete edit(s) you will make.
   - Flag any conflicts or ambiguities.
   - If you have follow-up questions, ask them now before editing. Group related questions together.

If all improvements are single-section additions or isolated text replacements that
do not renumber anything, restructure modes, or change the skill's operational flow,
state "Applying all improvements directly — no clarifications needed" and proceed to
Phase 4 without waiting. If any improvement involves renumbering phases, splitting
or merging modes, or could change the skill's flow, always present the plan and wait
for confirmation — even if the instruction seems unambiguous to you.

### Phase 4 — Apply improvements

Apply edits using `edit` (prefer surgical, line-anchored edits over full rewrites). Follow these rules:

1. **Preserve formatting**: Match the target skill's existing indentation, heading levels, and line spacing. Do not reformat code blocks or frontmatter unless the improvement explicitly requires it.
2. **Edit order matters**: If improvement B depends on text added by improvement A, apply A first. If they are independent, order does not matter.
3. **One improvement at a time**: Apply each improvement as a discrete set of edits.
   After each improvement, re-read the affected sections to verify the edits landed
   correctly. If a re-read shows the edit didn't land as expected (wrong line,
   missing content, doubled text), report the failure in Phase 6 and stop. Do not
   continue with a broken file — the user can `git revert` and retry with corrected
   instructions.
4. **Insert new sections**: If adding a new phase, step, or constraint section, place it where it logically belongs in the skill's flow — not arbitrarily at the end.
5. **Update cross-references**: If you renumber phases or steps, update any internal references (e.g., "see Phase 3" → "see Phase 4").
6. **Tool-hints**: If the improvement adds a new tool dependency, verify it is in `allowed-tools` and add it if missing. Add a corresponding entry to `tool-hints` if the tool has a specific usage pattern worth documenting.
   See the tool-hints section of this file for the phrasing convention: each entry is a
   sentence starting with the tool name and describing when to use it
   (e.g., "Use `bash` to dry-run argument parsing when the target skill has a parser
   script."). Match that style.

7. **Example of a surgical edit**: Below is a concrete before/after showing what a
   good improvement looks like — a focused change with a clear rationale.

   **Instruction**: "Add instructions to ask clarifying questions before decomposing
   into sub-topics, and don't aim for a fixed number."

   **Before** (SETUP step 4 in web-researcher):
   > Decompose the primary question into 3–10 sub-topics.

   **After**:
   > If the primary question is broad, ambiguous, or could benefit from narrower scope,
   > first ask the user 1–2 clarifying questions. Then decompose the (now clarified)
   > question into as many sub-topics as its complexity warrants — do not aim for a
   > fixed range. A simple factual question may need 2 sub-topics; a multi-faceted
   > policy analysis may need 12.

   **Why the "After" is better**: The original instructs the agent to produce 3–10
   sub-topics regardless of the question's actual complexity, which forces padding
   for simple topics and truncation for complex ones. The revision ties the number
   of sub-topics to the question's complexity and adds a clarifying-questions gate
   that prevents the agent from decomposing an ill-defined question. Both changes
   make the skill more adaptive and reduce downstream rework.

### Phase 5 — Validate

1. **Argument parsing check**: If the target skill uses a parser script (like `parse-args.py`), construct a sample invocation matching the skill's expected input format and dry-run it:
   ```bash
   cd .claude/skills/<skill-name> && python3 parse-args.py << 'ARGSEOF'
   "test query" some context
   ARGSEOF
   ```
   Verify the script runs without errors and produces the expected variables. If the script fails, the skill's argument parsing section may have been broken by the edits — fix it before proceeding.
2. **Internal consistency check**: Read the full SKILL.md after all edits and verify:
   - Every category that says "STOP" or "stop" has a clear, unambiguous stopping point.
   - Mode names are consistent throughout the file.
   - All referenced files (state files, parser scripts, report paths) match the skill's directory structure.
   - Every tool referenced in instructions appears in `allowed-tools`.
3. **LSP diagnostics**: Run `lsp diagnostics` on the file for any syntax issues in code blocks.
4. **Final coherence pass**: Read the full SKILL.md one last time as if you were the
   agent receiving these instructions for the first time. Ask yourself:
   - Would every step make sense without prior context?
   - Are there any leftover artifacts from the edits (orphaned references, duplicate
     lines, inconsistent numbering)?
   - Does the skill still achieve its original purpose, just improved?
   If any issues surface, fix them before moving to Phase 6.

### Phase 6 — Report

Produce a concise summary of what was changed:

```
## Improvements applied to <skill-name>

### 1. <Improvement instruction (summarized)>
- **What changed**: <description of edits, with line references>
- **Why**: <brief rationale>

### 2. <Improvement instruction (summarized)>
...
```

If any improvements were deferred or modified from the user's original instruction (due to conflicts, ambiguity, or a better approach surfaced during analysis), note them explicitly:

```
## Deferred or modified

- **"<original instruction>"**: <why it was deferred or modified and what was done instead>
```

## Constraints

- You may read any file under `.claude/skills/` and cross-reference other skills for conventions.
- You may edit the target SKILL.md file in-place.
- You may run bash commands for argument parsing validation and file resolution.
- You may ask follow-up questions when an improvement is ambiguous or could be done better than described.
- You may not create new skill directories or files outside the target skill's directory.
- You may not delete the target skill's directory or any files within it.
- You may not fundamentally change the skill's purpose — improvements refine, they do not repurpose.
- Do not add speculative improvements beyond what the user asked for or what follow-up discussion explicitly authorized.
