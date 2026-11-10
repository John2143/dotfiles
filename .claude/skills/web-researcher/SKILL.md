---
description: Conduct structured, multi-agent, multi-phase research with auditable markdown reports and APA citations
argument-hint: '"[primary research question]" [additional context, constraints, or focus areas]'
allowed-tools: Read, Write, Search, Find, Bash, Task, WebSearch, Browser, exit_loop_mode
tool-hints: |
  Use web_search for search engine queries returning structured results.
  Use read with URLs to fetch and extract full page content from specific links.
  Use browser for interactive research requiring navigation, JS execution, or login flows.
  Use Task(scout) to recon unfamiliar domains before committing to sub-topics.
  Use Task(web-researcher) for parallel research on independent sub-topics — each writes its own report file.
  Use write for all report and state files — never heredocs or shell redirection.
  Research files live inside ai_research/{topic-slug}/ — never write research content outside this directory.
  This skill may be invoked in loop mode (via /loop harness). When running in loop mode, call `exit_loop_mode(summary)` after producing results to terminate the harness. When not in loop mode, just stop normally.
---

## Usage

**Invocation:** `/skill:web-researcher "[primary research question]" [additional context]`

The primary research question must be quoted. Everything after the closing quote is treated as additional context (constraints, focus areas, preferences) and passed verbatim to every research sub-agent.

**Examples:**
- `/skill:web-researcher "how effective are four-day work weeks in tech companies?"` — Research with no additional context
- `/skill:web-researcher "find me a variety of cake recipes" focus on medium difficulty, at-home cakes. I can do decorating well. exclude fondant.` — Research with context shaping the scope and direction

Parse `$ARGUMENTS` by running the deterministic parser script — do NOT manually reason about quote positions:

```bash
eval "$("$HOME/.omp/agent/skills/web-researcher/parse-args.py" << 'ARGSEOF'
<paste the raw $ARGUMENTS string here exactly as you received it>
ARGSEOF
)"
```

This sets `$RESEARCH_QUESTION`, `$CONTEXT`, `$TOPIC_SLUG`, and `$EMPTY` as shell variables.

- If `$EMPTY` is `true`: the arguments were empty or whitespace-only. Ask "What is the primary research question…?"
- Otherwise: `$RESEARCH_QUESTION` is the question text, `$CONTEXT` is everything after the closing quote (may be empty).
- Pass `$CONTEXT` verbatim to every sub-agent.

Example invocations:
- `/skill:web-researcher "find me a variety of cake recipes" focus on medium difficulty, at-home cakes. I can do decorating well. exclude fondant.`
  → `$RESEARCH_QUESTION` = `find me a variety of cake recipes`, `$CONTEXT` = `focus on medium difficulty, at-home cakes. I can do decorating well. exclude fondant.`
- `/skill:web-researcher "how effective are four-day work weeks in tech companies?"`
  → `$RESEARCH_QUESTION` = `how effective are four-day work weeks in tech companies?`, `$CONTEXT` is empty

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

**This is a multi-invocation skill.** Run exactly one category per session, then stop; the user invokes it again for the next step. That is what keeps context clean and each decision auditable, so chaining categories — "the user is waiting", "I'll just read the next section", "re-invocation keeps firing so I'll archive the project to reset it" — is always a bug. `research_state.md` is the only handoff between sessions. A `done` project stays `done`: never rename, move, or re-enter it to make SETUP fire again.

The `web-research-orchestrator` agent is exempt: it runs all four categories back to back in one session, using the state files as its audit trail. The one-category rule applies to interactive invocation.

1. Read `ai_research/{topic-slug}/research_state.md`. No file means a fresh project — run **SETUP**.
2. Otherwise run exactly one category for the current `phase_status`:

   | `phase_status` | Category to run |
   |---|---|
   | `setting_up` | SETUP (resume — plan was partially written) |
   | `dispatching` | DISPATCH |
   | `synthesizing` | SYNTHESIZE |
   | `done` | Report: research is complete. Point to `final_report.md`, call `exit_loop_mode('Research complete — final report at ai_research/{topic-slug}/final_report.md')` if the tool exists, and stop. |

3. When the category's final step says **STOP**, stop: confirm the state file was written, report the category and the new `phase_status`, and do not read past the STOP line.

## How to work

### Category: SETUP

**Purpose**: Create the research directory, formalize the question, decompose into sub-topics, write the plan and initial state.

1. Create the directory `ai_research/{topic-slug}/` and the `reports/` subdirectory:
   - Use `mkdir -p ai_research/{topic-slug}/reports/`.
   - Check first (`ls ai_research/{topic-slug}/`). Prior research there means treat it as an existing project and follow the session-start flow; empty directories with no state files mean fresh SETUP.
2. Formalize `$RESEARCH_QUESTION` into a crisp, answerable primary research question. If the user's phrasing is ambiguous, vague, or unanswerable as stated:
   - **If invoked in loop mode**: formalize to the best interpretation, note the assumption explicitly in `research_plan.md` under `## Context`, and proceed. Do not stall.
   - **If not in loop mode**: **stop and ask the user for clarification.** Do not proceed with a poorly-defined question.
   Write the refined question into `research_plan.md`.
