# Autoresearch vs. Goal: A Comparative Research Report

**Date:** 2026-05-25
**Scope:** Claude Code, Oh My Pi (OMP), Pi (pi.dev), and Hermes Agent

---

## Executive Summary

"Autoresearch" and "Goal" are two overlapping but distinct concepts in modern AI coding agents. They share a common thread—autonomous, multi-turn iteration toward an objective—but differ significantly in architecture, scope, and lineage.

- **Goal** (present in all four platforms) is a *session-scoped directive*: the agent keeps working across turns until a completion condition is met, checked by a judge/evaluator model after each turn.
- **Autoresearch** (present primarily in Claude Code as a third-party skill) is a *structured iteration loop*: modify → verify (mechanically) → keep/discard → repeat, with git rollback, results logging, and often a single measurable metric.

The critical difference: **Goal is about persistence across turns. Autoresearch is about a disciplined improvement loop within and across turns.**

---

## Part 1: The Goal Pattern

The `/goal` command exists in some form across all four platforms. It is fundamentally a **continuation mechanism**: the agent finishes a turn, a judge checks whether the objective is complete, and if not, the agent starts another turn automatically instead of returning control to the user.

### Common Architecture

All implementations follow the "Ralph loop" pattern, pioneered by Eric Traut at OpenAI in Codex CLI 0.128.0:

```
LOOP:
  1. Agent takes a turn (plans, reads files, edits, runs commands)
  2. Judge/evaluator model checks: "Is the goal satisfied?"
  3. If NO  → auto-continue to next turn (until budget exhausted)
  4. If YES → clear goal, return control to user
```

### Per-Platform Comparison

| Feature | Claude Code | Hermes Agent | Pi / OMP (pi-goal-x) |
|---------|-------------|--------------|----------------------|
| **Command** | `/goal <condition>` | `/goal <text>` | `/goals <topic>` or `/goals-set <objective>` |
| **Judge model** | Small fast model (default Haiku) | Auxiliary model (configurable, cheap recommended) | Independent auditor pi agent |
| **Default turn budget** | No fixed budget (bounded by condition) | 20 turns | No fixed budget |
| **Pause/Resume** | No — condition met or cleared | `/goal pause` / `/goal resume` | `/goal-pause` / `/goal-resume` |
| **Mid-loop criteria** | Modify condition (replaces) | `/subgoal <text>` (additive) | `/goal-tweak <change>` |
| **Persistence** | Survives `--resume`/`--continue` | Survives `/resume` via SessionDB | Disk-backed in `.pi/goals/` |
| **Completion check** | Model-based: judges conversation output | Model-based: judges assistant's last response | Auditor agent: independent agent inspects workspace, returns approved/disapproved |
| **Graceful budget exhaustion** | Not applicable | Auto-pauses with resume hint | Auto-pauses |
| **User preemption** | Esc interrupts, next message overrides | Any message preempts continuation | Esc interrupts, message overrides |

### Key Differentiators

**Claude Code `/goal`** is a wrapper around a session-scoped prompt-based Stop hook. The evaluator does not run commands or read files — it judges only what's surfaced in the conversation transcript. Conditions work best as verifiable statements: "all tests in `test/auth` pass and `npm test` exits 0."

**Hermes Agent `/goal`** is built on a central CommandDef registry with SessionDB persistence. It supports `/subgoal` for appending acceptance criteria mid-loop without breaking the running session. The judge is conservative (false positives are rare), and the system fails open (a broken judge means `continue`, not deadlock).

**Pi / OMP `pi-goal-x`** is the most architecturally complex. It has:
- **Two goal styles**: Regular (open-ended) and Sisyphus (patient ordered execution)
- **Intent-before-run flow**: User expresses intent → agent clarifies/grills → agent proposes a draft → user confirms → execution begins
- **Independent auditor agent**: A separate pi agent inspects the workspace (read, grep, find, bash — read-only) and must return `<approved/>` before the goal archives as complete
- **Schema gates**: Tool availability is lifecycle-gated (e.g., `propose_goal_draft` only during drafting, `update_goal` only when active)
- **Multiple concurrent goals**: `.pi/goals/` can hold several open goals; each session focuses on exactly one

### When to Use /goal

Use `/goal` when:
- The task requires multiple turns and you'd otherwise say "keep going" repeatedly
- The end state is verifiable from the agent's own output
- You want to set it and walk away

Examples:
- "Fix every lint error in `src/` until `ruff check` passes"
- "Port feature X from repo Y, including tests, and verify CI is green"
- "Work through the issue backlog until `gh issue list` is empty"

---

