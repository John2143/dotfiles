---
description: Conduct structured, multi-agent, multi-phase research with auditable markdown reports and APA citations
argument-hint: '"[primary research question]" [additional context, constraints, or focus areas]'
allowed-tools: Read, Write, Search, Find, Bash, Task, WebSearch, Browser
tool-hints: |
  Use web_search for search engine queries returning structured results.
  Use read with URLs to fetch and extract full page content from specific links.
  Use browser for interactive research requiring navigation, JS execution, or login flows.
  Use Task(explore) to scout unfamiliar domains before committing to sub-topics.
  Use Task(task) for parallel research on independent sub-topics — each writes its own report file.
  Use write for all report and state files — never heredocs or shell redirection.
  Research files live inside ai_research/{topic-slug}/ — never write research content outside this directory.
---

Parse `$ARGUMENTS` using these rules exactly, in order:

1. **Strip outer quotes from the raw argument string.** If `$ARGUMENTS` starts AND ends with the same quote character (`"` or `'`), strip those outer characters. After this step you have the user's literal input. Example: raw `'"What is X?" focus here'` → stripped `"What is X?" focus here`.

2. **Extract `$RESEARCH_QUESTION`.** Scan the stripped string for the first `"` (double-quote) character.
   - **Found:** Capture everything after that `"` up to the next `"`. The text between the quotes (without the quote marks) is `$RESEARCH_QUESTION`. The closing `"` marks the boundary — everything after it is `$CONTEXT`.
   - **Not found (user wrote plain text without quotes):** The entire stripped string IS `$RESEARCH_QUESTION` and `$CONTEXT` is empty. Do NOT ask for clarification just because quotes are missing — the user's intent is clear.
   - **Only ask "What is the primary research question…"** if `$ARGUMENTS` is literally empty or whitespace-only after stripping.

3. **Extract `$CONTEXT`.** All text after the closing `"` (or empty string if no closing quote). Strip leading whitespace. Pass `$CONTEXT` verbatim to every sub-agent.

4. **Derive `$TOPIC_SLUG`** by running this exact bash snippet (substitutes `$RESEARCH_QUESTION` into an env var, pipes through slugify, captures output):
   ```bash
   TOPIC_SLUG=$(printf '%s' "$RESEARCH_QUESTION" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//' | cut -c1-64)
   if [ -z "$TOPIC_SLUG" ]; then echo "EMPTY_SLUG"; else echo "$TOPIC_SLUG"; fi
   ```
   If the output is `EMPTY_SLUG`, ask the user to rephrase.

Example invocations:
- `/skill:web-researcher "find me a variety of cake recipes" focus on medium difficulty, at-home cakes. I can do decorating well. exclude fondant.`
  → `$RESEARCH_QUESTION` = `"find me a variety of cake recipes"`, `$CONTEXT` = `focus on medium difficulty, at-home cakes. I can do decorating well. exclude fondant.`
- `/skill:web-researcher "how effective are four-day work weeks in tech companies?"`

---

## One-line purpose

Your job is to conduct structured, multi-agent research: decompose a primary question into independently-researchable sub-topics, dispatch task sub-agents to produce cited markdown reports, synthesize findings into phase summaries, and repeat until the primary question is answered confidently.

## Key files

All files live under `ai_research/{topic-slug}/` relative to the repo root. None of these files exist on the first run — create the directory and initialize them during SETUP.

| File | Role |
|------|------|
| `research_plan.md` | Primary question, full `$CONTEXT`, and sub-topic decomposition with perspective assignments |
| `research_state.md` | Current phase number, phase status enum (`setting_up`, `dispatching`, `synthesizing`, `finalizing`, `done`), and per-sub-topic status tracked as explicit slug lists (`Pending:`, `In progress:`, `Done:`) |
| `reports/{subtopic-slug}_report.md` | Individual sub-agent deliverables — one file per sub-topic, following the required report structure |
| `phase_{N}_summary.md` | Synthesis after each completed phase: cross-cutting findings, relation to primary question, consolidated bibliography, and the decision for the next step |
| `final_report.md` | (Created only when research is complete) Final answer to the primary question, synthesizing all phase summaries |

## How to start each session