3. Record the full `$CONTEXT` in `research_plan.md` under a `## Context` heading so every sub-agent receives it.
4. Decompose the primary question into 3–10 sub-topics. Each sub-topic must be:
   - Independently researchable (one sub-agent can complete it without waiting for another sub-topic's results).
   - Specific enough that a sub-agent knows exactly what to investigate.
   - Directly relevant to answering the primary question.
5. For each sub-topic, decide whether a **perspective trait** would surface an angle that consensus or censorship hides — political leanings for policy, national viewpoint for geopolitics, school-of-thought for academic debates. Assign one only when it adds accuracy; skip purely factual sub-topics. Record the perspective (or "none") in `research_plan.md`.
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
```

8. **STOP.** State written (`phase_status: dispatching`). The user invokes you again for DISPATCH.

### Category: DISPATCH

**Purpose**: Send sub-agents to research pending sub-topics in parallel. Do not collect results in this session.

1. Read `research_plan.md` and `research_state.md`. Identify pending sub-topics from the `Pending:` list in `research_state.md`.
2. If no sub-topics are pending and `Done:` is not empty: update `phase_status` to `synthesizing` in `research_state.md`. **STOP.** Do not proceed to synthesis in this session.
3. Select up to 5 pending sub-topics to dispatch this session (or up to 10 if the user explicitly authorized more in `$CONTEXT`). If more than 5 remain pending, dispatch 5 now; the rest will be dispatched in future sessions.
4. Rewrite `research_state.md` in one `write` call: move each selected slug from `Pending:` to `In progress:`, increment its `Retries:` count, and set `phase_status: synthesizing`.
5. Dispatch all selected sub-agents simultaneously using `Task(web-researcher)`. Each sub-agent receives a self-contained research brief. Construct the brief as follows (substitute `{placeholders}` with values from `research_plan.md`):

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
For each source your conclusions actually rest on — at most 12, and fewer when the question is narrow — state: the URL and title, a credibility assessment (primary vs. secondary, official data vs. opinion, verified author vs. anonymous, recency), and why you weighted it that way. A source you read but did not rely on belongs in the bibliography only.

### 4. Conclusions
Actionable conclusions drawn from your research. If your perspective assignment revealed non-obvious angles, call them out explicitly.

### 5. Bibliography
All sources in APA format. Each entry must include the full URL.

## Source Rules
- Prefer primary, official, and peer-reviewed material over secondary summaries and opinion; prefer verified authors and established outlets.
- Acknowledge a source's bias rather than discarding it — biased sources can still carry useful data.
- An unverifiable key claim is labelled as such, never presented as fact.
- Never cite a source you did not actually read.

## Constraints
- You may write only to the specified output file path.
- You may use web_search, read (with URLs), and bash for research.
- You may not write outside ai_research/{topic-slug}/.
- You may not ask questions — work with the brief you have.
- Your report must be self-contained so a reviewer can audit it without your context window.
```

6. **STOP.** State written (`phase_status: synthesizing`). Sub-agents run asynchronously; the next session collects them.

### Category: SYNTHESIZE

**Purpose**: Collect completed sub-agent reports, assess whether the primary question is answered, write a phase summary, and decide the next step.

1. Read `research_plan.md` and `research_state.md`.
2. Check every sub-topic listed under `In progress:` in `research_state.md`. Read its expected output file at `reports/{subtopic-slug}_report.md`:
   - If the file exists and contains a complete report (all 5 required sections present): move the sub-topic's slug from `In progress:` to `Done:` in `research_state.md`. Rewrite the entire state file atomically.
   - If the file does not exist or is incomplete (missing sections): leave the slug under `In progress:`.
3. If anything remains under `Pending:` or `In progress:`: a sub-agent with no output file after a reasonable attempt gets up to 3 tries — under 3, move it back to `Pending:`; at 3, move it to `Failed:` and note the abandonment in `research_state.md`. Set `phase_status: dispatching`. **STOP.**
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

5. **Decision criteria** — record one of three outcomes in both the phase summary and `research_state.md`:

   **SUFFICIENT** — the primary question can now be answered fully; no major gaps or unresolved contradictions. → `phase_status: finalizing`. **STOP.**

   **MORE_NEEDED** — useful but incomplete, and new sub-questions emerged. → Append them to `research_plan.md` as new sub-topics (append only, never edit existing ones), add their slugs to `Pending:`, update `Total sub-topics`, bump the phase number, set `phase_status: dispatching`. **STOP.**

   **STUCK** — the question cannot be answered without the user: unanswerable from the available sources, irreconcilable evidence, or scope that needs narrowing. → Set `phase_status: stuck`. **STOP.** In loop mode, write `stuck_summary.md` (summary, blocker, 2–3 concrete options) and call `exit_loop_mode('Research stuck — see ai_research/{topic-slug}/stuck_summary.md')`; otherwise present the same summary inline and wait for the next session.

6. **STOP.** State written, whatever the decision.

### Category: FINALIZE

**Purpose**: Produce the final answer and report to the user.

1. Read all `phase_*_summary.md` files.
2. Optionally, dispatch a fresh `Task(web-researcher)` sub-agent to write `final_report.md` from all phase summaries. This provides an unbiased synthesis with a clean context window. Use this brief:

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

6. **STOP.** Research is done; `phase_status` is `done`.

## Constraints

- Write only inside `ai_research/{topic-slug}/`. Never delete research files without explicit user confirmation.
- At most 10 sub-agents per phase without explicit user approval in `$CONTEXT`.
- Every report states source quality; never weight all sources equally.
- Consult the user only at SETUP (unclear question) or when STUCK — never mid-phase.
- When `phase_status` is `done`, call `exit_loop_mode('<summary>')` without checking whether loop mode is on; if the tool fails, the text report is enough. A `done` project is never re-entered.

**State machine:** SETUP → DISPATCH ⇄ SYNTHESIZE → FINALIZE → DONE. `research_state.md` decides the step — never your memory of the previous session.
