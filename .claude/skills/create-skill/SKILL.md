---
description: Guide the user through creating a new skill: scope definition, plan generation, and task decomposition
argument-hint: [idea] [--name name] [--refine]
allowed-tools: Read, Search, Find, Write, Edit, AstGrep, Bash, Ask
tool-hints: |
  Use `read` (with selectors like :50-100) instead of cat/head/tail.
  Use `search` instead of grep/rg.
  Use `find` instead of ls or find via bash.
  Use `write` instead of heredocs or cat <<EOF.
  Use `edit` instead of sed -i.
  Use `ast_grep` for structural code search and rewrites.
  This skill creates other skills; you will write a SKILL.md file and may need to invoke prompt-engineer.
---

## Usage

**Invocation:** `/skill:create-skill [idea] [--name name] [--refine]`

- `idea` — A description of what the skill should do (e.g., "a skill that checks logs and fixes issues in a loop"). If omitted, you will be prompted for it.
- `--name name` — Explicit skill directory name (kebab-case). If omitted, the name is derived automatically from the idea.
- `--refine` — Automatically run prompt-engineer on the resulting SKILL.md after writing it, skipping the Phase 5 offer.

**Examples:**
- `/skill:create-skill "a skill to monitor k8s pods and alert on crashes"` — Create a skill with auto-derived name
- `/skill:create-skill "monitor pods" --name k8s-watchdog` — Create a skill with an explicit directory name
- `/skill:create-skill "monitor pods" --refine` — Create a skill and automatically refine it with prompt-engineer

Parse `$ARGUMENTS`:
- First positional argument is the `$IDEA` — a description of what the skill should do (e.g., "I want a skill which helps me check logs, diagnose, plan, and fix issues automatically in a loop"). If omitted, ask the user for the idea before proceeding.
- If `--name $SKILL_NAME` is provided, use it as the skill directory name and kebab-case identifier. If omitted, derive it from `$IDEA` by running this exact bash snippet with the idea in `$IDEA`:
  ```bash
  SKILL_NAME=$(printf '%s' "$IDEA" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//' | cut -c1-48)
  if [ -z "$SKILL_NAME" ]; then echo "EMPTY_SLUG"; else echo "$SKILL_NAME"; fi
  ```
  If the output is `EMPTY_SLUG`, ask the user to provide `--name`.
- If the user passes `--refine`, automatically run prompt-engineer on the resulting file after writing it (skip the Phase 5 offer).

---

## Resolve target directory

Before proceeding with the scaffold, determine where to write the skill. Skills must live in a dotfiles repo so they can be committed and deployed.

Determine `$SKILLS_DIR` — the absolute path to the `.claude/skills/` directory in the user's dotfiles repo:

1. Check if the current working directory is already inside the dotfiles repo. Run:
   ```bash
   SKILLS_DIR_CANDIDATE=""
   if git rev-parse --show-toplevel 2>/dev/null; then
     TOP=$(git rev-parse --show-toplevel)
     REMOTE=$(git -C "$TOP" remote get-url origin 2>/dev/null)
     case "$REMOTE" in
       *John2143/dotfiles*|*2143-Labs/dotfiles*)
         SKILLS_DIR_CANDIDATE="$TOP/.claude/skills"
         ;;
     esac
   fi
   ```
2. If empty and a `dotfiles/` subdirectory exists in cwd:
   ```bash
   if [ -z "$SKILLS_DIR_CANDIDATE" ] && [ -d dotfiles/.git ]; then
     REMOTE=$(git -C dotfiles remote get-url origin 2>/dev/null)
     case "$REMOTE" in
       *John2143/dotfiles*|*2143-Labs/dotfiles*)
         SKILLS_DIR_CANDIDATE="$PWD/dotfiles/.claude/skills"
         ;;
     esac
   fi
   ```
3. If still empty, check common locations:
   ```bash
   for dir in "$HOME/dotfiles" "$HOME/repos/dotfiles"; do
     if [ -z "$SKILLS_DIR_CANDIDATE" ] && [ -d "$dir/.git" ]; then
       REMOTE=$(git -C "$dir" remote get-url origin 2>/dev/null)
       case "$REMOTE" in
         *John2143/dotfiles*|*2143-Labs/dotfiles*)
           SKILLS_DIR_CANDIDATE="$dir/.claude/skills"
           ;;
       esac
     fi
   done
   ```
4. If `$SKILLS_DIR_CANDIDATE` is still empty, ask the user: "I couldn't auto-detect a dotfiles repo. Where should I write this skill? Provide the full path to the `.claude/skills/` directory."
5. Set `$SKILLS_DIR` to the confirmed path. Create it if it doesn't exist:
   ```bash
   mkdir -p "$SKILLS_DIR"
   ```
6. Use `$SKILLS_DIR` for all file operations below. **Do not** write skills to the bare cwd `.claude/skills/` — always use `$SKILLS_DIR`.
## Mode: Interactive Skill Scaffolding

Your job is to produce a complete skill document (SKILL.md) under `$SKILLS_DIR/<skill-name>/` based on a user's idea. You work through five phases in order, presenting intermediate artifacts to the user before proceeding.

### Phase 1 — Clarify the idea

Use the `ask` tool to present all clarifying questions at once. Skip any dimension the user already answered in their `$IDEA`.