## Part 2: The Autoresearch Pattern

"Autoresearch" has a specific lineage:

1. **Karpathy's autoresearch** (March 2026, 630-line Python, 83K+ stars) — AI agents autonomously run ML experiments: edit `train.py`, train for 5 minutes, measure `val_bpb`, keep or discard with git, repeat. 100 experiments per night. The core insight: one metric, constrained scope, fast verification, automatic rollback, git as memory.

2. **Claude Autoresearch Skill** (uditgoenka, MIT license, 4.6K+ stars) — Generalizes Karpathy's principles to ANY domain. 13 commands, 9 safety hooks, 95% token reduction vs. monolithic SKILL.md. Supports Claude Code, OpenCode, and OpenAI Codex.

### The Autoresearch Loop (Claude Code Skill)

```
LOOP (N iterations or until goal is met):
  1. Review current state + git history + results log (TSV)
  2. Pick the next change based on what worked, what failed, what's untried
  3. Make ONE focused change
  4. Git commit (before verification)
  5. Run mechanical verification (tests, benchmarks, scores)
  6. If improved → keep. If worse → git revert. If crashed → fix or skip.
  7. Log the result (TSV format)
  8. Repeat
```

### 13 Commands

| Command | What it does | Default Iterations |
|---------|--------------|-------------------|
| `/autoresearch` | Core loop: modify → verify → keep/discard | 25 |
| `/autoresearch:plan` | Convert goal into validated config (metric, direction, target, scope, data source, verification command, regression tests) | one-shot |
| `/autoresearch:debug` | Hunt bugs via hypothesis iteration | 15 |
| `/autoresearch:fix` | Crush errors one-by-one to zero | 20 |
| `/autoresearch:security` | STRIDE + OWASP audit with red-team | 15 |
| `/autoresearch:ship` | Ship through 8 phases | linear |
| `/autoresearch:scenario` | Generate edge cases across 12 dimensions | 20 |
| `/autoresearch:predict` | 5 expert personas debate | one-shot |
| `/autoresearch:learn` | Scout → generate docs → validate → fix | 10 |
| `/autoresearch:reason` | Adversarial debate with blind judges | 8 |
| `/autoresearch:probe` | 8 personas interrogate requirements | 15 |
| `/autoresearch:improve` | Research ICP, discover improvements, generate PRDs | 15 |
| `/autoresearch:evals` | Analyze iteration results: trends, plateaus | one-shot |

### 8 Critical Rules

1. **Bounded by default** — each command has default iteration count; unlimited is opt-in
2. **Read before write** — understand context before modifying
3. **One change per iteration** — atomic changes; if it breaks, you know why
4. **Mechanical verification only** — no subjective "looks good"; use metrics
5. **Automatic rollback** — failed changes revert instantly via git
6. **Simplicity wins** — equal results + less code = keep the simpler version
7. **Git is memory** — experiments committed with `experiment:` prefix; agent reads `git log` + `git diff` before each iteration
8. **When stuck, think harder** — re-read, combine near-misses, try radical changes

### Safety Hooks (v2.1.1)

9 hooks fire on every session (not just autoresearch commands):
- Scout block (prevents reading node_modules/, .git/, etc.)
- Privacy block (blocks .env, SSH keys, credentials)
- Dangerous command block (blocks force-push, `rm -rf`, `git reset --hard`)
- Iteration context injection (TSV data after compaction)
- Subagent context (subagents aware of loop state)
- Dev rules reminder (code standards after compaction)
- Simplify gate (warns at 400 LOC, blocks at 800 LOC before shipping)
- Session init (project context at start)
- Stop notify (terminal notification + optional webhook on session end)

### When to Use /autoresearch

Use `/autoresearch` when:
- You have a **measurable metric** (test coverage %, bundle size, benchmark score, error count)
- The improvement surface is **wide but bounded** (specific files in scope)
- Verification is **fast and mechanical** (not subjective review)
- You want compounding gains across many small iterations

Examples:
- "Improve test coverage from 72% to 85% in `src/auth/`"
- "Reduce bundle size below 200KB without removing features"
- "Fix all ESLint violations in `src/components/`"
- "Security-hardening: run STRIDE audit on `api/` endpoint handlers"

**Do NOT use** `/autoresearch` when:
- The task has no measurable metric
- The scope is unbounded or unclear
- The work is one-shot research/analysis (use `/autoresearch:probe` or `/autoresearch:predict` instead)
- You need subjective judgment (use `/goal` with human oversight)

---

## Part 3: Hermes Agent's Research Capabilities

Hermes Agent does not have a dedicated `/autoresearch` command or skill. Its research surface is different:

