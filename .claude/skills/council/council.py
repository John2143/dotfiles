#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Validation and scoring for the council skill (see SKILL.md in this directory).

A run directory <cwd>/ai_council/<run id>/ holds:
  prompt.md                   the brief every council member receives
  private/seats.json          written by the orchestrator; later given its ok_tokens
  rubric/rubric.json          copied from the validator manager's payload
  scorecards/<seat>.json      copied from each judge's payload
  evidence/<token>/<id>.log   captured output of the rubric's check commands
  final_report.md, scores.json  written by `report`

Seats, briefs and packets live in the agents' task calls, not here. This script
only validates and scores. Subcommands: check-rubric, check-scorecard, report,
selftest.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_ROSTER = Path.home() / ".omp/agent/council/roster.json"


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


def run_dir(args):
    run = Path(args.run).resolve()
    if not run.is_dir():
        die(f"{run} is not a directory")
    return run


def seats(run):
    path = run / "private" / "seats.json"
    data = load_json(path)

    def objects(key, fields):
        items = data.get(key)
        return isinstance(items, list) and all(
            isinstance(item, dict) and all(isinstance(item.get(f), str) for f in fields) for item in items)

    if not (isinstance(data, dict)
            and isinstance(data.get("quorum"), int) and not isinstance(data.get("quorum"), bool)
            and isinstance(data.get("ok_tokens"), list)
            and all(isinstance(t, str) for t in data["ok_tokens"])
            and objects("creators", ("token", "member"))
            and objects("judges", ("seat", "member"))):
        die(f"{path} is missing or malformed")
    return data


def ok_tokens(seats):
    return seats["ok_tokens"]


# ---------------------------------------------------------------- subcommands


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
    run = run_dir(args)
    path = Path(args.file).resolve() if args.file else run / "rubric" / "rubric.json"
    if not path.exists():
        die(f"missing file: {path}")
    problems = rubric_problems(load_json(path))
    for problem in problems:
        print(problem)
    sys.exit(1 if problems else 0)


def scorecard_problems(seat_name, card, rubric, tokens):
    if not isinstance(card, dict):
        return [f"{seat_name}: scorecard is not an object"]
    problems = []
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
    run = run_dir(args)
    data = seats(run)
    if args.seat not in {s["seat"] for s in data["judges"]}:
        die(f"unknown judge seat {args.seat}")
    rubric_path = run / "rubric" / "rubric.json"
    if not rubric_path.exists():
        die(f"missing file: {rubric_path}")
    rubric = load_json(rubric_path)
    card_path = run / "scorecards" / f"{args.seat}.json"
    problems = scorecard_problems(args.seat, load_json(card_path), rubric, ok_tokens(data))
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


def cmd_report(args):
    run = run_dir(args)
    data = seats(run)
    quorum = data["quorum"]
    rubric_path = run / "rubric" / "rubric.json"
    if not rubric_path.exists():
        die(f"missing file: {rubric_path}")
    rubric = load_json(rubric_path)
    problems = rubric_problems(rubric)
    if problems:
        die("rubric invalid:\n  " + "\n  ".join(problems))
    tokens = ok_tokens(data)
    if not tokens:
        die("no ok deliverables")
    roster = load_json(args.roster)
    trust = {m["name"]: m["trust"] for m in roster["members"]}
    creators = {s["token"]: s for s in data["creators"] if s["token"] in tokens}
    missing = sorted(set(tokens) - set(creators))
    if missing:
        die(f"ok_tokens not among the creators: {' '.join(missing)}")

    valid = []
    for seat in data["judges"]:
        card_path = run / "scorecards" / f"{seat['seat']}.json"
        if not card_path.exists():
            continue
        card = load_json(card_path)
        if scorecard_problems(seat["seat"], card, rubric, tokens):
            continue
        valid.append((seat, card))
    if len(valid) < quorum:
        die(f"only {len(valid)} valid scorecards, quorum is {quorum}")

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
        "run_id": run.name,
        "quorum": quorum,
        "judges": [{"seat": s["seat"], "member": s["member"], "trust": trust.get(s["member"], 1.0)} for s, _ in valid],
        "deliverables": table,
    })
    (run / "final_report.md").write_text(report(run, data, rubric, table, valid))
    print(f"REPORT {run / 'final_report.md'}")
    for token in sorted(table):
        row = table[token]
        print(f"{token}: median {fmt(row['median'])} min-max {fmt(row['min'])}-{fmt(row['max'])} "
              f"excl-own {fmt(row['median_excl_own'])} trust {fmt(row['trust_weighted_mean'])}")


