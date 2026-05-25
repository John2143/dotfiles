---
description: "One-shot skill that decomposes a complex, multi-faceted task into independent, self-contained subplans for parallel sub-agent execution. Researches, plans, writes plan files — zero implementation, zero agent launches, zero state mutation outside the plan directory. ⚠ NOT for simple or single-file tasks — use /plan for tasks with clear scope under ~3 files. This skill is for problems that genuinely need parallel decomposition."
argument-hint: "[prompt] [--output <dir>]"
allowed-tools: Read, Write, Edit, Bash, Task, Search, Find, LSP, AstGrep, Browser, Ask
tool-hints: |
  Use Task subagents for parallel research into unfamiliar subsystems.
  The ONLY files you may write or edit live inside the plan temp directory.
  Never modify code, configs, or system state outside the plan directory.
  This skill produces plan files only; it does not execute them.
---

## Usage

**Invocation:** `/skill:big-plan [prompt] [--output <dir>]`

- `prompt` — The task description to decompose into independent subplans. Required; the skill asks if missing.
- `--output <dir>` — Directory where plan files are written. Defaults to a temporary directory created via `mktemp`.

**Examples:**
- `/skill:big-plan "Add authentication middleware to the API server"` — Decomposes the auth task into subplans in a temp directory.
- `/skill:big-plan "Refactor the database layer" --output ./plans/db-refactor` — Writes plans to `./plans/db-refactor` instead of a temp directory.

Parse `$ARGUMENTS`:
- First positional argument is `$PROMPT` — the task description to decompose into subplans.
- `--output <dir>` — override the plan directory path. Default: `mktemp -d "ai-plan-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")-XXXXXXX"`.
- If `$PROMPT` is empty or missing, ask: "What task should I decompose into subplans?"

---

## Mode: Plan Decomposition

**You produce plan files. Nothing else.** <!-- changed -->
You write plan markdown into `$PLAN_DIR` and exit. You do NOT implement the task, run builds or tests, mutate repo state, create git worktrees, or launch sub-agents to execute what you wrote. The orchestrator (or user) executes the plans later — your job ends when the plan directory is validated. <!-- changed -->

### Step 1 — Setup

1. Determine `REPO_NAME`: run `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
2. Create the plan directory:
   ```bash
   PLAN_DIR=$(mktemp -d "ai-plan-${REPO_NAME}-XXXXXXX")
   ```
   If `--output <dir>` was provided, use that path instead (create it with `mkdir -p`).
3. Write the full, unaltered prompt to `$PLAN_DIR/original-prompt.md`:
   ```markdown
   # Original Prompt
   [verbatim $PROMPT — do not paraphrase, summarize, or omit anything]
   ```

### Step 2 — Research (read-only)

Gather enough context to decompose the task accurately. You may:

- Read repo structure, relevant files, conventions, and existing patterns.
- Use `Task(explore)` subagents to scout unfamiliar subsystems in parallel. Each explore subagent gets a narrow target (one directory, one subsystem) and returns a summary of relevant files, patterns, and gotchas.
- Use `Search`, `Find`, `LSP`, `AstGrep`, `Browser`, or any other read-only tool.
- Read `AGENTS.md` or `CLAUDE.md` if present in the repo root for project-specific conventions.

**When to use Task subagents vs. inline research:** If the task spans 3+ distinct subsystems or directories, spawn one explore subagent per subsystem. If the task is scoped to 1–2 subsystems, research inline. Each explore subagent must receive a narrow target and explicit deliverable (e.g., "list all files in src/auth/ and summarize the authentication flow").

Read-only means read-only: do not write outside `$PLAN_DIR`, do not run builds, tests, formatters, or any command that changes state. (See full constraints at the end of this document.) <!-- changed -->

If the task is vague or underspecified, ask 1–3 clarifying questions before proceeding. Do not guess at boundaries that will cause downstream rework.

### Step 3 — Decompose

Break the task into independent sub-tasks. Rules:

- Each sub-task must be **fully self-contained** — a sub-agent can execute it with zero external context beyond the plan file.
- Sub-tasks must not share mutable state or write to the same files (file collision check — see below). <!-- changed -->
- Aim for **2–7 subplans**. Hard rules at the boundaries: <!-- changed -->
  - If research shows only **1** self-contained chunk of work, **stop and recommend `/plan` instead** — do not emit a single-subplan directory. <!-- changed -->
  - If you find yourself wanting **>7** subplans, the decomposition is too granular; coalesce related sub-tasks. <!-- changed -->
- Think in a DAG: identify what depends on what. Maximize parallelism — independent sub-tasks should be dispatchable simultaneously. Sequential subplans still go in separate files; the Index records the dependency.
- A sub-task that depends on another's output MUST state, in its Context and Steps sections, exactly which upstream plan produced that output and where the output lives.  <!-- changed -->
- Two **read-only research** subplans MAY explore the same question from different angles for diversity of perspective, but only if both emit reports (not file edits). Write-target subplans MUST be disjoint. <!-- changed -->

**File collision check** (mandatory before writing subplans): list the write targets of all proposed subplans. No two parallel subplans may write to the same file. If they do, merge them, sequentialize them, or scope each to disjoint sections of the file and document the section boundaries in both plans' Notes. <!-- changed -->

### Step 4 — Write subplans

For each sub-task, write `$PLAN_DIR/plan-{slug}.md`. Derive `{slug}` from the task name by lowercasing, replacing non-alphanumeric characters with hyphens, collapsing consecutive hyphens, and trimming to ≤40 characters. Keep slugs short and descriptive. <!-- changed -->

**Parallelism:** Subplans are independent by design — write them simultaneously via parallel `write` calls or Task subagents. `Index.md` (Step 5) is written last because it references every subplan.

**Size budget:** Target 40–120 lines per subplan. A subplan over ~150 lines usually signals that the sub-task itself should be decomposed further; go back to Step 3 if that happens. <!-- changed -->

Each subplan file must follow this exact structure:

```markdown
# Plan: [Task Name]