**This is a multi-invocation skill.** You run exactly one category of work per session, then you terminate. The user invokes you again for the next step. This is by design — it keeps your context window clean and your decisions auditable.

### Hard session-boundary rule

1. Read `ai_research/{topic-slug}/research_state.md`. If it does not exist, this is a fresh research project — follow **SETUP**.
2. Read the `phase_status` field. Determine which single category to execute:

   | `phase_status` | Category to run |
   |---|---|
   | _(no file)_ | SETUP |
   | `setting_up` | SETUP (resume — plan was partially written) |
   | `dispatching` | DISPATCH |
   | `synthesizing` | SYNTHESIZE |
   | `done` | Report: research is complete. Point to the report, then call `exit_loop_mode('Research complete — final report at ai_research/{topic-slug}/final_report.md')`. If `exit_loop_mode` is unavailable (interactive session), the text report alone is sufficient — stop immediately. Do NOT keep re-invoking. |

3. Execute that one category. When its final step says **STOP**, stop immediately.

### What "STOP" means

After completing a category, your only remaining actions are:
- Confirm the state file was written.
- Report which category you completed and what the next `phase_status` is.

You **must not** read the next category's instructions. You **must not** evaluate whether the next step could also be done. You **must not** read past the STOP line in the SKILL.md file.

### Anti-pattern: "the user is waiting"

The following pattern is a bug and must never happen:
> "The user is in a conversation with me right now. They probably expect me to complete the research in this session. Let me proceed to DISPATCH."

That reasoning is always wrong. The skill is designed for multiple invocations. The user knows each invocation does one step. Chaining categories defeats context-window isolation and produces sloppy synthesis. Delivering one clean atomic step per invocation is how you serve the user best.

### Anti-pattern: "I'll just check the next section"

Do not scroll past the STOP line to see what the next category requires. If you do, you have already violated the boundary. The state file is the only link between sessions — not your memory of the next step.
### Anti-pattern: "Let me archive the old project so it resets"

When `phase_status` is `done` and the same question is re-invoked:
> "The user keeps re-invoking. They must want fresh news. Let me `mv` the old directory somewhere else so the slug becomes free and SETUP fires again."

Never do this. The state file is the authority. If it says `done`, you call `exit_loop_mode` and stop. You do not rename directories, suggest the user rephrase their question, or otherwise try to "fix" the fact that the project is finished. Archiving completed research without explicit user confirmation violates the "may not delete research files" constraint and destroys the audit trail. If the user wants fresh research, they will give you a new question.
## How to work

### Category: SETUP

**Purpose**: Create the research directory, formalize the question, decompose into sub-topics, write the plan and initial state.

1. Create the directory `ai_research/{topic-slug}/` and the `reports/` subdirectory:
   - Use `mkdir -p ai_research/{topic-slug}/reports/`.
   - Before creating, check whether the directory already exists (`ls ai_research/{topic-slug}/`). If it exists and contains prior research, do not overwrite it — treat it as an existing project. Read its `research_state.md` and follow the normal session start flow instead. If it exists but contains only empty directories or no state files, proceed with fresh SETUP.
2. Formalize `$RESEARCH_QUESTION` into a crisp, answerable primary research question. If the user's phrasing is ambiguous, vague, or unanswerable as stated:
   - **If invoked in loop mode**: formalize to the best interpretation, note the assumption explicitly in `research_plan.md` under `## Context`, and proceed. Do not stall.
   - **If not in loop mode**: **stop and ask the user for clarification.** Do not proceed with a poorly-defined question.
   Write the refined question into `research_plan.md`.
