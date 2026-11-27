#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Helper for the council skill (see SKILL.md in this directory).

A run lives in <cwd>/ai_council/<run id>/ and contains every artefact a later
reader needs: the prompt, each seat's notes, the rubric, evidence, scorecards
and the assembled report. `init` also adds `ai_council/` to the repository's
info/exclude so runs never show up as untracked files.

Subcommands: init, seats, brief, creator-status, check-rubric, status, packets,
check-scorecard, aggregate, selftest.
"""

import argparse
import json
import random
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_ROSTER = Path.home() / ".omp/agent/council/roster.json"
COUNCILS = {
    "creators": ("creator", "high_agent"),
    "validators": ("validator", "low_agent"),
    "judges": ("judge", "low_agent"),
}
SUBDIRS = "private creators validators rubric evidence judges scorecards context work".split()


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        die(f"missing file: {path}")
    except json.JSONDecodeError as exc:
        die(f"invalid JSON in {path}: {exc}")


def write_json(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def fill(template, **values):
    for key, value in values.items():
        template = template.replace("@" + key + "@", str(value))
    return template


def git(*args, cwd=None):
    try:
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    except FileNotFoundError:
        return None


def detect(cwd):
    """Return (mode, repo_root, base_ref, pr_allowed) for the current directory."""
    top = git("rev-parse", "--show-toplevel", cwd=str(cwd))
    if top is None or top.returncode != 0:
        return "dir", None, None, False
    root = Path(top.stdout.strip())
    head = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD", cwd=str(root))
    base_ref = head.stdout.strip() if head.returncode == 0 else ""
    if not base_ref:
        cur = git("rev-parse", "--abbrev-ref", "HEAD", cwd=str(root))
        base_ref = cur.stdout.strip() if cur.returncode == 0 else "HEAD"
    url = git("remote", "get-url", "origin", cwd=str(root))
    remote = url.stdout.strip() if url.returncode == 0 else ""
    pr_allowed = bool(re.search(r"github\.com[:/](John2143|2143-Labs)/", remote))
    return "repo", str(root), base_ref, pr_allowed


def add_exclude(root):
    common = git("rev-parse", "--git-common-dir", cwd=root)
    if common is None or common.returncode != 0:
        return
    path = Path(common.stdout.strip())
    if not path.is_absolute():
        path = Path(root) / path
    exclude = path / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    text = exclude.read_text() if exclude.exists() else ""
    if "ai_council/" in text.splitlines():
        return
    with exclude.open("a") as handle:
        if text and not text.endswith("\n"):
            handle.write("\n")
        handle.write("ai_council/\n")


def run_and_meta(args):
    run = Path(args.run).resolve()
    if not (run / "run.json").exists():
        die(f"{run} has no run.json")
    return run, load_json(run / "run.json")


def load_seats(run):
    path = run / "private" / "seats.json"
    return load_json(path) if path.exists() else {}


def save_seats(run, seats):
    write_json(run / "private" / "seats.json", seats)


def ok_tokens(seats):
    return [s["token"] for s in seats.get("creators", []) if s.get("status") == "ok"]


def creator_workspace(run, meta, token):
    if meta.get("mode") == "repo" and meta.get("repo_root"):
        root = Path(meta["repo_root"])
        return root.parent / "worktrees" / f"{root.name}-council-{token}"
    return run / "work" / token


# ---------------------------------------------------------------- subcommands


def cmd_init(args):
    roster = load_json(args.roster)
    now = datetime.now(timezone.utc)
    slug = re.sub(r"[^a-z0-9]+", "-", args.title.lower()).strip("-")[:40].strip("-") or "run"
    base = f"{now.strftime('%Y%m%d-%H%M%S')}-{slug}"
    run = Path.cwd() / "ai_council" / base
    suffix = 2
    while run.exists():
        run = Path.cwd() / "ai_council" / f"{base}-{suffix}"
        suffix += 1
    run = run.resolve()
    for name in SUBDIRS:
        (run / name).mkdir(parents=True, exist_ok=True)
    mode, repo_root, base_ref, pr_allowed = detect(Path.cwd())
    if mode == "repo":
        add_exclude(repo_root)
    meta = {
        "run_id": run.name,
        "title": args.title,
        "created_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cwd": str(Path.cwd()),
        "mode": mode,
        "repo_root": repo_root,
        "base_ref": base_ref,
        "pr_allowed": pr_allowed,
        "quorum": roster["quorum"],
        "roster": str(Path(args.roster).resolve()),
    }
    write_json(run / "run.json", meta)
    save_seats(run, {})
    print(json.dumps(meta, indent=2))


def cmd_seats(args):
    run, meta = run_and_meta(args)
    seats = load_seats(run)
    prefix, agent_key = COUNCILS[args.council]
    if seats.get(args.council):
        print(json.dumps([{k: v for k, v in s.items() if k != "member"} for s in seats[args.council]], indent=2))
        return
    roster = load_json(meta["roster"])
    members = list(roster["members"])
    random.SystemRandom().shuffle(members)
    out = []
    for index, member in enumerate(members, 1):
        seat = {
            "seat": f"{prefix}-{index}",
            "agent": member[agent_key],
            "member": member["name"],
            "status": "pending",
        }
        if args.council == "creators":
            token = "d-" + secrets.token_hex(3)
            seat.update(
                token=token,
                branch=f"council/{token}",
                workspace=str(creator_workspace(run, meta, token)),
            )
        out.append(seat)
    seats[args.council] = out
    save_seats(run, seats)
    print(json.dumps([{k: v for k, v in s.items() if k != "member"} for s in out], indent=2))


def creator_brief(run, meta, seat):
    token = seat["token"]
    workspace = seat["workspace"]
    branch = seat["branch"]
    lines = [
        "# Council brief: creator",
        "",
        f"Build the complete deliverable described in `{run}/prompt.md`, alone and end to end.",
        "",
        f"- Deliverable id: `{token}`",
        f"- Workspace: `{workspace}`",
    ]
    if meta.get("mode") == "repo":
        lines.append(f"- Create it with: `git -C {meta['repo_root']} worktree add -b {branch} {workspace} {meta['base_ref']}`")
    else:
        lines.append(f"- Create it with: `mkdir -p {workspace}`")
    lines += [
        f"- Notes: write `{run}/creators/{token}/notes.md` — what you built, how to build, run and test",
        "  it, known gaps, pitfalls you hit.",
    ]
    if meta.get("mode") == "repo":
        lines.append(f"- Commit your work on `{branch}`. Leave no uncommitted files.")
    if meta.get("pr_allowed"):
        lines += [
            f"- After your first commit: `git push -u origin {branch}`, then",
            f'  `gh pr create --draft --head {branch} --title "council {token}" --body "Council deliverable {token}."`',
            "  Keep it a draft. Push again when you finish.",
        ]
    else:
        lines.append("- Do not push and do not open a pull request.")
    lines += [
        "",
        f"You may read `{run}/prompt.md`, `{run}/context/` and your own `{run}/creators/{token}/`.",
        "Nothing else under `<run>`.".replace("<run>", str(run)),
        "",
        f"Final reply: `DONE {token}` plus at most 10 lines, or `GAVE_UP {token}: <reason>`.",
        "",
    ]
    return "\n".join(lines)


def validator_brief(run, seat):
    return fill(
        """# Council brief: validator

