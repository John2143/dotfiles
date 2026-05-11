---
description: Improve an existing prompt file, optimize a short inline prompt for AI use, or generate a loop prompt for the current repo
argument-hint: '[path/to/prompt.md | loop | "your prompt text"]'
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
- If the normalized argument starts with `@`, strip the `@` — this prefix means the file was passed automatically by the harness context, not by the user. Treat the rest of the argument normally.
- If the normalized argument is exactly `loop`, follow **Mode: Loop Prompt Generation** below.
- If the normalized argument is a quoted string (starts and ends with `"`), strip the quotes and treat the content as inline prompt text — follow **Mode: Inline Prompt Optimization** below.
- If the normalized argument is a path to an existing regular file, follow **Mode: Prompt Improvement** below.
- If the normalized argument matches no existing file and is not a quoted string: treat it as inline prompt text — follow **Mode: Inline Prompt Optimization** below.
- If no argument was given, ask the user: "Do you want to (1) improve an existing prompt file, (2) optimize a short prompt inline, or (3) generate a loop prompt for this repo?"

---

## Mode: Prompt Improvement

You are an expert prompt engineer. Read the file at the given path and produce a prioritized list of concrete improvement suggestions.

If the file exceeds ~200 lines: focus analysis on the frontmatter and opening instructions, and note the truncation.

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

## Mode: Inline Prompt Optimization

You are an expert prompt engineer. The user has given you a short prompt as raw text. Your job is to produce an improved version: spell-checked, grammatically clean, and optimized for consumption by another AI.

### What to fix

1. **Spelling and grammar** — Fix typos, punctuation errors, and awkward phrasing. Do not change the user's voice or intent.
2. **Goal clarity** — If the prompt's objective is buried or implied, surface it explicitly in the first sentence.
3. **Specificity** — Replace vague pronouns and qualifiers ("do it well", "make it good") with concrete criteria.
4. **Structure** — If the prompt is a wall of text, add paragraph breaks. If it describes a multi-step task, add numbered steps.
5. **Remove hedging** — Strip "maybe", "if you want", "you could try", "it might be helpful to" unless the uncertainty is intentional.
6. **Add missing constraints** — If the prompt implies an output format or audience but doesn't state it, add a brief note (e.g., "Output plain text, not markdown").

### What NOT to do

- Do not add features the user didn't ask for.
- Do not rewrite the prompt into a different task.
- Do not produce analysis or commentary — output only the improved prompt.
- Do not run the full 8-dimension analysis framework from Prompt Improvement mode (that's for file-based review).

### Output format

Output the improved prompt as a fenced markdown code block. If the text is short enough, also display it inline. After the improved prompt, add a brief bullet list of what you changed and why (max 5 items).

### Example

**Input:**
> wrtie a prompt that tells the AI to make a good readme for my rust project

**Output:**
```
Write a README.md for a Rust project. Include: project description, installation instructions (cargo-based), usage examples, and contribution guidelines. Output valid markdown.
```
- Fixed "wrtie" → "Write", added structure (section list), specified output format (markdown), and removed the meta-framing ("a prompt that tells the AI to") so the text works as a direct prompt.

---

## Mode: Loop Prompt Generation

This mode generates a loop prompt: a self-contained instruction document designed for the `/loop` harness, which calls the same prompt repeatedly with no arguments. Each invocation does a small, atomic unit of work and then stops. The agent maintains state between runs via files it writes to the repo.

**This is distinct from a multi-session skill** (user-invoked, user controls timing). A loop prompt must include a gap-evaluation step at the start of every session to decide whether work exists. If no work exists, the agent uses harness-provided tool calls to terminate:

- **`sleep(duration, reason)`** — Work is expected to reappear later (e.g., waiting for a human PR merge, waiting for a timer). The harness pauses and re-invokes after `duration`.
- **`exit_loop_mode(reason)`** — All work is definitively complete. The harness stops invoking permanently.

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
3. If all items are marked done or the queue is empty: re-read the main deliverable and background file, perform a fresh gap evaluation.
   - If the gap evaluation finds new work: write new prioritized goals to the queue file, then stop. The next session will execute them.
   - If the gap evaluation finds nothing and no external events could create work: call **`exit_loop_mode("<summary of what was accomplished>")`**.
   - If the gap evaluation finds nothing but external events could create work (e.g., PR awaiting human merge, timer-based triggers): call **`sleep(<duration>, "<reason>")`**.

Use this gap-evaluation checklist when producing new goals:
- Missing documentation for any component visible in the directory tree.
- Stale or commented-out code referencing removed features.
- TODO/FIXME/HACK comments indicating unfinished work.
- Configuration drift (e.g., a Nix option renamed or removed upstream).
- Incomplete test coverage for recently changed modules.
- Open PRs awaiting human review (if the agent's role includes PR monitoring).
#### 4. How to work
Rules for execution. Must include:
- Do one category of work per session; batch similar tasks together.
- When you change data, also update the main deliverable if the change affects it.
- When you finish a goal, mark it ✅ with a one-line summary of what was done.
- Do not re-do goals already marked ✅.
- Commit with a descriptive message. Do not ask for approval.
- If no work exists, call the appropriate harness tool:
  - **`sleep(duration, reason)`** when work is expected to reappear.
  - **`exit_loop_mode(reason)`** when all work is definitively done.

#### 5. Constraints
List what the agent may and may not do. Derive these from the repo's tooling and CLAUDE.md. Always include:
- Tool/environment restrictions appropriate to this repo
- "Do not ask questions." (the agent runs unattended)
- "Prefer `sleep()` when uncertain whether work is truly done. A sleeping agent can be re-invoked; an exited agent cannot."
- "When calling `sleep()`, always provide a duration and reason. Example: `sleep(5min, "waiting for PR #9 to be merged by human")`."
#### 6. TLDR
2–3 sentence plain-English summary of the entire loop logic. Must include: read queue → work or evaluate → sleep or exit. Should be the last thing in the file so a human can read it first.

### Quality bar for the generated prompt

- Run through the generated prompt as a fresh agent: does every instruction make sense without prior context? If you had to guess at any step, the prompt is not ready.
- The prompt must be self-contained: a fresh agent with no prior context must be able to follow it correctly on the first run.