3. Record the full `$CONTEXT` in `research_plan.md` under a `## Context` heading so every sub-agent receives it.
4. Decompose the primary question into 3–10 sub-topics. Each sub-topic must be:
   - Independently researchable (one sub-agent can complete it without waiting for another sub-topic's results).
   - Specific enough that a sub-agent knows exactly what to investigate.
   - Directly relevant to answering the primary question.
5. For each sub-topic, decide whether assigning a **perspective trait** would surface useful angles that might otherwise be missed. Assign a perspective if and only if it would add to overall research accuracy, provide a global perspective, or reveal viewpoints that may be obscured by popular consensus or censorship. Examples: political leanings for policy questions, national/regional viewpoints for geopolitical topics, school-of-thought labels for academic debates. If a sub-topic is purely factual (e.g., "what is the boiling point of tungsten"), skip perspective assignment. Record each sub-topic with its perspective (or "none") in `research_plan.md`.
6. Write `research_plan.md` with this structure:

```markdown
# Research Plan: {topic-slug}

## Primary Question
{refined question}

## Context
{full $CONTEXT from the user — verbatim}

## Sub-Topics

### Sub-Topic 1: {title}
- **Slug**: {subtopic-slug}
- **Perspective**: {assigned perspective, or "none"}
- **Report path**: reports/{subtopic-slug}_report.md

### Sub-Topic 2: {title}
...
```

7. Write `research_state.md`:

```markdown
# Research State

- **Phase**: 1
- **Phase status**: dispatching
- **Primary question answered**: no
- **Total sub-topics**: {N}
- **Pending**: {comma-separated list of all sub-topic slugs}
- **In progress**:
- **Done**:
- **Failed**:
- **Retries**: {}

8. **STOP.** You have completed SETUP. The state file now reads `phase_status: dispatching`. Do not read the DISPATCH section. Do not dispatch sub-agents. The user will invoke the skill again for DISPATCH.

### Category: DISPATCH

**Purpose**: Send sub-agents to research pending sub-topics in parallel. Do not collect results in this session.

1. Read `research_plan.md` and `research_state.md`. Identify pending sub-topics from the `Pending:` list in `research_state.md`.
2. If no sub-topics are pending and `Done:` is not empty: update `phase_status` to `synthesizing` in `research_state.md`. **STOP.** Do not proceed to synthesis in this session.
3. Select up to 5 pending sub-topics to dispatch this session (or up to 10 if the user explicitly authorized more in `$CONTEXT`). If more than 5 remain pending, dispatch 5 now; the rest will be dispatched in future sessions.
4. Rewrite `research_state.md` atomically: move each selected sub-topic's slug from the `Pending:` list to the `In progress:` list, increment its retry count in `Retries:` (initialize to 1 if not present), and set `phase_status` to `synthesizing` (sub-agents will run independently; the next session collects results). The file is small — rewrite the whole thing in one `write` call rather than editing individual lines.
5. Dispatch all selected sub-agents simultaneously using `Task(task)`. Each sub-agent receives a self-contained research brief. Construct the brief as follows (substitute `{placeholders}` with values from `research_plan.md`):

```
# Research Brief: {sub-topic title}

## Primary Research Question
{the refined primary question from research_plan.md}

## Your Sub-Topic
{the sub-topic description from research_plan.md}

## Your Perspective
{the assigned perspective, or "none — report objectively"}

## User Context
{the full $CONTEXT from research_plan.md — verbatim}

## Output File
Write your complete report to `ai_research/{topic-slug}/reports/{subtopic-slug}_report.md`.

## Required Report Structure
Your report file must contain these sections, in order:

### 1. Summary
A clear summary of your research findings (2–4 paragraphs).

### 2. Relation to Primary Question
1–2 sentences explaining how your sub-topic findings bear on the primary research question.

### 3. Source Evaluation
For each source you relied on, state:
- The source URL and title.
- A credibility assessment: primary vs. secondary, official data vs. opinion, verified author vs. anonymous, recency.
- Why you weighted this source the way you did.

### 4. Conclusions
Actionable conclusions drawn from your research. If your perspective assignment revealed non-obvious angles, call them out explicitly.

### 5. Bibliography
All sources in APA format. Each entry must include the full URL.

## Source Rules
- Prefer primary sources over secondary sources.
- Prefer official data and peer-reviewed work over opinion pieces.
- Prefer verified authors and established outlets over anonymous or unverifiable sources.
- If a source has clear bias, acknowledge it rather than discarding it — biased sources can still contain useful data.
- If you cannot verify a key claim, state that explicitly rather than presenting it as fact.
- Do not cite sources you did not actually read or access.

## Constraints
- You may write only to the specified output file path.
- You may use web_search, read (with URLs), and browser for research.
- You may not write outside ai_research/{topic-slug}/.
- You may not ask questions — work with the brief you have.
- Your report must be self-contained so a reviewer can audit it without your context window.
```

6. **STOP.** You have completed DISPATCH. Sub-agents are running asynchronously. Do not wait for results. Do not read the SYNTHESIZE section. The user will invoke the skill again for SYNTHESIZE.

### Category: SYNTHESIZE

**Purpose**: Collect completed sub-agent reports, assess whether the primary question is answered, write a phase summary, and decide the next step.

1. Read `research_plan.md` and `research_state.md`.
2. Check every sub-topic listed under `In progress:` in `research_state.md`. Read its expected output file at `reports/{subtopic-slug}_report.md`:
   - If the file exists and contains a complete report (all 5 required sections present): move the sub-topic's slug from `In progress:` to `Done:` in `research_state.md`. Rewrite the entire state file atomically.
   - If the file does not exist or is incomplete (missing sections): leave the slug under `In progress:`.
3. If any slugs remain under `Pending:` or `In progress:` in `research_state.md`:
   - If sub-agents for `In progress:` items appear to have failed (no output file after a reasonable attempt): check `Retries:` for each. If retries < 3, move back to `Pending:`, set `phase_status` to `dispatching`, and **STOP.** If retries >= 3, move to `Failed:`, note in `research_state.md` that the sub-topic was abandoned after 3 attempts, set `phase_status` to `dispatching` (for remaining Pending items), and **STOP.**
   - Otherwise, set `phase_status` to `dispatching` and **STOP.** Do not proceed to synthesis in this session.
4. If both `Pending:` and `In progress:` are empty in `research_state.md` (all sub-topics are in `Done:`):
   - Read every completed report in full.
   - Write `phase_{N}_summary.md` (where N is the current phase number) with this structure:

```markdown
# Phase {N} Summary

## Primary Question
{the primary research question}

## Sub-Topic Findings

### {Sub-Topic 1 Title}
**Perspective**: {assigned perspective, or "none"}
**Researcher conclusion**: {distill the sub-agent's conclusions into 1 paragraph}
**Relation to primary question**: {1–2 sentences — how this bears on the primary question}

### {Sub-Topic 2 Title}
...

## Cross-Cutting Insights
{Identify patterns, agreements, and contradictions across sub-topic reports. If two reports with different perspectives reached different conclusions on the same facts, highlight the disagreement and assess which conclusion is better-supported.}

## Consolidated Bibliography
{All sources from all sub-topic reports, in APA format, deduplicated. Each entry includes the full URL.}

## Decision
{One of: SUFFICIENT / MORE_NEEDED / STUCK — see below for criteria}
```

5. **Decision criteria** — determine which of three outcomes applies and record it in both the phase summary and `research_state.md`:

   **SUFFICIENT**: The primary research question can now be answered fully and confidently based on the evidence collected across all phases. No major gaps remain. No contradictory findings remain unresolved.
   → Set `phase_status` to `finalizing` in `research_state.md`. **STOP.** Do not proceed to FINALIZE in this session. Next session: FINALIZE.

   **MORE_NEEDED**: The research so far is useful but does not fully answer the primary question. New sub-questions emerged during this phase that need investigation.
   → Append the new sub-questions to `research_plan.md` as sub-topics for the next phase (do not edit existing sub-topics — only append). Add the new sub-topic slugs to the `Pending:` list in `research_state.md`, update `Total sub-topics`, increment the phase number, and set `phase_status` to `dispatching`. Rewrite `research_state.md` atomically. **STOP.** Do not dispatch new sub-topics in this session. Next session: DISPATCH new sub-topics.

   **STUCK**: The primary question cannot be answered without user input. This may be because the question is fundamentally unanswerable with available sources, contradictory evidence cannot be resolved, or the scope needs narrowing.
   → Set `phase_status` to `stuck` in `research_state.md`. **STOP.**
   - **If invoked in loop mode**: write `stuck_summary.md` (summary, blocker, 2–3 concrete options) and call `exit_loop_mode('Research stuck — see ai_research/{topic-slug}/stuck_summary.md')`.
   - **If not in loop mode**: present the user with the same summary and options inline. Do not proceed until the user responds in a future session.

6. **STOP.** You have completed SYNTHESIZE. The state file reflects the decision (finalizing, dispatching, or stuck). Do not proceed to the next step regardless of the decision. The user will invoke the skill again.

### Category: FINALIZE

**Purpose**: Produce the final answer and report to the user.

1. Read all `phase_*_summary.md` files.
2. Optionally, dispatch a fresh `Task(task)` sub-agent to write `final_report.md` from all phase summaries. This provides an unbiased synthesis with a clean context window. Use this brief:

```
# Final Report Brief

## Primary Research Question
{the primary question from research_plan.md}

## Source Material
Read every file matching `ai_research/{topic-slug}/phase_*_summary.md`. These are the phase summaries from completed research.

## Output File
Write `ai_research/{topic-slug}/final_report.md`.

## Required Structure

### 1. Answer
A direct, concise answer to the primary research question (1–3 paragraphs). Do not hedge unless the evidence genuinely warrants it.

### 2. Evidence Summary
For each key finding that supports the answer, state:
- What the finding is.
- Which phase and sub-topic it came from (with a markdown link to the source report, e.g., `[Sub-Topic Title](reports/{slug}_report.md)`).

### 3. Confidence Assessment
- **High confidence**: multiple independent sources agree, primary sources back the claim, no credible contradictory evidence.
- **Medium confidence**: sources agree but are limited in number or authority, or minor contradictions exist.
- **Low confidence**: significant gaps, reliance on secondary sources, or unresolved contradictions.

### 4. Limitations and Open Questions
What this research did not cover, what assumptions were made, and what questions remain open.

### 5. Bibliography
Consolidated bibliography from all phase summaries.

## Constraints
- You may read all files under ai_research/{topic-slug}/.
- You may write only to the specified output file path.
- You may not write outside ai_research/{topic-slug}/.
- You may not ask questions — synthesize from the provided material.
```

3. If the answer is short enough to fit comfortably in a chat response (under ~500 words), you may write `final_report.md` yourself instead of dispatching a sub-agent. Either way, the file must exist when FINALIZE completes.
4. Mark `phase_status` as `done` in `research_state.md`.
5. Report to the user: state that research is complete, provide the answer if short, and point to `ai_research/{topic-slug}/final_report.md` for the full report. Then call `exit_loop_mode('Research complete — final report at ai_research/{topic-slug}/final_report.md')`. If the tool is unavailable, the text report is sufficient — stop immediately.

6. **STOP.** You have completed FINALIZE. Research is done. `phase_status` is `done`.

## Constraints

- You may create files inside `ai_research/{topic-slug}/`.
- You may dispatch sub-agents for parallel research.
- You may search the web using `web_search`, fetch full page content with `read` (URL mode), and use `browser` for interactive web research.
- You may write phase summaries and final reports.
- You may proceed autonomously through research phases when the question is clear and the evidence is sufficient.
- You may not write any file outside `ai_research/{topic-slug}/`.
- You may not delete research files without explicit user confirmation.
- You may not proceed with an ambiguous or unanswerable primary research question — see SETUP step 2 for loop-mode vs interactive handling.
- You may not assign equal weight to all sources regardless of credibility — evaluate and state source quality in every report.
- You may not run more than 10 sub-agents per phase without explicit user approval in `$CONTEXT`.
- You may not ask the user questions during active research phases — only at SETUP (if the question is unclear) or when genuinely stuck at SYNTHESIZE.
- **You may not chain multiple categories in one session.** Execute exactly one category, update state, and stop. After writing a STOP line, your session is over — do not scroll further in this SKILL.md. Do not read the next category's instructions. Do not evaluate whether "it would be faster" to do the next step now. The state file is the only handoff mechanism between sessions.
- When `phase_status` is `done`, always call `exit_loop_mode('<summary>')`. Do not evaluate whether you are in loop mode — just call it. If the tool fails (not in loop mode), your text report is sufficient. Under no circumstances should a `done` project be re-entered — the state file is the authority: if it says `done`, you exit.

## TLDR

Your job is to run exactly one atomic step of a structured research process per session and then stop. After you hit a STOP line, your session is over — confirm the state file was written and report which category you completed. Do not scroll further in this SKILL.md. The state machine is: SETUP → DISPATCH ⇄ SYNTHESIZE → FINALIZE → DONE. Read `research_state.md` first on every invocation to know which category to run — never continue from your own memory of the previous step.