def report(run, data, rubric, table, valid):
    total_creators = len(data["creators"])
    ok = len(ok_tokens(data))
    failed = total_creators - ok
    judge_seats = [s["seat"] for s, _ in valid]
    total_judges = len(data["judges"])
    lines = [
        f"# Council report: {run.name}",
        "",
        "## Seats",
        "",
        f"- Creators: {ok} ok, {failed} failed (quorum {data['quorum']})",
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
        path = run / "evidence" / token
        logs = sorted(path.glob("*.log")) if path.is_dir() else []
        lines.append(f"- {token}: {path} ({len(logs)} logs)" if logs else f"- {token}: none")
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
        members = [{"name": n, "trust": t} for n, t in (("m1", 1.0), ("m2", 1.0), ("m3", 2.0))]
        write_json(roster_path, {"quorum": 2, "prepare_agent": "p", "members": members})
        run = base / "20260101-000000-selftest"
        write_json(run / "private" / "seats.json", {
            "quorum": 2,
            "mode": "dir",
            "ok_tokens": ["d-aaaaaa", "d-bbbbbb"],
            "creators": [
                {"seat": "creator-1", "member": "m1", "token": "d-aaaaaa"},
                {"seat": "creator-2", "member": "m2", "token": "d-bbbbbb"},
            ],
            "validators": [],
            "judges": [
                {"seat": "judge-1", "member": "m1"},
                {"seat": "judge-2", "member": "m2"},
                {"seat": "judge-3", "member": "m3"},
            ],
        })
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
        for seat in ("judge-1", "judge-2", "judge-3"):
            card = {"deliverables": {}}
            for token, scores in raw.items():
                first, second = scores[seat]
                card["deliverables"][token] = {
                    "summary": f"{seat} on {token}",
                    "scores": {"C01": {"score": first, "note": "n"}, "C02": {"score": second, "note": "n"}},
                }
            write_json(run / "scorecards" / f"{seat}.json", card)
        args = argparse.Namespace(run=str(run), roster=str(roster_path), seat=None, file=None)
        problems = rubric_problems(load_json(run / "rubric" / "rubric.json"))
        assert not problems, problems
        for seat in ("judge-1", "judge-2", "judge-3"):
            args.seat = seat
            cmd_check_scorecard(args)
        cmd_report(args)
        scores = load_json(run / "scores.json")
        expected = {
            "d-aaaaaa": ([100.0, 83.3, 91.7], 91.7, 83.3, 100.0, 87.5, 91.7),
            "d-bbbbbb": ([16.7, 100.0, 33.3], 33.3, 16.7, 100.0, 25.0, 45.8),
        }
        for token, (judge_scores, med, low, high, own, trust) in expected.items():
            row = scores["deliverables"][token]
            got = sorted(round(r["score"], 1) for r in row["judges"])
            assert got == sorted(judge_scores), (token, got)
            assert round(row["median"], 1) == med, (token, row["median"])
            assert round(row["min"], 1) == low and round(row["max"], 1) == high, (token, row["min"], row["max"])
            assert round(row["median_excl_own"], 1) == own, (token, row["median_excl_own"])
            assert round(row["trust_weighted_mean"], 1) == trust, (token, row["trust_weighted_mean"])
        text = (run / "final_report.md").read_text()
        assert text.startswith(f"# Council report: {run.name}"), text.splitlines()[0]
        for name in ("m1", "m2", "m3"):
            assert name not in text, name
        broken = load_json(run / "scorecards" / "judge-1.json")
        del broken["deliverables"]["d-aaaaaa"]["scores"]["C02"]
        write_json(run / "scorecards" / "judge-1.json", broken)
        proc = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "check-scorecard",
             "--run", str(run), "--seat", "judge-1"],
            capture_output=True, text=True,
        )
        assert proc.returncode == 1, proc.stdout + proc.stderr
        assert "C02" in proc.stdout + proc.stderr, proc.stdout + proc.stderr
    print("selftest ok")


def main():
    parser = argparse.ArgumentParser(description="Council validation and scoring.")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(name, help_text):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--run", required=True)
        return p

    rubric = common("check-rubric", "validate a rubric (default RUN/rubric/rubric.json)")
    rubric.add_argument("--file", default=None)
    rubric.set_defaults(func=cmd_check_rubric)

    card = common("check-scorecard", "validate RUN/scorecards/<seat>.json")
    card.add_argument("--seat", required=True)
    card.set_defaults(func=cmd_check_scorecard)

    rep = common("report", "score the run and write the report")
    rep.add_argument("--roster", default=str(DEFAULT_ROSTER))
    rep.set_defaults(func=cmd_report)

    test = sub.add_parser("selftest", help="run the built-in checks")
    test.set_defaults(func=lambda args: selftest())

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
