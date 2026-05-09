---
description: Improve an existing prompt file, or generate a new loop prompt for the current repo
argument-hint: [path/to/prompt.md | loop]
allowed-tools: Read, Search, Find, Write, Edit, AstGrep, Bash
tool-hints: |
  Use `read` (with selectors like :50-100) instead of cat/head/tail.
  Use `search` instead of grep/rg.
  Use `find` instead of ls or find via bash.
  Use `write` instead of heredocs or cat <<EOF.
  Use `edit` instead of sed -i.
  Use `ast_grep` for structural code search and rewrites.
---

Parse `$ARGUMENTS`:
- Normalize the argument: strip leading `./`, trailing `/`, and surrounding whitespace before matching.
- If the normalized argument is exactly `loop`, follow **Mode: Loop Prompt Generation** below.
- Otherwise treat it as a file path and follow **Mode: Prompt Improvement** below.
- If no argument was given, ask the user whether they want to improve an existing prompt (provide the path) or generate a loop prompt for this repo.
- If the given path does not exist or is a directory: report the error and suggest a valid prompt file path.
- If the file exceeds ~200 lines: focus analysis on the frontmatter and opening instructions, and note the truncation.

---

## Mode: Prompt Improvement

You are an expert prompt engineer. Read the file at the given path and produce a prioritized list of concrete improvement suggestions.

### Analysis framework

Evaluate the prompt on these dimensions in order:

1. **Goal clarity** — Is the primary objective stated unambiguously in the first few lines? Could a new reader misinterpret what success looks like?

2. **Scope & constraints** — Are the boundaries of the task explicit? What should the agent do vs. refuse? Are edge cases covered or at least acknowledged?

3. **Output format** — Is the expected output format (structure, length, tone, examples) specified? If the prompt produces free-form output, is that intentional?

4. **Step decomposition** — For multi-step tasks, are the steps ordered logically? Are dependencies between steps explicit? Would parallel execution be possible and beneficial?

5. **Examples** — Are there input/output examples? If not, would one or two examples eliminate ambiguity that prose cannot?

6. **Agent/tool guidance** — Are the right tools called out? Are there tool restrictions that should be added? Should sub-agents be used for parallelism or context isolation?

7. **Failure modes** — Does the prompt handle the most common failure cases (missing input, ambiguous state, no results found)?

8. **Redundancy & noise** — Is there text that restates what is already obvious, or instructions that contradict each other?

### Output format

Produce your response in three sections:

#### Summary
Two sentences: what this prompt does well, and what the biggest single gap is.

#### Suggested improvements
A numbered list. Each item must:
- Name the dimension being addressed (from the framework above)
- State the specific problem in the current prompt (quote the relevant text if short)
- Give a concrete rewrite or addition — not just "add an example" but the actual example text

Order by impact: highest-impact changes first. Stop at 8 items max; quality over quantity.

*Example improvement item (for illustration only — do not include this specific item in your output):*
*1. **Goal clarity** — The first paragraph reads "This prompt helps you write good prompts" which conflates audience (the agent) with purpose (the deliverable). Replace with: "Your job is to critique and rewrite a given prompt document." This makes the agent the subject and the prompt file the object.*

#### Revised prompt
Produce a full rewrite of the prompt incorporating all your suggestions. Preserve the original frontmatter unless a field itself needs changing. Mark any line you changed with a `<!-- changed -->` HTML comment so the user can diff by eye.

Display the revised prompt in your output. Do not write it back to the file unless the user explicitly asks.

### Notes

- Treat this as a peer code review, not a critique. Be direct but constructive.
- Do not suggest changes that introduce ambiguity in order to remove verbosity.
- If the prompt is already tight and well-structured, say so clearly — do not invent problems.

---

## Mode: Loop Prompt Generation

This mode generates a loop prompt: a self-contained instruction document designed for the `/loop` harness, which calls the same prompt repeatedly with no arguments. Each invocation does a small, atomic unit of work and then stops. The agent maintains state between runs via files it writes to the repo.

**This is distinct from a multi-session skill** (user-invoked, user controls timing). A loop prompt must include a gap-evaluation step at the start of every session to decide whether work exists — if not, it must sleep rather than invent work. A multi-session skill assumes the user only invokes it when work is needed.

### Step 1 — Explore the repo

Use your tools to build a picture of the repo:
- Read `CLAUDE.md` (root and any subdirectories) if present
- List the top-level directory structure with `read` on the repo root
- Read any existing goals, plan, or task-queue files if they exist
- Identify: what is being built or maintained, what the main deliverable(s) are, and what categories of ongoing work are likely to repeat

### Step 2 — Design the state file layout

Before writing the prompt, decide on the minimal set of files the agent will use to manage state across runs. A good loop prompt needs exactly these three types:

| Role | Suggested filename | Purpose |
|------|-------------------|---------|
| Task queue | `goals_for_the_next_agent.md` | Prioritized list of work items; agent reads this first and marks items ✅ when done |
| Main deliverable(s) | (derive from repo) | The artifact(s) the agent improves each run |
| Background & scope | `background_and_goals.md` | Requirements, scope, constraints — written once, rarely changes |

Add data directories or other files only if the repo genuinely needs them. Do not invent state files that have no natural home in this codebase.

### Step 3 — Write the loop prompt

Output **only** the finished loop prompt as a fenced markdown code block. Do not add commentary before or after it.

The prompt must contain exactly these sections, in this order:

#### 1. One-line purpose
A single sentence: "Your job is to [maintain/improve/build] [deliverable] for [user/context]."

#### 2. Key files
A bullet list mapping each state file to its role. Keep descriptions to one line each.

#### 3. How to start each session
Numbered steps:
1. Read the task queue first.
2. If there are unfinished items (not marked ✅), do the highest-priority one.
3. If all items are marked done or the queue is empty: re-read the main deliverable and background file, perform a fresh gap evaluation, write new prioritized goals to the queue file, then stop. Execute in the next session.

Use this gap-evaluation checklist when producing new goals:
- Missing documentation for any component visible in the directory tree.
- Stale or commented-out code referencing removed features.
- TODO/FIXME/HACK comments indicating unfinished work.
- Configuration drift (e.g., a Nix option renamed or removed upstream).
- Incomplete test coverage for recently changed modules.

#### 4. How to work
Rules for execution. Must include:
- Do one category of work per session; batch similar tasks together.
- When you change data, also update the main deliverable if the change affects it.
- When you finish a goal, mark it ✅ with a one-line summary of what was done.
- Do not re-do goals already marked ✅.
- Commit with a descriptive message. Do not ask for approval.
- Stop. You will be called again.

#### 5. Constraints
List what the agent may and may not do. Derive these from the repo's tooling and CLAUDE.md. Always include:
- Tool/environment restrictions appropriate to this repo
- "Do not ask questions." (the agent runs unattended)

#### 6. TLDR
2–3 sentence plain-English summary of the entire loop logic. Must include the "stop" instruction. Should be the last thing in the file so a human can read it first.

### Quality bar for the generated prompt

- Run through the generated prompt as a fresh agent: does every instruction make sense without prior context? If you had to guess at any step, the prompt is not ready.
- The prompt must be self-contained: a fresh agent with no prior context must be able to follow it correctly on the first run.