### Hermes Research Tools

| Approach | Description |
|----------|-------------|
| **`hermes chat --toolsets web,terminal,skills`** | Launches a session with web search + terminal access — agent can research autonomously on-the-fly |
| **`/search <query>`** (slash command) | In-chat web search trigger — returns search results directly in the session |
| **`/goal` with research objective** | Persist a research goal across turns (e.g., "/goal Research the top 5 auth libraries for Bun, compare them in a table, and recommend one with justification") |
| **`/background <prompt>`** | Offload a research task to a separate background session while continuing other work |

Hermes' approach to research is more *compositional*: combine tools (web search, terminal, skills) with the `/goal` persistence loop to achieve autonomous research. There's no structured modify→verify→keep/discard cycle with mechanical metrics — it's a general-purpose agentic loop applied to research tasks.

---

## Part 4: Comparative Analysis

### Conceptual Map

```
                         ┌─────────────────────────────────┐
                         │     Autonomous Agent Behavior    │
                         └──────────────┬──────────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              │                         │                         │
     ┌────────▼────────┐      ┌────────▼────────┐      ┌─────────▼────────┐
     │  Single-turn     │      │  Multi-turn via  │      │  Structured       │
     │  agentic loop    │      │  /goal command   │      │  AutoResearch     │
     │  (normal mode)   │      │                  │      │  loop             │
     └─────────────────┘      └─────────────────┘      └──────────────────┘
                                      │                         │
                              ┌───────┼───────┐          ┌──────┼──────────┐
                              │       │       │          │      │          │
                        Claude Code Hermes  Pi/OMP  Claude Code Karpathy   │
                        /goal       /goal  /goals  /autoresearch  original  │
                                                      skill        (ML only)
```

### Decision Matrix: When to Use Which

| Scenario | Use | Why |
|----------|-----|-----|
| Multi-step task with clear end state | `/goal` (any platform) | Simpler, less overhead |
| Task with a numeric metric to optimize | `/autoresearch` (Claude Code) | Mechanical verification loop is designed for this |
| Security audit of a codebase | `/autoresearch:security` (Claude Code) | STRIDE + OWASP + red-team built in |
| Requirements gathering for a new feature | `/autoresearch:probe` (Claude Code) | 8 personas interrogate requirements |
| One-shot deep research with citations | `/goal` + web tools (Hermes) or `/autoresearch:predict` (Claude Code) | Research, not iteration |
| Ordered, patient execution (step 1, then 2, then 3) | Sisyphus goal (Pi/OMP) or `/goal` (Hermes with subgoals) | Preserves order, doesn't rush |
| Ship a feature through deployment | `/autoresearch:ship` (Claude Code) | 8-phase pipeline |
| "Just keep going until tests pass" | `/goal` (any) | Simple continuation is all you need |
| Want an independent audit of completion | Pi/OMP goal (auditor agent) | Separate agent verifies work |
| Overnight unsupervised work | `/autoresearch` (Claude Code) or `/goal` (any) | Both work; autoresearch adds structured rollback |
| Refactoring with strict constraints | `/autoresearch` (Claude Code) | `Scope:` directive limits file changes |
| Mid-loop criteria additions | Hermes `/subgoal` or Pi/OMP `/goal-tweak` | Add requirements without restarting |

### Architecture Comparison: Verification

| Platform | How completion is verified |
|----------|---------------------------|
| Claude Code `/goal` | Small model evaluates conversation transcript; can't run commands |
| Claude Code `/autoresearch` | Mechanical verification via metric (test output, benchmark, score — agent runs commands and reads results) |
| Hermes `/goal` | Auxiliary judge model evaluates assistant's last response; conservative (only marks done when explicitly confirmed) |
| Pi/OMP goal | Independent auditor agent inspects workspace (read-only tools), must return `<approved/>` to archive |

### Platform-Specific Strengths

| Platform | Strengths for Autonomous Work |
|----------|------------------------------|
| **Claude Code + Autoresearch Skill** | Most sophisticated autonomous loop. 13 specialized commands, mechanical verification with git rollback, safety hooks, TSV logging. Best for metric-driven optimization. |
| **Claude Code /goal** | Simplest to use. Just type `/goal <condition>`. Integrates with auto mode. Good for straightforward multi-turn tasks. |
| **Hermes /goal** | Most flexible persistence (subgoals mid-loop, resume across sessions, all messaging platforms). Largest tool surface (web, terminal, skills, MCP, 40+ providers). Fail-open design. |
| **Pi/OMP goal (pi-goal-x)** | Best audit/verification: independent auditor agent. Strong lifecycle discipline (schema gates prevent invalid state transitions). Disk-backed (transparent, inspectable). Two goal styles. |
| **Pi/OMP tool harness** | Fastest tool execution: hash-anchored edits, LSP-wired renames, native debugger, in-process ripgrep. Good for when you need maximum agent throughput. |

