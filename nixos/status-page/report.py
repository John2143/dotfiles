"""Report pite's LAN checks to statusd, and backfill its history from Mimir.

Live mode (default) reads pite's own Prometheus, which is the only place the
`blackbox-tcp` results for the house services exist, and posts one batch to
statusd every 30 s. `--backfill DAYS` replays Mimir's retained history through
the same mapping so the droplet starts with ~29 days instead of zero.

Two vantage points, one page: the droplet probes the websites from outside,
pite reports what it can see from inside. A component that pite stops reporting
goes `unknown` on the page after 120 s rather than keeping its last state, which
is why a missing LAN instance is a non-zero exit here.

Standard library only, deliberately: this runs from systemd on a Pi with no
virtualenv, and the two HTTP APIs it talks to are trivial.

Note on history: pite's blackbox follows redirects, and john2143.com and
2143.me both 301 to github.com. Backfilled samples for those two before the
droplet existed therefore partly measured GitHub's uptime, not ours. The
droplet's own probes do not follow redirects, so only backfilled hours carry
this caveat.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

URL = "https://status-origin.2143.me"
PROM = "http://localhost:9090"
MIMIR = "http://192.168.6.23:8080/prometheus"

# Instances of job="blackbox-tcp": house services, probed from inside.
# 192.168.5.9:9100 is pite's own node_exporter and is intentionally unmapped.
LAN = {
    "192.168.6.6:443": "gateway",
    "192.168.6.13:25": "mail",
    "192.168.6.16:30033": "teamspeak",
    "192.168.6.19:1883": "mqtt",
    "192.168.6.20:7233": "temporal",
    "192.168.6.23:8080": "metrics",
    "192.168.6.24:3100": "logs",
}

# Instances of job="blackbox-http". status-origin.2143.me/healthz is also probed
# by pite — for alerting on the droplet — but is not a page component.
WEB = {
    "https://john2143.com": "john2143-com",
    "https://files.john2143.com": "files-john2143-com",
    "https://2143.me": "2143-me",
    "https://2143.me/user": "2143-me-user",
    "https://i.2143.me": "i-2143-me",
}

INSTANT_TIMEOUT = 10
RANGE_TIMEOUT = 30
STEP = 30
CHUNK_HOURS = 6
ATTEMPTS = 3


def floor_hour(ts):
    return int(ts) // 3600 * 3600


def ceil_hour(ts):
    ts = int(ts)
    return -(-ts // 3600) * 3600


def _get(url, timeout):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.load(r)


def query_instant(base, expr, timeout=INSTANT_TIMEOUT):
    """{instance: float} for an instant vector; NaN and stale series are skipped."""
    url = f"{base}/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    payload = _get(url, timeout)
    if payload.get("status") != "success":
        raise RuntimeError(f"query failed: {payload.get('error')}")
    out = {}
    for series in payload["data"]["result"]:
        try:
            value = float(series["value"][1])
        except (KeyError, IndexError, ValueError):
            continue
        if value != value:  # NaN
            continue
        out[series["metric"].get("instance", "")] = value
    return out


def query_range(base, expr, start, end, timeout=RANGE_TIMEOUT, attempts=ATTEMPTS):
    """{instance: [(ts, value)]} over [start, end], retried whole."""
    url = f"{base}/api/v1/query_range?" + urllib.parse.urlencode(
        {"query": expr, "start": start, "end": end, "step": STEP}
    )
    last = None
    for attempt in range(attempts):
        try:
            payload = _get(url, timeout)
            if payload.get("status") != "success":
                raise RuntimeError(payload.get("error") or "query failed")
            out = {}
            for series in payload["data"]["result"]:
                points = []
                for ts, value in series.get("values", []):
                    try:
                        v = float(value)
                    except ValueError:
                        continue
                    if v != v:
                        continue
                    points.append((float(ts), v))
                if points:
                    out[series["metric"].get("instance", "")] = points
            return out
        except Exception as e:  # noqa: BLE001 - one retry loop for every transport error
            last = e
            if attempt + 1 < attempts:
                time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"range query failed after {attempts} attempts: {last}")


def build_checks(success, duration):
    """Live payload checks, in LAN order. Missing instances are simply absent."""
    checks = []
    for instance, component in LAN.items():
        ok = success.get(instance) == 1
        latency = None
        if ok and instance in duration:
            latency = round(duration[instance] * 1000, 1)
        if instance in success:
            checks.append({"id": component, "ok": ok, "latency_ms": latency})
    return checks


def hourly_rows(points, mapping):
    """Per component and whole hour: sample count, successes, mean latency over successes."""
    buckets = {}
    for instance, series in points.items():
        component = mapping.get(instance)
        if component is None:
            continue
        for ts, ok in series:
            slot = buckets.setdefault((component, floor_hour(ts)), [0, 0.0])
            slot[0] += 1
            slot[1] += 1.0 if ok == 1 else 0.0
    return buckets


def attach_latency(buckets, duration_points, mapping, success_points):
    """Mean probe duration over the successful samples of each hour."""
    sums = {}
    for instance, series in duration_points.items():
        component = mapping.get(instance)
        if component is None:
            continue
        ok_times = {ts for ts, ok in success_points.get(instance, []) if ok == 1}
        for ts, dur in series:
            if ts not in ok_times:
                continue
            key = (component, floor_hour(ts))
            total, count = sums.get(key, (0.0, 0))
            sums[key] = (total + dur, count + 1)
    rows = []
    for (component, hour), (samples, oks) in sorted(buckets.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        latency = None
        if (component, hour) in sums:
            total, count = sums[(component, hour)]
            latency = round(total / count * 1000, 1)
        rows.append(
            {
                "id": component,
                "hour": hour,
                "samples": samples,
                "ok": int(oks),
                "latency_ms": latency,
            }
        )
    return rows


def outage_runs(points, mapping, until):
    """Runs of at least two consecutive failures, ending at the first pass.

    A run still failing at `until` is dropped: the walk has no evidence it ever
    ended, and statusd opens outages from live reports.
    """
    runs = []
    for instance, series in points.items():
        component = mapping.get(instance)
        if component is None:
            continue
        start = None
        previous = None
        failing = 0
        for ts, ok in sorted(series):
            if ok == 1:
                if start is not None and failing >= 2:
                    runs.append({"id": component, "start": int(start), "end": int(ts)})
                start, failing = None, 0
            else:
                if start is None:
                    start = ts
                failing += 1
            previous = ts
        if start is not None and failing >= 2 and previous is not None and previous < until:
            continue  # open at the end of the walk: no known end, so no row
    return sorted(runs, key=lambda r: (r["start"], r["id"]))


def post(path, token, payload, timeout=30):
    body = json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(
        f"{URL}{path}",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as r:
        return json.load(r)


def read_token(path):
    with open(path, encoding="utf-8") as f:
        token = f.read().strip()
    if not token:
        raise SystemExit(f"report: token file {path} is empty")
    return token


def run_live(token):
    success = query_instant(PROM, 'probe_success{job="blackbox-tcp"}')
    duration = query_instant(PROM, 'probe_duration_seconds{job="blackbox-tcp"}')
    checks = build_checks(success, duration)
    missing = sorted(set(LAN.values()) - {c["id"] for c in checks})
    result = post("/v1/report", token, {"v": 1, "ts": int(time.time()), "checks": checks})
    down = [c["id"] for c in checks if not c["ok"]]
    print(
        f"report: {result.get('accepted', 0)} accepted, {result.get('ignored', 0)} ignored, "
        f"{len(down)} failing{': ' + ','.join(down) if down else ''}"
        f"{f'; missing {len(missing)}: ' + ','.join(missing) if missing else ''}"
    )
    if missing:
        # The page shows these as unknown after 120 s, which is the truth.
        sys.exit(1)


def run_backfill(token, days):
    now = int(time.time())
    start = ceil_hour(now - days * 86400)
    end = floor_hour(now)
    skipped = []
    points = {"success": {}, "duration": {}}
    chunk = start
    while chunk < end:
        chunk_end = min(chunk + CHUNK_HOURS * 3600, end)
        for expr, key in (
            ('probe_success{job=~"blackbox-(tcp|http)"}', "success"),
            ('probe_duration_seconds{job=~"blackbox-(tcp|http)"}', "duration"),
        ):
            # query_range includes its end point, so stop one step short of the
            # next chunk to keep every sample inside exactly one chunk.
            try:
                result = query_range(MIMIR, expr, chunk, chunk_end - STEP)
            except RuntimeError as e:
                print(f"backfill: chunk {chunk} ({key}) skipped: {e}", file=sys.stderr)
                skipped.append(chunk)
                continue
            for instance, series in result.items():
                points[key].setdefault(instance, []).extend(series)
        chunk = chunk_end

    mapping = {**LAN, **WEB}
    buckets = hourly_rows(points["success"], mapping)
    rows = attach_latency(buckets, points["duration"], mapping, points["success"])
    runs = outage_runs(points["success"], mapping, until=end)
    result = post("/v1/backfill", token, {"v": 1, "hours": rows, "outages": runs})
    print(
        f"backfill: {result.get('accepted', 0)} accepted, {result.get('rejected', 0)} rejected, "
        f"{len(rows)} hour rows, {len(runs)} outages, {days} days requested"
        + (f", {len(set(skipped))} chunks skipped" if skipped else "")
    )
    if skipped:
        # Rerunning is safe: statusd ignores duplicate hour rows and outages.
        sys.exit(1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--backfill", type=int, metavar="DAYS")
    args = parser.parse_args(argv)
    token = read_token(args.token_file)
    try:
        if args.backfill is not None:
            run_backfill(token, args.backfill)
        else:
            run_live(token)
    except (urllib.error.URLError, OSError, RuntimeError, ValueError) as e:
        print(f"report: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
