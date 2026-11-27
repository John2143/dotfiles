---
description: "Run a multi-model council: four models each build the deliverable, four write validation criteria, four score the anonymised results. Returns a scored report to decide from."
argument-hint: "<what to build, with goals and constraints>"
allowed-tools: read, write, bash, task, ask
tool-hints: |
  You are the orchestrator: you write the prompt, spawn three manager agents, and present the result. You never build, write criteria, or score.
  Spawn council_manager_creator and council_manager_validator in ONE task call. Spawn council_manager_judgement only after both have returned.
  Managers and members return structured payloads; read a payload that was cut from a result with `cat agent://<id>`, using the id the result reports, never one built from the task name.
  Never put a model name in a brief, and never show ai_council/<run>/private/ to a subagent.
---

## Usage

**Invocation:** `/skill:council <what to build, with goals and constraints>`

One run costs about 16 agent sessions (4 creators, 4 validators, 4 judges, 3 managers, 1 prepare)
plus their subtasks. Use it for work where comparing independent attempts is worth that.

If `$ARGUMENTS` is empty, ask "What should the council build?" and stop.

## Step 0 — Preflight

```bash
COUNCIL="$HOME/.omp/agent/skills/council/council.py"
ROSTER="$HOME/.omp/agent/council/roster.json"
test -r "$ROSTER" || echo "MISSING_ROSTER"
jq -e '(.members | length) >= .quorum' "$ROSTER" >/dev/null 2>&1 || echo "BAD_ROSTER"
```

On `MISSING_ROSTER`, say the council agents are not installed on this host and stop. On
`BAD_ROSTER`, stop: the roster is unreadable or lists fewer members than `quorum`. If the current
directory is inside a git repository, run `git fetch origin` before Step 1.

## Step 1 — Start the run and write the prompt

```bash
RUN="$(pwd)/ai_council/$(date -u +%Y%m%d-%H%M%S)-SLUG"
[ -e "$RUN" ] && RUN="$RUN-$$"
mkdir -p "$RUN/rubric" "$RUN/scorecards" "$RUN/evidence" "$RUN/private"
REPO=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$REPO" ]; then
  MODE=repo
  BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD)
  URL=$(git remote get-url origin 2>/dev/null || true)
  case "$URL" in
    *github.com[:/]John2143/*|*github.com[:/]2143-Labs/*) PR=true ;;
    *) PR=false ;;
  esac
  EX=$(git rev-parse --git-common-dir)/info/exclude
  grep -qxF 'ai_council/' "$EX" 2>/dev/null || echo 'ai_council/' >> "$EX"
else
  MODE=dir; BASE=null; PR=false
fi
TOKS=$(for i in 1 2 3 4; do printf '"d-%s",' "$(od -An -tx1 -N3 /dev/urandom | tr -d ' \n')"; done | sed 's/,$//')
jq --argjson toks "[$TOKS]" --arg mode "$MODE" --arg repo "$REPO" --arg base "$BASE" \
   --argjson pr "$PR" --arg run "$RUN" '
   .members as $m | ($m | length) as $n
   | {quorum: .quorum, mode: $mode,
      repo_root: (if $mode == "repo" then $repo else null end),
      base_ref: (if $mode == "repo" then $base else null end), pr_allowed: $pr,
      creators: [range(0; $n) as $i | {seat: "creator-\($i+1)", agent: $m[$i].creator_agent,
        member: $m[$i].name, token: $toks[$i]}],
      validators: [range(0; $n) as $i | {seat: "validator-\($i+1)",
        agent: $m[$i].validator_agent, member: $m[$i].name}],
      judges: [range(0; $n) as $i | {seat: "judge-\($i+1)",
        agent: $m[$i].judge_agent, member: $m[$i].name}]}
   | .creators |= map(. + {branch: ("council/" + .token),
       workspace: (if $mode == "repo"
         then ($repo | sub("/[^/]+$"; "")) + "/worktrees/" + ($repo | sub(".*/"; "")) + "-council-" + .token
         else $run + "/work/" + .token end)})' "$ROSTER" > "$RUN/private/seats.json"
```

Replace `SLUG` with the request title lowercased, non-alphanumerics to `-`, collapsed and
trimmed to 40 characters. The last command prints nothing; confirm with
`jq -c '[(.creators|length), (.judges|length), .mode]' "$RUN/private/seats.json"` before continuing.
`RUN` is already absolute; every later block that uses it starts by setting
`RUN` and `COUNCIL` to the same values.

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

One `task` call with two items:

- `agent: council_manager_creator`, `name: council-creators`
- `agent: council_manager_validator`, `name: council-validators`

Both carry `Run directory: <RUN>`; the validator manager also carries `Script: <COUNCIL>`.

End your turn; both results arrive on their own. Then copy the rubric out of the validator
manager's payload and validate it. `VID` is the id that manager's result reports — the `id`
attribute of its `<task-result>`, or the id in its `Agent: agent://<id>` line. It is
`council-validators` on a session's first run and `council-validators-2`, `-3`, … on later runs
in the same session, so never type the name in its place:

```bash
RUN="<the absolute path from Step 1>"
COUNCIL="$HOME/.omp/agent/skills/council/council.py"
VID="<the id from the validator manager's result>"
cat "agent://$VID" > "$RUN/rubric/rubric.json"
"$COUNCIL" check-rubric --run "$RUN"
```

Stop and report, without judging, when the copy or the check fails, or when the creator manager
reported fewer ok seats than `quorum`. Say which stage failed and what exists on disk.

## Step 4 — Judgement

Record the ok tokens the creator manager reported (its `OK ...` line; use `OK` alone when it
listed none), then spawn the judgement manager:

```bash
RUN="<the absolute path from Step 1>"
jq --arg ok "<the OK line without the leading OK>" \
   '.ok_tokens = ($ok | split(" ") | map(select(length > 0)))' \
   "$RUN/private/seats.json" > "$RUN/private/seats.tmp" \
  && mv "$RUN/private/seats.tmp" "$RUN/private/seats.json"
```

One `task` call: `agent: council_manager_judgement`, `name: council-judgement`, with
`Run directory: <RUN>`, `Script: <COUNCIL>` and `OK tokens: <the same token list>`.

If the creator manager's reply has no `OK` line, use the tokens it marked `ok`; if that is also
unreadable, stop and report the reply — never guess the set, and never pass an empty list.

When it returns, run `"$COUNCIL" report --run "$RUN"` only if `test -s "$RUN/final_report.md"`
fails — the manager runs it itself; do not overwrite a report it produced. If the report is
still missing, report the manager's reply and stop.

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
- Never retry a creator or validator seat. A model that fails has quit; the run continues above
  quorum. The one exception is the judgement manager's single same-model retry of a judge whose
  scorecard fails `check-scorecard`.
- Never read `RUN/private/` before Step 5.
- Everything a later reader needs is under `RUN`: prompt, rubric, evidence, scorecards, scores,
  report.