---

## Part 5: Lineage and Attribution

### The "Ralph Loop" Pattern

The `/goal` pattern across all platforms traces back to **Codex CLI 0.128.0** by Eric Traut (OpenAI). The core idea — keep a goal alive across turns, don't stop until it's achieved — is known as the "Ralph loop."

Hermes Agent explicitly credits this lineage in their documentation. Claude Code's implementation is independent.

### The Autoresearch Lineage

```
Karpathy's autoresearch (March 2026)
  │  630-line Python, single-GPU, ML-specific
  │  Modify train.py → train 5 min → measure val_bpb → keep/discard
  │
  └── uditgoenka/autoresearch (Claude Code skill)
        Generalized to ANY domain with a measurable metric
        13 commands, 9 safety hooks
        Supports Claude Code, OpenCode, OpenAI Codex
```

---

## Part 6: Practical Recommendations

### If you use Claude Code:

- **Day-to-day multi-turn tasks**: `/goal all tests pass and lint is clean`
- **Optimization sprints** (improving coverage, reducing size, fixing violations): Install the autoresearch skill, use `/autoresearch` with a metric
- **Security reviews**: `/autoresearch:security`
- **Pre-ship checklists**: `/autoresearch:ship`
- **Requirements analysis**: `/autoresearch:probe`

### If you use Hermes Agent:

- **Multi-turn persistence**: `/goal <objective>` (most mature `/goal` implementation among all four)
- **Research tasks**: `hermes chat --toolsets web,terminal,skills` + `/goal Research X and produce a report`
- **Adding criteria mid-run**: `/subgoal also add regression tests` (unique to Hermes)
- **Parallel research**: `/background research the best React router for our use case`

### If you use Pi / OMP:

- **Goals requiring independent verification**: Use `/goals` (auditor agent catches incomplete work)
- **Ordered, patient work**: `/sisyphus step1, step2, step3`
- **Tool-heavy autonomous work**: OMP's optimized harness (hashline edits, LSP, DAP) makes tool-calling loops faster

### If you need maximum autonomy:

- **Claude Code + Autoresearch Skill + auto mode + /goal**: The most autonomous combination. Auto mode approves tool calls within turns, /autoresearch structures the improvement loop, /goal provides cross-turn persistence.
- **Hermes + TUI + /goal + subgoals**: Best for interactive monitoring while work proceeds autonomously.

---

## Part 7: Limitations and Caveats

### /goal limitations:

- **Judge can be wrong**: False negatives (judge says continue when done) waste turn budget. False positives (judge says done when not) require re-setting the goal more precisely.
- **No independent verification**: The judge only sees conversation output, not actual filesystem state (except Pi/OMP's auditor agent).
- **Context window pressure**: Each turn adds to context. Without compaction, long goals can hit context limits.
- **Not for open-ended exploration**: If the end state isn't clearly definable, the judge can't evaluate it.

### /autoresearch limitations:

- **Requires a measurable metric**: If you can't define "better" mechanically, autoresearch can't work.
- **Third-party skill**: Not built into Claude Code — requires installation and trust of external hooks.
- **Token costs**: Each iteration costs tokens (though v2.1.0 reduced this by 95%).
- **Scope must be constrained**: Without clear scope boundaries, the agent may make unwanted changes.
- **No subjective judgment**: "Make the UI look better" doesn't work. "Reduce CLS to below 0.1" does.

---

## References

1. Karpathy's original autoresearch: https://github.com/karpathy/autoresearch
2. Claude Code autoresearch skill: https://github.com/uditgoenka/autoresearch
3. Claude Code /goal documentation: https://code.claude.com/docs/en/goal
4. Claude Code how it works: https://code.claude.com/docs/en/how-claude-code-works
5. Hermes Agent goals documentation: https://hermes-agent.nousresearch.com/docs/user-guide/features/goals
6. Hermes Agent CLI reference: https://hermes-agent.nousresearch.com/docs/reference/cli-commands
7. Pi (pi.dev): https://github.com/earendil-works/pi
8. Oh My Pi (OMP): https://github.com/can1357/oh-my-pi
9. pi-goal-x extension: https://pi.dev/packages/pi-goal-x
10. Autoresearch skill on SkillsLLM: https://skillsllm.com/skill/autoresearch