Read `@RUN@/prompt.md` and `@RUN@/context/`. Write the criteria you would use to judge a
finished deliverable built from that prompt. You will never see a deliverable, and you must not
look for one: do not read anything else under `@RUN@`, any council worktree, or any `council/*`
branch.

Write `@RUN@/validators/@SEAT@/criteria.md`. For each criterion give: a title; what exactly to
check; whether it is machine-checkable (then give the exact command, run from the deliverable's
root, and what output or exit code means pass) or a judgement call; and how much it should
weigh and on what scale, as suits this task. Cover the user's goals, every stated invariant,
correctness, completeness, and how the deliverable is meant to be run. Only use commands the
prompt guarantees will exist.

Final reply: `CRITERIA @SEAT@ <count>` plus at most 10 lines, or `GAVE_UP @SEAT@: <reason>`.
""",
        RUN=run,
        SEAT=seat,
    )


def judge_brief(run, seat):
    return fill(
        """# Council brief: judge

Score every deliverable in your packet against the rubric.

- Rubric: `@RUN@/rubric/rubric.json` (readable copy: `@RUN@/rubric/rubric.md`)
- Your packet: `@RUN@/judges/@SEAT@/packet.md`. Work through it in the order given.
- For each deliverable read its workspace, its notes, and its evidence directory. Evidence
  holds the captured output of the rubric's commands. For a `check` criterion, decide pass or
  fail from that output and the criterion's `pass_when`; if there is no evidence for it, score
  from reading and say so in the note.