## Goal
[What should the sub-agent accomplish? Be specific and measurable. A fresh agent
reading only this file must understand exactly what "done" means.]

## Context
[Everything the sub-agent needs to know. The sub-agent receives NO other context —
not the original prompt, not the index, not other plans. Include:
- Language, framework, and toolchain
- File structure (which files are relevant and where they live)
- Dependencies and imports
- Coding conventions and patterns to follow
- Existing abstractions to reuse
- Constraints (what NOT to touch)
- If this plan depends on another plan's output, state exactly what output and where to find it
Be exhaustive — the sub-agent's success depends on this section.]

## Steps
[A rough outline of recommended steps. The sub-agent will plan its own detailed
approach; this is guidance, not a micromanaged script. Include:
- Suggested order of operations
- Key decision points
- When to stop and report back rather than forging ahead]

## Output
[Concrete deliverable. Be specific:
- File path(s) to create or modify
- Format and structure of any report
- Commit message or PR description if applicable
- Verification: how the sub-agent (and reviewer) can confirm the work is correct
"Do your best" is not an output specification.]

## Notes
[Warnings, gotchas, coordination notes. Include:
- "Agent X is also working on Y — coordinate at Z or avoid touching file A"
- STOP conditions: specific situations where the sub-agent should stop and report rather than continue
- Any assumptions the sub-agent should validate before acting
Optional if there are genuinely no warnings; do not pad with filler.]
```

#### Worked Example (abridged) <!-- changed -->

A real prompt from a NixOS dotfiles repo asked for 8 Phase-2 fixes across Hyprland (`nixos/home.nix`) and Waybar (`nixos/modules/waybar.nix`, `.config/waybar/style.css`): missing default workspaces, broken "+" workspace button, top gap, small icons, missing hover tooltips, lost urgent animation, clock hover/copy, and media play/pause behavior. <!-- changed -->

That prompt decomposed into three independent subplans, with file-collision boundaries spelled out in each plan's Notes section: <!-- changed -->

1. **`plan-waybar-styling.md`** — top gap, icon sizing, hover tooltip restoration, clock hover expansion + copy animation. Touches `.config/waybar/style.css` (font-size, gap, clock styles, copy keyframe wiring) and `nixos/modules/waybar.nix` (tooltip fields, clock copy action). <!-- changed -->
2. **`plan-hyprland-workspaces.md`** — persistent named workspaces in Waybar, fix window auto-routing by class in Hyprland's `window_rule`, fix the "+" `on-click` shell invocation. Touches `nixos/home.nix` (window_rule fixes) and `nixos/modules/waybar.nix` (workspaces module + custom/newworkspace only — disjoint from plan 1). <!-- changed -->
3. **`plan-media-animations.md`** — media script fallback text, pause-all vs unpause-Spotify click behavior, `@keyframes urgent-pulse` and `@keyframes copy-flash` definitions. Touches `nixos/modules/waybar.nix` (custom/media only) and `.config/waybar/style.css` (`@keyframes` blocks and `#custom-media`/`#workspaces button.urgent` only — disjoint from plan 1). <!-- changed -->

Sketch of one subplan's Context section (showing the level of detail expected — file paths, line numbers, conventions, known patterns to reuse): <!-- changed -->

```markdown
## Context (excerpt)
- `nixos/modules/waybar.nix` — Waybar Nix module. Custom modules emit JSON via
  shell scripts (`return-type = "json"`) producing `{text, class, tooltip}`.
  Reference working tooltip: CPU temp at line 285 (`tooltip = true`). Module
  order is `modules-left` / `modules-center` / `modules-right`.
- `.config/waybar/style.css` — Catppuccin Mocha palette via `@define-color` at
  top. Module pills: `background: @surface0; border-radius: 8px; padding: 0 10px;
  margin: 4px 3px;`. State classes: `.warning` (peach), `.critical` (red),
  `.playing` (green), `.paused` (yellow). Base font 14px (likely too small).
- Known issues: top gap on `window#waybar > box` (line 55); weather/audio modules
  lack `tooltip` field in their exec scripts; clock needs `on-hover` expansion
  and a Ctrl+C → `wl-copy` action with a `.copied` flash class.
```

The full three-plan walkthrough (with all Steps/Output/Notes sections) is intentionally omitted here — it was ~250 lines and crowded the actual instructions. Reproduce that level of detail in real subplans, but do not copy this example verbatim into output. <!-- changed -->

### Step 5 — Write Index.md

Write `$PLAN_DIR/Index.md`:

```markdown
# Goal
[High-level description of the overall task. What is the end state we want?
Not a list of steps — a description of what success looks like. 1–3 paragraphs.]

Link to original prompt: [original-prompt.md](original-prompt.md)

# Index of Plans
- [Plan: Task 1](plan-task-1.md): Brief description of what this plan accomplishes (1 sentence).
- [Plan: Task 2](plan-task-2.md): Brief description of what this plan accomplishes (1 sentence).
- ...

# Dependencies
[If subplans have dependencies, list them:
- plan-task-2.md depends on plan-task-1.md output at path/to/file
- plan-task-3.md and plan-task-4.md are fully independent and can run in parallel
If all plans are independent, write "All plans are independent and can be executed in parallel."
If subplans share a file with section-disjoint scopes, record the boundaries here too.] <!-- changed -->

# Conclusion
## Expected Result
[What do we expect after all plans are completed? What does the orchestrator do next?]

## Success Criteria
[How do we know the overall task succeeded? How do we know if it failed?
How confident should the final result be, and what would signal the need to
retry with more context or a different decomposition?]

## Launching Sub-Agents
Plans are executed by fresh sub-agents in isolated worktrees. To execute:

1. Create a worktree for the sub-agent:
   ```bash
   git worktree add /tmp/agent-<slug> -b omp/agent-<slug>
   ```
   Or use `/skill:agent-workspace` if available for sandboxed isolation.

2. Launch the agent with the plan file:
   ```bash
   omp launch -p "$(cat $PLAN_DIR/plan-task-1.md)" --no-session
   ```
   Or from an interactive session:
   ```
   /task:oracle "execute the plan at $PLAN_DIR/plan-task-1.md"
   ```

3. Independent plans can be launched simultaneously. Plans that depend on others'
   output must wait for those plans to complete.

4. After the agent completes, clean up the worktree:
   ```bash
   git worktree remove /tmp/agent-<slug> --force
   ```
```

### Step 6 — Validate & Stop

1. Read back every file in `$PLAN_DIR` and confirm:
   - `original-prompt.md` exists with the verbatim prompt — no paraphrasing, no omissions.
   - Every subplan has all required sections: Goal, Context, Steps, Output, Notes (Notes may be empty if genuinely nothing to warn about). <!-- changed -->
   - No subplan references files outside the plan directory as write targets.
   - No two parallel subplans write to the same file (or, if they share a file, both Notes sections document disjoint section boundaries). <!-- changed -->
   - `Index.md` links to every subplan and includes all required sections.
   - Every subplan's Goal section is specific and measurable — a fresh agent can determine "done."
   - Every subplan's Context section is exhaustive — no critical information lives only in your context window.
   - Every subplan is within the 40–120-line size budget (≤150 hard ceiling). <!-- changed -->

2. Report a summary to the user. The summary MUST include: <!-- changed -->
   - The **absolute** path to `$PLAN_DIR` on its own line, so it is copy-pasteable. <!-- changed -->
   - Number of subplans created and their filenames. <!-- changed -->
   - The dependency graph: which subplans are parallelizable, which are sequential, and any shared-file coordination notes. <!-- changed -->
   - How to launch sub-agents (point at `Index.md`'s "Launching Sub-Agents" section). <!-- changed -->
   - Any risks, assumptions, or open clarifications the orchestrator should know.

3. **STOP.** Your job ends here. Do not execute any plan, implement anything, create worktrees, launch sub-agents, run builds/tests, or commit. The plans are complete. <!-- changed -->

## Constraints

- **NEVER** write or edit files outside `$PLAN_DIR`.
- **NEVER** implement, execute, commit, run builds, tests, formatters, or any command that mutates repo or system state. <!-- changed -->
- **NEVER** launch sub-agents to execute the plans you wrote, and **NEVER** create git worktrees — you are the planner, not the orchestrator. <!-- changed -->
- **DO** ask clarifying questions if the prompt is too vague to decompose accurately (Step 2).
- **DO** use Task subagents for parallel **read-only** research during Step 2. <!-- changed -->
- **MAY** read any file in the repo for research purposes.
- **MAY** use any available read-only tool (Browser, LSP, AstGrep, etc.). <!-- changed -->
- If research shows the task is trivial (1 self-contained chunk, or under ~3 files), stop and recommend `/plan` instead of producing a single-subplan directory. <!-- changed -->
- If after thorough research the task genuinely cannot be decomposed into independent sub-tasks (tightly coupled monolithic change where every part depends on every other part), report this explicitly. Describe what makes it indivisible and suggest the user use `/plan` or a direct agent session instead. Do not force subplans that aren't truly independent — bad decomposition is worse than no decomposition. <!-- changed -->
