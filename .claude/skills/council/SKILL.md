---
description: "Run a multi-model council: four models each build the deliverable, four write validation criteria, four score the anonymised results. Returns a scored report to decide from."
argument-hint: "<what to build, with goals and constraints>"
allowed-tools: read, write, bash, task, ask
tool-hints: |
  You are the orchestrator: you write the prompt, spawn three manager agents, and present the result. You never build, write criteria, or score.
  Spawn council_manager_creator and council_manager_validator in ONE task call. Spawn council_manager_judgement only after both have returned.
  Managers return pointers. The data is in files under ai_council/<run>/.
  Never put a model name in a brief, and never show ai_council/<run>/private/ to a subagent.
---

## Usage

**Invocation:** `/skill:council <what to build, with goals and constraints>`

One run costs about 15 agent sessions (4 creators, 4 validators, 4 judges, 3 managers) plus
their subtasks. Use it for work where comparing independent attempts is worth that.

If `$ARGUMENTS` is empty, ask "What should the council build?" and stop.

## Step 0 — Preflight

```bash
COUNCIL="$HOME/.omp/agent/skills/council/council.py"
test -r "$HOME/.omp/agent/council/roster.json" || echo "MISSING_ROSTER"
```

On `MISSING_ROSTER`, say the council agents are not installed on this host and stop. If the
current directory is inside a git repository, run `git fetch origin` before Step 1.

## Step 1 — Start the run and write the prompt

```bash
"$COUNCIL" init --title "<3-6 word title for the request>"
```

It prints `run.json`. Call its directory RUN (absolute path). `mode` is `repo` (creators work in
git worktrees on `council/<id>` branches) or `dir` (creators work in `RUN/work/<id>/`).

Write `RUN/prompt.md`. Every council member receives exactly this file, with no chance to ask
questions, so it must stand alone:

- The goal, and every goal and invariant the user gave, in the user's own words where possible.
- One clearly defined deliverable: which files, where in the workspace, and what "done" means.
- The exact commands that must work on the finished deliverable (build, test, run). The
  validators write checks from these without seeing any deliverable, so name them.
- Context: absolute paths to files members should read. Copy large material into
  `RUN/context/` and link it from the prompt.
- What is out of scope.
- Nothing about the council, other members, models, judging, or the rubric.

Check the draft against the eight review dimensions in `skill://prompt-engineer` (file mode)
and fix what fails.

If the request leaves a choice only the user can make, ask it now, in one `ask`, before
anything is spawned.

## Step 2 — Confirm

One `ask`: show the path to `RUN/prompt.md`, the mode, whether draft pull requests will be
opened (`pr_allowed`), and the session count. Options: start (default), edit the prompt first,
cancel.

## Step 3 — Creators and validators

One `task` call with two items, same brief for both:

- `agent: council_manager_creator`, `name: council-creators`
- `agent: council_manager_validator`, `name: council-validators`

```
# Council run
Run directory: <RUN>
Script: <COUNCIL>
```

End your turn; both results arrive on their own. Then run `"$COUNCIL" status --run "$RUN"`.

Stop and report, without judging, when `creators_ok` is below `quorum` or `rubric_valid` is
false. Say which stage failed and what exists on disk.

## Step 4 — Judgement

One `task` call: `agent: council_manager_judgement`, `name: council-judgement`, same brief.
When it returns, run `status` again. If `report_exists` is false, report the manager's reply
and stop.

## Step 5 — Present and decide

Read `RUN/final_report.md`, `RUN/scores.json` and `RUN/private/seats.json`. Only now may model
names be used. Show the user:

- The score table with each deliverable's model, workspace, and draft PR.
- Failed or dropped seats, with reasons.
- Where the judges disagreed most (largest min–max spread) and what their notes say.
- Your own check of the leading deliverable against `RUN/evidence/` and the rubric. Agreement
  between judges is not proof; verify before you recommend.

If one deliverable leads on the median, on the median without its own-model judge, and on the
trust-weighted mean, and its checks pass, recommend it. If none is acceptable, say so and offer
a rerun with a revised prompt. Otherwise lay out the trade-off and let the user choose.

After the user decides, offer with one `ask` to: mark the winner's PR ready, close the other
draft PRs, and remove the other worktrees. Do none of these without that answer.

## Constraints

- Never build, write criteria, or score yourself, and never edit a deliverable.
- Never retry a failed seat. A model that fails has quit; the run continues above quorum.
- Never read `RUN/private/` before Step 5.
- Everything a later reader needs is under `RUN`: prompt, criteria, rubric, evidence,
  scorecards, scores, report.