- Run nothing: no builds, no tests, no executing deliverable code. Change nothing in any
  workspace.
- Score each criterion as an integer from 0 to its `max`, with a short note saying why.
- Judge the work, not its length. Do not try to work out who or what built a deliverable.
- Do not read `@RUN@/private/`, `@RUN@/scorecards/`, `@RUN@/validators/` or another judge's
  packet.

Write `@RUN@/scorecards/@SEAT@.json`:
`{"seat": "@SEAT@", "deliverables": {"<token>": {"summary": str, "scores": {"<criterion id>":
{"score": int, "note": str}}}}}` with every deliverable in your packet and every rubric
criterion.

Final reply: `SCORED @SEAT@` plus at most 10 lines, or `GAVE_UP @SEAT@: <reason>`.
""",
        RUN=run,
        SEAT=seat,
    )


def prepare_brief(run, token, seat):
    return fill(
        """# Council brief: prepare results

- Deliverable id: `@TOKEN@`
- Workspace (read-only for you): `@WORKSPACE@`
- Notes: `@RUN@/creators/@TOKEN@/notes.md`
- Rubric: `@RUN@/rubric/rubric.json`
- Evidence directory: `@RUN@/evidence/@TOKEN@/` (create it)
""",
        RUN=run,
        TOKEN=token,
        WORKSPACE=seat["workspace"],
    )


def cmd_brief(args):
    run, meta = run_and_meta(args)
    seats = load_seats(run)
    if args.seat == "prepare":
        if not args.token:
            die("--seat prepare needs --token")
        for seat in seats.get("creators", []):
            if seat["token"] == args.token:
                print(prepare_brief(run, args.token, seat), end="")
                return
        die(f"unknown deliverable {args.token}")
    for council in ("creators", "validators", "judges"):
        for seat in seats.get(council, []):
            if seat["seat"] != args.seat:
                continue
            if council == "creators":
                print(creator_brief(run, meta, seat), end="")
            elif council == "validators":
                print(validator_brief(run, seat["seat"]), end="")
            else:
                print(judge_brief(run, seat["seat"]), end="")
            return
    die(f"unknown seat {args.seat}")


def cmd_creator_status(args):
    run, _ = run_and_meta(args)
    seats = load_seats(run)
    for seat in seats.get("creators", []):
        if seat["seat"] != args.seat:
            continue
        seat["status"] = args.status
        seat["reason"] = args.reason
        if args.pr_url:
            seat["pr_url"] = args.pr_url
        save_seats(run, seats)
        print(json.dumps(seat, indent=2))
        return
    die(f"unknown creator seat {args.seat}")


def rubric_problems(rubric):
    if not isinstance(rubric, dict):
        return ["rubric.json is not an object"]
    criteria = rubric.get("criteria")
    if not isinstance(criteria, list) or not criteria:
        return ["rubric.json has no criteria"]
    problems = []
    seen = set()
    for index, crit in enumerate(criteria, 1):
        tag = f"criterion #{index}"
        if not isinstance(crit, dict):
            problems.append(f"{tag}: not an object")
            continue
        cid = crit.get("id")
        if not isinstance(cid, str) or not re.fullmatch(r"C\d{2,}", cid):
            problems.append(f"{tag}: id {cid!r} does not match C<digits>")
        elif cid in seen:
            problems.append(f"{cid}: duplicate id")
        else:
            seen.add(cid)
            tag = cid
        kind = crit.get("kind")
        if kind not in ("check", "judgement"):
            problems.append(f"{tag}: kind {kind!r} is not check or judgement")
        weight = crit.get("weight")
        if isinstance(weight, bool) or not isinstance(weight, (int, float)) or not weight > 0:
            problems.append(f"{tag}: weight {weight!r} is not a number > 0")
        maximum = crit.get("max")
        if isinstance(maximum, bool) or not isinstance(maximum, int) or maximum < 1:
            problems.append(f"{tag}: max {maximum!r} is not an integer >= 1")
        if kind == "check":
            for key in ("command", "pass_when"):
                if not isinstance(crit.get(key), str) or not crit[key].strip():
                    problems.append(f"{tag}: {key} is missing on a check criterion")
        else:
            for key in ("command", "pass_when"):
                if key in crit:
                    problems.append(f"{tag}: {key} must be absent on a judgement criterion")
    return problems


def cmd_check_rubric(args):
    run, _ = run_and_meta(args)
    path = run / "rubric" / "rubric.json"
    if not path.exists():
        die(f"missing file: {path}")
    problems = rubric_problems(load_json(path))
    for problem in problems:
        print(problem)
    sys.exit(1 if problems else 0)


def cmd_status(args):
    run, meta = run_and_meta(args)
    seats = load_seats(run)
    rubric_path = run / "rubric" / "rubric.json"
    problems = rubric_problems(load_json(rubric_path)) if rubric_path.exists() else ["missing rubric.json"]
    rubric = None if problems else load_json(rubric_path)
    judges = seats.get("judges", [])
    print(json.dumps({
        "quorum": meta["quorum"],
        "creators_total": len(seats.get("creators", [])),
        "creators_ok": len(ok_tokens(seats)),
        "rubric_valid": not problems,
        "check_criteria": sum(1 for c in rubric["criteria"] if c.get("kind") == "check") if rubric else 0,
        "judges_total": len(judges),
        "scorecards_valid": sum(1 for s in judges if s.get("valid")),
        "report_exists": (run / "final_report.md").exists(),
    }, indent=2))


def cmd_packets(args):
    run, _ = run_and_meta(args)
    seats = load_seats(run)
    creators = {s["token"]: s for s in seats.get("creators", []) if s.get("status") == "ok"}
    if not creators:
        die("no ok deliverables to packet")
    rng = random.SystemRandom()
    tokens = sorted(creators)
    for judge in seats.get("judges", []):
        order = tokens[:]
        rng.shuffle(order)
        lines = ["# Council packet", "", "Deliverables, in the order to score them.", ""]
        for token in order:
            lines += [
                f"## {token}",
                "",
                f"- Workspace: `{creators[token]['workspace']}`",
                f"- Notes: `{run}/creators/{token}/notes.md`",
                f"- Evidence: `{run}/evidence/{token}/`",
                "",
            ]
        path = run / "judges" / judge["seat"] / "packet.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines))
        print(f"{judge['seat']}: {path}")
    print(f"order: {' '.join(tokens)}")


def scorecard_problems(seat_name, card, rubric, tokens):
    if not isinstance(card, dict):
        return [f"{seat_name}: scorecard is not an object"]
    problems = []
    if card.get("seat") != seat_name:
        problems.append(f"{seat_name}: seat field is {card.get('seat')!r}, expected {seat_name!r}")
    deliverables = card.get("deliverables")
    if not isinstance(deliverables, dict):
        return problems + [f"{seat_name}: deliverables is not an object"]
    for token in sorted(set(deliverables) - set(tokens)):
        problems.append(f"{token}: not an ok deliverable")
    for token in sorted(set(tokens) - set(deliverables)):
        problems.append(f"{token}: missing from the scorecard")
    criteria = {c["id"]: c for c in rubric["criteria"]}
    for token, entry in sorted(deliverables.items()):
        if not isinstance(entry, dict):
            problems.append(f"{token}: entry is not an object")
            continue
        if not isinstance(entry.get("summary"), str):
            problems.append(f"{token}: summary is not a string")
        scores = entry.get("scores")
        if not isinstance(scores, dict):
            problems.append(f"{token}: scores is not an object")
            continue
        for cid in sorted(set(scores) - set(criteria)):
            problems.append(f"{token} {cid}: not a rubric criterion")
        for cid in sorted(set(criteria) - set(scores)):
            problems.append(f"{token} {cid}: missing score")
        for cid, value in sorted(scores.items()):
            if cid not in criteria:
                continue
            if not isinstance(value, dict):
                problems.append(f"{token} {cid}: score entry is not an object")
                continue
            if not isinstance(value.get("note"), str):
                problems.append(f"{token} {cid}: note is not a string")
            score = value.get("score")
            maximum = criteria[cid]["max"]
            if isinstance(score, bool) or not isinstance(score, int) or not 0 <= score <= maximum:
                problems.append(f"{token} {cid}: score {score!r} is not an integer from 0 to {maximum}")
    return problems


def cmd_check_scorecard(args):
    run, _ = run_and_meta(args)
    seats = load_seats(run)
    rubric_path = run / "rubric" / "rubric.json"
    if not rubric_path.exists():
        die(f"missing file: {rubric_path}")
    rubric = load_json(rubric_path)
    card_path = run / "scorecards" / f"{args.seat}.json"
    problems = scorecard_problems(args.seat, load_json(card_path), rubric, ok_tokens(seats))
    for seat in seats.get("judges", []):
        if seat["seat"] == args.seat:
            seat["valid"] = not problems
            save_seats(run, seats)
            break
    else:
        die(f"unknown judge seat {args.seat}")
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(1)
    print(f"{args.seat}: ok")


def median(values):
    values = sorted(values)
    count = len(values)
    if not count:
        return None
    if count % 2:
        return values[count // 2]
    return (values[count // 2 - 1] + values[count // 2]) / 2


def judge_score(rubric, scores):
    total = sum(c["weight"] for c in rubric["criteria"])
    weighted = sum(c["weight"] * scores[c["id"]]["score"] / c["max"] for c in rubric["criteria"])
    return 100.0 * weighted / total


def fmt(value):
    return "n/a" if value is None else f"{value:.1f}"


def cmd_aggregate(args):
    run, meta = run_and_meta(args)
    seats = load_seats(run)
    rubric_path = run / "rubric" / "rubric.json"
    if not rubric_path.exists():
        die(f"missing file: {rubric_path}")
    rubric = load_json(rubric_path)
    problems = rubric_problems(rubric)
    if problems:
        die("rubric invalid:\n  " + "\n  ".join(problems))
    tokens = ok_tokens(seats)
    if not tokens:
        die("no ok deliverables")
    roster = load_json(meta["roster"])
    trust = {m["name"]: m["trust"] for m in roster["members"]}
    creators = {s["token"]: s for s in seats.get("creators", []) if s.get("status") == "ok"}

    valid = []
    for seat in seats.get("judges", []):
        card_path = run / "scorecards" / f"{seat['seat']}.json"
        if not seat.get("valid") or not card_path.exists():
            continue
        card = load_json(card_path)
        if scorecard_problems(seat["seat"], card, rubric, tokens):
            continue
        valid.append((seat, card))
    if len(valid) < meta["quorum"]:
        die(f"only {len(valid)} valid scorecards, quorum is {meta['quorum']}")

    table = {}
    for token in sorted(tokens):
        rows = []
        for seat, card in valid:
            rows.append({
                "seat": seat["seat"],
                "member": seat["member"],
                "trust": trust.get(seat["member"], 1.0),
                "score": judge_score(rubric, card["deliverables"][token]["scores"]),
                "summary": card["deliverables"][token].get("summary", ""),
                "scores": {cid: v.get("score") for cid, v in card["deliverables"][token]["scores"].items()},
                "notes": {cid: v.get("note", "") for cid, v in card["deliverables"][token]["scores"].items()},
            })
        values = [r["score"] for r in rows]
        own = [r["score"] for r in rows if r["member"] != creators[token]["member"]]
        weights = sum(r["trust"] for r in rows)
        table[token] = {
            "creator_member": creators[token]["member"],
            "judges": rows,
            "median": median(values),
            "min": min(values),
            "max": max(values),
            "median_excl_own": median(own),
            "trust_weighted_mean": sum(r["trust"] * r["score"] for r in rows) / weights,
        }

    write_json(run / "scores.json", {
        "run_id": meta["run_id"],
        "quorum": meta["quorum"],
        "judges": [{"seat": s["seat"], "member": s["member"], "trust": trust.get(s["member"], 1.0)} for s, _ in valid],
        "deliverables": table,
    })
    (run / "final_report.md").write_text(report(run, meta, rubric, table, valid))
    print(f"REPORT {run / 'final_report.md'}")
    for token in sorted(table):
        row = table[token]
        print(f"{token}: median {fmt(row['median'])} min-max {fmt(row['min'])}-{fmt(row['max'])} "
              f"excl-own {fmt(row['median_excl_own'])} trust {fmt(row['trust_weighted_mean'])}")


def report(run, meta, rubric, table, valid):
    seats = load_seats(run)
    total_creators = len(seats.get("creators", []))
    ok = len(ok_tokens(seats))
    failed = total_creators - ok
    judge_seats = [s["seat"] for s, _ in valid]
    total_judges = len(seats.get("judges", []))
    lines = [
        f"# Council report: {meta['run_id']}",
        "",
        "## Seats",
        "",
        f"- Creators: {ok} ok, {failed} failed (quorum {meta['quorum']})",
        f"- Judges: {len(judge_seats)} valid of {total_judges}",
        "",
        "## Scores",
        "",
        "| Deliverable | " + " | ".join(judge_seats) + " | Median | Min–Max | Median excl. own-model judge | Trust-weighted mean |",
        "|---" * (len(judge_seats) + 5) + "|",
    ]
    for token in sorted(table):
        row = table[token]
        cells = [token] + [fmt(r["score"]) for r in row["judges"]]
        cells += [
            fmt(row["median"]),
            f"{fmt(row['min'])}–{fmt(row['max'])}",
            fmt(row["median_excl_own"]),
            fmt(row["trust_weighted_mean"]),
        ]
        lines.append("| " + " | ".join(cells) + " |")
    lines += ["", "## Criteria", ""]
    for token in sorted(table):
        lines += [f"### {token}", "", "| Criterion | Title | Weight | Max | " + " | ".join(judge_seats) + " |", "|---" * (len(judge_seats) + 4) + "|"]
        for crit in rubric["criteria"]:
            cells = [
                crit["id"],
                str(crit.get("title", "")),
                str(crit["weight"]),
                str(crit["max"]),
            ] + [str(r["scores"].get(crit["id"])) for r in table[token]["judges"]]
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")
    lines += ["## Judge notes", ""]
    for token in sorted(table):
        lines += [f"### {token}", ""]
        for row in table[token]["judges"]:
            lines.append(f"**{row['seat']}** — {row['summary']}")
            for crit in rubric["criteria"]:
                lines.append(f"- {crit['id']}: {row['notes'].get(crit['id'], '')}")
            lines.append("")
    lines += ["## Evidence", ""]
    for token in sorted(table):
        path = run / "evidence" / token / "results.json"
        lines.append(f"- {token}: {path}" if path.exists() else f"- {token}: none")
    lines += [
        "",
        "## Data",
        "",
        f"- Rubric: {run / 'rubric' / 'rubric.json'}",
        f"- Scorecards: {run / 'scorecards'}",
        f"- Scores: {run / 'scores.json'}",
        "",
    ]
    return "\n".join(lines)


def selftest():
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        roster_path = base / "roster.json"
        members = [
            {"name": "m1", "trust": 1.0, "high_agent": "h1", "low_agent": "l1"},
            {"name": "m2", "trust": 1.0, "high_agent": "h2", "low_agent": "l2"},
            {"name": "m3", "trust": 2.0, "high_agent": "h3", "low_agent": "l3"},
        ]
        write_json(roster_path, {"quorum": 2, "prepare_agent": "p", "members": members})
        run = base / "run"
        for name in SUBDIRS:
            (run / name).mkdir(parents=True, exist_ok=True)
        write_json(run / "run.json", {
            "run_id": "selftest",
            "title": "selftest",
            "mode": "dir",
            "repo_root": None,
            "base_ref": None,
            "pr_allowed": False,
            "quorum": 2,
            "roster": str(roster_path),
        })
        creators = [
            {"seat": "creator-1", "agent": "h1", "member": "m1", "status": "ok",
             "token": "d-aaaaaa", "branch": "council/d-aaaaaa", "workspace": str(run / "work" / "d-aaaaaa")},
            {"seat": "creator-2", "agent": "h2", "member": "m2", "status": "ok",
             "token": "d-bbbbbb", "branch": "council/d-bbbbbb", "workspace": str(run / "work" / "d-bbbbbb")},
        ]
        judges = [
            {"seat": "judge-1", "agent": "l1", "member": "m1", "status": "pending"},
            {"seat": "judge-2", "agent": "l2", "member": "m2", "status": "pending"},
            {"seat": "judge-3", "agent": "l3", "member": "m3", "status": "pending"},
        ]
        save_seats(run, {"creators": creators, "judges": judges, "validators": []})
        write_json(run / "rubric" / "rubric.json", {
            "title": "selftest",
            "criteria": [
                {"id": "C01", "title": "check", "description": "d", "kind": "check",
                 "weight": 2, "max": 1, "sources": ["validator-1"], "command": "true", "pass_when": "exit 0"},
                {"id": "C02", "title": "judge", "description": "d", "kind": "judgement",
                 "weight": 1, "max": 4, "sources": ["validator-2"]},
            ],
        })
        raw = {
            "d-aaaaaa": {"judge-1": (1, 4), "judge-2": (1, 2), "judge-3": (1, 3)},
            "d-bbbbbb": {"judge-1": (0, 2), "judge-2": (1, 4), "judge-3": (0, 4)},
        }
        for seat, member in (("judge-1", "m1"), ("judge-2", "m2"), ("judge-3", "m3")):
            card = {"seat": seat, "deliverables": {}}
            for token, scores in raw.items():
                first, second = scores[seat]
                card["deliverables"][token] = {
                    "summary": f"{seat} on {token}",
                    "scores": {"C01": {"score": first, "note": "n"}, "C02": {"score": second, "note": "n"}},
                }
            write_json(run / "scorecards" / f"{seat}.json", card)
        args = argparse.Namespace(run=str(run), roster=str(roster_path), seat=None)
        for seat in ("judge-1", "judge-2", "judge-3"):
            args.seat = seat
            cmd_check_scorecard(args)
        args.seat = "judge-1"
        cmd_aggregate(args)
        scores = load_json(run / "scores.json")
        expected = {
            "d-aaaaaa": (100.0, [100.0, 83.3, 91.7], 91.7, 83.3, 100.0, 87.5, 91.7),
            "d-bbbbbb": (0.0, [16.7, 100.0, 33.3], 33.3, 16.7, 100.0, 25.0, 45.8),
        }
        for token, (_, judge_scores, med, low, high, own, trust) in expected.items():
            row = scores["deliverables"][token]
            got = sorted(round(r["score"], 1) for r in row["judges"])
            assert got == sorted(judge_scores), (token, got)
            assert round(row["median"], 1) == med, (token, row["median"])
            assert round(row["min"], 1) == low and round(row["max"], 1) == high, (token, row["min"], row["max"])
            assert round(row["median_excl_own"], 1) == own, (token, row["median_excl_own"])
            assert round(row["trust_weighted_mean"], 1) == trust, (token, row["trust_weighted_mean"])
        text = (run / "final_report.md").read_text()
        for name in ("m1", "m2", "m3"):
            assert name not in text, name
        broken = load_json(run / "scorecards" / "judge-1.json")
        broken["seat"] = "judge-4"
        del broken["deliverables"]["d-aaaaaa"]["scores"]["C02"]
        write_json(run / "scorecards" / "judge-4.json", broken)
        seats = load_seats(run)
        seats["judges"].append({"seat": "judge-4", "agent": "l1", "member": "m1", "status": "pending"})
        save_seats(run, seats)
        proc = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "check-scorecard",
             "--run", str(run), "--roster", str(roster_path), "--seat", "judge-4"],
            capture_output=True, text=True,
        )
        assert proc.returncode == 1, proc.stdout + proc.stderr
        assert "C02" in proc.stdout + proc.stderr, proc.stdout + proc.stderr
    print("selftest ok")


def main():
    parser = argparse.ArgumentParser(description="Council run helper.")
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init", help="create a run directory")
    init.add_argument("--title", required=True)
    init.add_argument("--roster", default=str(DEFAULT_ROSTER))
    init.set_defaults(func=cmd_init)

    def common(name, help_text):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--run", required=True)
        p.add_argument("--roster", default=str(DEFAULT_ROSTER))
        return p

    seats = common("seats", "allocate seats for one council")
    seats.add_argument("--council", required=True, choices=sorted(COUNCILS))
    seats.set_defaults(func=cmd_seats)

    brief = common("brief", "print one seat's brief")
    brief.add_argument("--seat", required=True)
    brief.add_argument("--token", default=None)
    brief.set_defaults(func=cmd_brief)

    status = common("creator-status", "record one creator's result")
    status.add_argument("--seat", required=True)
    status.add_argument("--status", required=True, choices=["ok", "failed"])
    status.add_argument("--reason", required=True)
    status.add_argument("--pr-url", default=None)
    status.set_defaults(func=cmd_creator_status)

    common("check-rubric", "validate rubric.json").set_defaults(func=cmd_check_rubric)
    common("status", "print run progress").set_defaults(func=cmd_status)
    common("packets", "write one packet per judge").set_defaults(func=cmd_packets)

    card = common("check-scorecard", "validate one judge's scorecard")
    card.add_argument("--seat", required=True)
    card.set_defaults(func=cmd_check_scorecard)

    common("aggregate", "score the run and write the report").set_defaults(func=cmd_aggregate)

    test = sub.add_parser("selftest", help="run the built-in checks")
    test.set_defaults(func=lambda args: selftest())

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