```json
{
  "questions": [
    {
      "id": "input",
      "question": "How will this skill be invoked? What arguments does it take?",
      "options": [
        { "label": "No arguments — just run it" },
        { "label": "A file or directory path" },
        { "label": "A search query or topic string" },
        { "label": "A commit range (e.g. HEAD~10)" },
        { "label": "Custom flags (e.g. --focus, --dry-run)" }
      ]
    },
    {
      "id": "output",
      "question": "What does the skill produce as its deliverable?",
      "options": [
        { "label": "Chat report only (read-only analysis)" },
        { "label": "A written file (report, config, code)" },
        { "label": "State files for multi-session tracking" },
        { "label": "A git commit" }
      ]
    },
    {
      "id": "pattern",
      "question": "What invocation pattern fits this skill?",
      "options": [
        { "label": "One-shot — run once, produce a result, done" },
        { "label": "Multi-session — user invokes repeatedly, state persists in files" },
        { "label": "Loop prompt — unattended, called by /loop harness with no arguments" }
      ]
    },
    {
      "id": "tools",
      "question": "Which tools does this skill need? (Select all that apply)",
      "multi": true,
      "options": [
        { "label": "Read / Search / Find (filesystem inspection)" },
        { "label": "Write / Edit (file modification)" },
        { "label": "LSP (code intelligence, refactoring)" },
        { "label": "Bash (shell commands, builds, tests)" },
        { "label": "AstGrep (structural search and rewrite)" },
        { "label": "Task (parallel subagents)" },
        { "label": "Browser (web interaction)" },
        { "label": "Debug (debugger integration)" }
      ]
    },
    {
      "id": "constraints",
      "question": "What should the agent NOT do?",
      "options": [
        { "label": "Read-only — never modify files" },
        { "label": "No destructive commands (rm, force-push, etc.)" },
        { "label": "Repo-scoped only — no writes outside the repo" },
        { "label": "No network access" },
        { "label": "No specific restrictions beyond defaults" }
      ]
    },
    {
      "id": "context",
      "question": "What codebase or environment does this skill target?",
      "options": [
        { "label": "Generic — works in any repo" },
        { "label": "NixOS / home-manager configurations" },
        { "label": "This specific repo only" },
        { "label": "Kubernetes / k3s clusters" },
        { "label": "Rust / Cargo projects" }
      ]
    }
  ]
}
```

After the user responds, produce a short **Scope Summary** (3-5 sentences) confirming your understanding. Present it in chat.
After presenting the Scope Summary, STOP and wait for the user to confirm before proceeding to Phase 2. Do not begin Phase 2 until the user explicitly approves the summary. If the user requests changes, revise the summary and wait again.

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

For **multi-session skills** (user invokes the skill several times; each invocation does one unit of work with state in files), the body should include:
1. **Key files** — state file layout (what files track progress between sessions)
2. **How to start each session** — read state, determine what to do next
3. **How to work** — execution categories, one per session
4. **Constraints** — may/may-not rules
5. **TLDR** — 2-3 sentence summary with "stop" instruction

For **loop prompts** (designed for the `/loop` harness, which calls the same prompt repeatedly with no arguments), the body must additionally include:
- A **gap-evaluation checklist** in "How to start each session" — the agent must decide whether there is work to do before acting. If no work exists, the agent should use Bash `sleep <seconds>` to pause and retry later, or call **`exit_loop_mode(reason)`** to stop permanently.
- "Do not ask questions" in constraints (the agent runs unattended).
- See `$SKILLS_DIR/prompt-engineer/SKILL.md` Mode: Loop Prompt Generation for the full template.

Present the proposed design to the user as a structured outline, then STOP and wait for confirmation before proceeding to Phase 3. Do not begin Phase 3 until the user explicitly approves the design.

### Phase 3 — Research

First, save the current skill draft — based on the Phase 2 design and all clarifications so far — to a temporary file.

1. Ensure the directory exists:
   ```bash
   mkdir -p "$SKILLS_DIR/<skill-name>/"
   ```
2. Write the draft to `$SKILLS_DIR/<skill-name>/SKILL.draft.md` using `write`. Include:
   - Complete frontmatter (as designed in Phase 2).
   - Argument parsing section.
   - Mode structure outline with section headings and brief content notes.
   - This draft will evolve into the final SKILL.md in Phase 4 — write real content, not placeholders.
3. Verify the draft was saved: use `read` to check the first 10 lines of `$SKILLS_DIR/<skill-name>/SKILL.draft.md`. If the file is missing, empty, or truncated, STOP and report: "Draft save failed: \<reason\>." Do not continue to research until the draft is confirmed saved.
Then research the following using your tools:

- Read 2-3 existing skills from `$SKILLS_DIR/*/SKILL.md` to match conventions, argument patterns, and frontmatter style.
- If the skill targets a specific tool or runtime (e.g., `nix`, `docker`, `kubectl`), check whether it's available in the environment.
- If the skill references specific files or directories in the repo, verify they exist.

Report findings concisely. Flag any risks (e.g., tool unavailable, ambiguous naming).

After reporting findings, STOP and wait for the user to confirm before proceeding to Phase 4. Ask explicitly: "Ready to write the final SKILL.md based on these findings?" Do not begin Phase 4 until the user approves.
### Phase 4 — Write the skill

Write the SKILL.md file to `$SKILLS_DIR/<skill-name>/SKILL.md`.

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

After presenting the checklist, STOP and wait for the user to review the written skill before proceeding to Phase 5. The user may want changes to the file — apply any requested edits and re-present the checklist. Do not offer Phase 5 until the user signals satisfaction.
### Phase 5 — Refine

If the user passed `--refine`, run the prompt-engineer refinement automatically. Otherwise, offer to run it:

- For one-shot and multi-session skills: `/skill:prompt-engineer $SKILLS_DIR/<skill-name>/SKILL.md`
- For loop prompts (for `/loop` harness): `/skill:prompt-engineer loop $SKILLS_DIR/<skill-name>/SKILL.md`

If the user accepts, follow the prompt-engineer skill instructions and apply the revised prompt back to the file.
