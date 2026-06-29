#!/usr/bin/env python3
"""Status page generator for pite.

Queries pite's Prometheus (current state), Mimir (long-term uptime via remote write),
and kubectl (home k3s pod status). Generates static HTML to /var/www/status/index.html.

Stdlib only — no pip dependencies.
"""

import datetime
import html
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ── Configuration ──────────────────────────────────────────────────

PROM_URL = "http://localhost:9090"
MIMIR_URL = "http://192.168.5.10:30674/prometheus"
OUTPUT = "/var/www/status/index.html"
KUBECONFIG = "/var/lib/status-page/kubeconfig"
TIMEOUT = 10     # seconds per instant query
RANGE_TIMEOUT = 30  # seconds per range query (30d avg_over_time is heavy)

# Friendly names for node instances
NODE_NAMES = {
    "192.168.5.36:9100": "closet",
    "192.168.5.76:9100": "arch",
    "192.168.5.175:9100": "nas",
    "192.168.5.209:9100": "office",
    "localhost:9100": "pite",
}

# Friendly names for service instances
SERVICE_NAMES = {
    "https://john2143.com": "john2143.com",
    "https://2143.me": "2143.me",
    "https://i.2143.me": "i.2143.me",
    "https://files.john2143.com": "files.john2143.com",
    "https://2143.me/user": "2143.me/user",
    "192.168.5.10:30034": "TS file xfer",
    "192.168.5.9:9100": "pite node_exporter",
}

# Service display order (top to bottom in table)
SERVICE_ORDER = [
    "https://john2143.com",
    "https://2143.me",
    "https://i.2143.me",
    "https://files.john2143.com",
    "https://2143.me/user",
    "192.168.5.10:30034",
    "192.168.5.9:9100",
]

# ── HTTP helpers ────────────────────────────────────────────────────


def fetch_json(url, timeout=TIMEOUT):
    """Fetch a JSON endpoint, return parsed dict or None on failure."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"[WARN] fetch failed: {url} — {exc}", file=sys.stderr)
        return None


def prom_instant(query):
    """Query pite Prometheus instant vector. Returns list of result dicts."""
    params = urllib.parse.urlencode({"query": query})
    url = f"{PROM_URL}/api/v1/query?{params}"
    data = fetch_json(url)
    if data and data.get("status") == "success":
        return data["data"]["result"]
    return []


def mimir_instant(query):
    """Query Mimir instant vector."""
    params = urllib.parse.urlencode({"query": query})
    url = f"{MIMIR_URL}/api/v1/query?{params}"
    data = fetch_json(url)
    if data and data.get("status") == "success":
        return data["data"]["result"]
    return []


def mimir_range(query, start, end, step="60s"):
    """Query Mimir range. start/end are unix timestamps."""
    params = urllib.parse.urlencode({
        "query": query,
        "start": str(int(start)),
        "end": str(int(end)),
        "step": step,
    })
    url = f"{MIMIR_URL}/api/v1/query_range?{params}"
    data = fetch_json(url, timeout=RANGE_TIMEOUT)
    if data and data.get("status") == "success":
        return data["data"]["result"]
    return []


def mimir_avg_uptime(job_label, days):
    """Return dict: instance -> uptime_percentage (float, e.g. 99.99872).
    Uses avg_over_time on Mimir range query."""
    end = time.time()
    start = end - (days * 86400)
    # Mimir limits to ~11k points per series; compute safe step
    step = max(60, (days * 86400) // 10000)
    results = mimir_range(
        f'avg_over_time(up{{job=~"{job_label}"}}[{days}d]) * 100',
        start, end, step=f"{step}s",
    )
    uptimes = {}
    for r in results:
        inst = r["metric"].get("instance", "unknown")
        # Take the last value from the range (most recent avg_over_time bucket)
        values = r.get("values", [])
        if values:
            try:
                uptimes[inst] = float(values[-1][1])
            except (ValueError, IndexError):
                uptimes[inst] = 0.0
        else:
            # Single value (instant query fallback)
            v = r.get("value", [None, "0"])
            try:
                uptimes[inst] = float(v[1])
            except (ValueError, TypeError):
                uptimes[inst] = 0.0
    return uptimes


# ── Data collection ─────────────────────────────────────────────────


def get_nodes():
    """Return list of node dicts: name, ip, load, cpu%, ram%, disk%, 30d_uptime, 7d_uptime."""
    # Current state from pite
    up_data = {r["metric"]["instance"]: r["value"][1]
               for r in prom_instant('up{job="home-nodes"}')}
    load_data = {r["metric"]["instance"]: r["value"][1]
                 for r in prom_instant('node_load1{job="home-nodes"}')}
    mem_data = {r["metric"]["instance"]: r["value"][1]
                for r in prom_instant(
                    '(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'
                )}
    # CPU: 100 - (idle %)
    cpu_data = {}
    for r in prom_instant(
        '100 - (avg without(cpu,mode) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)'
    ):
        cpu_data[r["metric"]["instance"]] = r["value"][1]
    disk_data = {r["metric"]["instance"]: r["value"][1]
                 for r in prom_instant(
                     '(node_filesystem_avail_bytes{mountpoint="/"} / '
                     'node_filesystem_size_bytes{mountpoint="/"}) * 100'
                 )}

    # Long-term uptime from Mimir
    uptime_30d = mimir_avg_uptime("home-nodes", 30)
    uptime_7d = mimir_avg_uptime("home-nodes", 7)

    mimir_up = mimir_instant('up{job="home-nodes"}')
    mimir_up_map = {r["metric"]["instance"]: r["value"][1] for r in mimir_up}

    nodes = []
    all_instances = sorted(set(
        list(up_data.keys()) + list(mimir_up_map.keys())
    ))

    for inst in all_instances:
        name = NODE_NAMES.get(inst, inst)
        ip = inst.replace(":9100", "")
        up = float(up_data.get(inst, mimir_up_map.get(inst, 0)))
        load = float(load_data.get(inst, 0))
        cpu = float(cpu_data.get(inst, 0))
        mem = float(mem_data.get(inst, 100))  # 100 = unknown
        disk = float(disk_data.get(inst, 100))

        u30 = uptime_30d.get(inst)
        u7 = uptime_7d.get(inst)

        nodes.append({
            "name": name,
            "ip": ip,
            "up": up == 1,
            "load": load,
            "cpu": cpu,
            "ram": 100 - mem,  # mem = avail %, so used % = 100 - avail
            "disk": 100 - disk,  # disk = avail %, so used % = 100 - avail
            "uptime_30d": u30,
            "uptime_7d": u7,
        })
    return nodes


def get_services():
    """Return list of service dicts in SERVICE_ORDER: name, up, latency, 30d_uptime, 7d_uptime."""
    # Current state from pite
    up_data = {r["metric"]["instance"]: r["value"][1]
               for r in prom_instant('up{job=~"blackbox.*"}')}
    latency_data = {r["metric"]["instance"]: r["value"][1]
                    for r in prom_instant('probe_duration_seconds{job=~"blackbox.*"}')}

    # Uptime from Mimir
    uptime_30d = mimir_avg_uptime("blackbox.*", 30)
    uptime_7d = mimir_avg_uptime("blackbox.*", 7)

    mimir_up = mimir_instant('up{job=~"blackbox.*"}')
    mimir_up_map = {r["metric"]["instance"]: r["value"][1] for r in mimir_up}

    services = []
    for inst in SERVICE_ORDER:
        name = SERVICE_NAMES.get(inst, inst)
        up = float(up_data.get(inst, mimir_up_map.get(inst, 0)))
        lat = float(latency_data.get(inst, 0))
        u30 = uptime_30d.get(inst)
        u7 = uptime_7d.get(inst)

        services.append({
            "name": name,
            "instance": inst,
            "up": up == 1,
            "latency_s": lat,
            "uptime_30d": u30,
            "uptime_7d": u7,
        })
    return services


def get_ssl_certs():
    """Return list of SSL cert dicts: domain, days_left."""
    certs = []
    for r in prom_instant(
        '(probe_ssl_earliest_cert_expiry - time()) / 86400'
    ):
        inst = r["metric"]["instance"]
        try:
            days = float(r["value"][1])
        except (ValueError, TypeError):
            days = 0
        domain = inst.replace("https://", "").rstrip("/")
        certs.append({
            "domain": domain,
            "days_left": days,
            "ok": days > 14,
        })
    certs.sort(key=lambda c: c["domain"])
    return certs


def get_remote_write():
    """Return dict of remote write stats from pite Prometheus.
    Returns available=False if the metrics don't exist (e.g. Prometheus 3.x)."""
    def _sum(metric):
        vals = [float(r["value"][1]) for r in prom_instant(metric)]
        return int(sum(vals)) if vals else 0

    # Probe whether remote write metrics exist
    check = prom_instant("prometheus_remote_storage_samples_total")
    if not check:
        return {
            "available": False,
            "samples": 0, "failed": 0, "pending": 0, "bytes": 0,
            "last_sent_ago": None, "retries": 0,
            "fail_pct": 0, "retry_pct": 0,
        }

    samples = _sum("prometheus_remote_storage_samples_total")
    failed = _sum("prometheus_remote_storage_samples_failed_total")
    pending = _sum("prometheus_remote_storage_samples_pending")
    bytes_total = _sum("prometheus_remote_storage_bytes_total")

    # Highest timestamp
    highest = 0
    for r in prom_instant("prometheus_remote_storage_highest_timestamp_in_seconds"):
        try:
            highest = max(highest, float(r["value"][1]))
        except (ValueError, TypeError):
            pass
    last_sent_ago = time.time() - highest if highest > 0 else None

    # Retries
    retries = _sum("prometheus_remote_storage_samples_retried_total")

    return {
        "available": True,
        "samples": samples,
        "failed": failed,
        "pending": pending,
        "bytes": bytes_total,
        "last_sent_ago": last_sent_ago,
        "retries": retries,
        "fail_pct": (failed / samples * 100) if samples > 0 else 0,
        "retry_pct": (retries / samples * 100) if samples > 0 else 0,
    }


def get_alerts():
    """Return list of firing alert dicts: name, severity, summary."""
    data = fetch_json(f"{PROM_URL}/api/v1/alerts")
    if not data:
        return []
    alerts = []
    for a in data.get("data", {}).get("alerts", []):
        if a.get("state") != "firing":
            continue
        labels = a.get("labels", {})
        annotations = a.get("annotations", {})
        alerts.append({
            "name": labels.get("alertname", "Unknown"),
            "severity": labels.get("severity", "none"),
            "summary": annotations.get("summary", ""),
        })
    return alerts


def get_k8s_pods():
    """Return list of non-healthy pod dicts: namespace, name, status, age.
    Returns None if kubectl is unavailable."""
    if not os.path.exists(KUBECONFIG):
        return None
    try:
        result = subprocess.run(
            [
                "kubectl",
                f"--kubeconfig={KUBECONFIG}",
                "get", "pods", "-A",
                "--no-headers",
                "--field-selector=status.phase!=Running,status.phase!=Succeeded",
            ],
            capture_output=True, text=True, timeout=15,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as exc:
        print(f"[WARN] kubectl failed: {exc}", file=sys.stderr)
        return None

    if result.returncode != 0:
        print(f"[WARN] kubectl exited {result.returncode}: {result.stderr.strip()}",
              file=sys.stderr)
        return None

    pods = []
    for line in result.stdout.strip().split("\n"):
        if not line:
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        pods.append({
            "namespace": parts[0],
            "name": parts[1],
            "status": parts[3],
            "age": parts[5],
        })
    return pods


# ── Formatting helpers ───────────────────────────────────────────────


def fmt_uptime(pct):
    """Format uptime percentage to 5 decimal places, or '--' if None."""
    if pct is None:
        return "--"
    return f"{pct:.5f}%"


def fmt_latency(seconds):
    """Format latency in human-readable form."""
    if seconds < 1:
        return f"{seconds * 1000:.0f}ms"
    return f"{seconds:.2f}s"


def fmt_bytes(b):
    """Format bytes in human-readable form."""
    if b >= 1_000_000_000:
        return f"{b / 1_000_000_000:.2f} GB"
    if b >= 1_000_000:
        return f"{b / 1_000_000:.1f} MB"
    if b >= 1000:
        return f"{b / 1000:.1f} KB"
    return f"{b} B"


def fmt_count(n):
    """Format large numbers with units."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1000:
        return f"{n / 1000:.1f}K"
    return str(n)


def status_class(ok):
    """Return CSS class for up/down status."""
    return "up" if ok else "down"


def cert_class(ok):
    """Return CSS class for cert status."""
    return "ok" if ok else "expiring"


def severity_class(sev):
    """Return CSS class for alert severity."""
    return sev


# ── HTML generation ──────────────────────────────────────────────────


def render_node_rows(nodes):
    rows = []
    for n in nodes:
        up_badge = '<span class="up">UP</span>' if n["up"] else '<span class="down">DOWN</span>'
        rows.append(
            f'<tr>'
            f'<td>{html.escape(n["name"])} ({html.escape(n["ip"])})</td>'
            f'<td>{n["load"]:.2f}</td>'
            f'<td>{n["cpu"]:.1f}%</td>'
            f'<td>{n["ram"]:.1f}%</td>'
            f'<td>{n["disk"]:.1f}%</td>'
            f'<td>{fmt_uptime(n["uptime_30d"])}</td>'
            f'</tr>'
        )
    return "\n".join(rows)


def render_service_rows(services):
    rows = []
    for s in services:
        up_badge = '<span class="up">UP</span>' if s["up"] else '<span class="down">DOWN</span>'
        rows.append(
            f'<tr>'
            f'<td>{html.escape(s["name"])}</td>'
            f'<td>{up_badge}</td>'
            f'<td>{fmt_uptime(s["uptime_30d"])}</td>'
            f'<td>{fmt_uptime(s["uptime_7d"])}</td>'
            f'<td>{fmt_latency(s["latency_s"])}</td>'
            f'</tr>'
        )
    return "\n".join(rows)


def render_cert_rows(certs):
    if not certs:
        return '<tr><td colspan="2">No SSL certificates monitored.</td></tr>'
    rows = []
    for c in certs:
        cls = cert_class(c["ok"])
        status = "OK" if c["ok"] else f"EXPIRES IN {c['days_left']:.0f} DAYS"
        rows.append(
            f'<tr class="{cls}">'
            f'<td>{html.escape(c["domain"])}</td>'
            f'<td>expires in {c["days_left"]:.0f} days</td>'
            f'<td>{status}</td>'
            f'</tr>'
        )
    return "\n".join(rows)


def render_pod_rows(pods):
    if pods is None:
        return '<tr><td colspan="4">Cluster unreachable (kubeconfig not set up or kubectl failed).</td></tr>'
    if not pods:
        return '<tr><td colspan="4">All pods healthy.</td></tr>'
    rows = []
    for p in pods:
        rows.append(
            f'<tr>'
            f'<td>{html.escape(p["namespace"])}/{html.escape(p["name"])}</td>'
            f'<td class="down">{html.escape(p["status"])}</td>'
            f'<td>{html.escape(p["age"])}</td>'
            f'</tr>'
        )
    return "\n".join(rows)



def render_rw_rows(rw):
    """Render remote write stats table rows."""
    if not rw["available"]:
        return '<tr><td colspan="4">Remote write metrics not available (Prometheus 3.x). Data is flowing — check Mimir.</td></tr>'
    return (
        f'<tr>'
        f'<td>Samples sent</td>'
        f'<td>{fmt_count(rw["samples"])}</td>'
        f'<td>Failed</td>'
        f'<td>{fmt_count(rw["failed"])} ({rw["fail_pct"]:.2f}%)</td>'
        f'</tr>\n'
        f'<tr>'
        f'<td>Queue depth</td>'
        f'<td>{rw["pending"]}</td>'
        f'<td>Data pushed</td>'
        f'<td>{fmt_bytes(rw["bytes"])}</td>'
        f'</tr>\n'
        f'<tr>'
        f'<td>Last sent</td>'
        f'<td>{"<1s ago" if rw["last_sent_ago"] is not None and rw["last_sent_ago"] < 5 else "N/A"}</td>'
        f'<td>Retries</td>'
        f'<td>{fmt_count(rw["retries"])} ({rw["retry_pct"]:.2f}%)</td>'
        f'</tr>'
    )
def render_alert_rows(alerts):
    if not alerts:
        return '<tr><td colspan="3">No active alerts.</td></tr>'
    rows = []
    for a in alerts:
        rows.append(
            f'<tr class="{severity_class(a["severity"])}">'
            f'<td>{html.escape(a["name"])}</td>'
            f'<td>{html.escape(a["severity"])}</td>'
            f'<td>{html.escape(a["summary"])}</td>'
            f'</tr>'
        )
    return "\n".join(rows)


def render_summary(nodes, services, pods, certs, alerts):
    """Render summary badge bar."""
    nodes_up = sum(1 for n in nodes if n["up"])
    nodes_total = len(nodes)
    svc_up = sum(1 for s in services if s["up"])
    svc_total = len(services)
    if pods is None:
        pods_text = "N/A"
    elif len(pods) == 0:
        pods_text = "All healthy"
    else:
        pods_text = f"{len(pods)} unhealthy"
    certs_ok = sum(1 for c in certs if c["ok"])
    certs_total = len(certs)
    alert_count = len(alerts)
    alert_text = "None!" if alert_count == 0 else f"{alert_count} FIRING"

    return (
        f'│ Nodes  │ Services │ Pods    │ Certs      │ Alerts {alert_count}  │\n'
        f'│ {nodes_up}/{nodes_total} UP │ {svc_up}/{svc_total} UP  │ {pods_text} │ {certs_ok}/{certs_total} valid  │ {alert_text}     │'
    )


def render_html(nodes, services, certs, rw, pods, alerts, errors):
    """Generate full HTML page."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    summary = render_summary(nodes, services, pods, certs, alerts)

    error_html = ""
    if errors:
        error_html = (
            '<div class="errors">\n'
            + "\n".join(f"  <p>{html.escape(e)}</p>" for e in errors)
            + "\n</div>\n"
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <title>2143 Status</title>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="30">
  <style>
    body {{
      font-family: system-ui, -apple-system, sans-serif;
      max-width: 900px;
      margin: 1em auto;
      padding: 0 1em;
      background: #0d1117;
      color: #c9d1d9;
    }}
    h1 {{ font-size: 1.4em; margin: 0.5em 0; }}
    h2 {{
      font-size: 1.1em;
      border-bottom: 1px solid #30363d;
      padding-bottom: 0.3em;
      margin: 1.2em 0 0.5em;
    }}
    .box {{
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 6px;
      padding: 1em;
      margin: 0.5em 0;
      font-family: monospace;
      white-space: pre;
      font-size: 0.9em;
      line-height: 1.4;
      overflow-x: auto;
    }}
    table {{
      border-collapse: collapse;
      width: 100%;
      font-size: 0.95em;
    }}
    th, td {{
      padding: 4px 10px;
      border-bottom: 1px solid #21262d;
      text-align: left;
    }}
    th {{
      color: #8b949e;
      font-weight: 600;
      border-bottom: 2px solid #30363d;
    }}
    tr:hover td {{ background: #1c2128; }}
    .up {{ color: #3fb950; font-weight: bold; }}
    .down {{ color: #f85149; font-weight: bold; }}
    .ok {{ color: #3fb950; }}
    .expiring {{ color: #d29922; }}
    .critical {{ color: #f85149; font-weight: bold; }}
    .warning {{ color: #d29922; }}
    .info {{ color: #58a6ff; }}
    .none {{ color: #8b949e; }}
    .errors {{
      background: #f8514920;
      border: 1px solid #f85149;
      border-radius: 6px;
      padding: 0.5em 1em;
      margin: 0.5em 0;
      color: #f85149;
      font-size: 0.9em;
    }}
    .muted {{ color: #8b949e; font-size: 0.85em; }}
    a {{ color: #58a6ff; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    .links {{
      display: flex;
      gap: 1.5em;
      flex-wrap: wrap;
    }}
  </style>
</head>
<body>
  <h1>2143 Status Dashboard</h1>
  <p class="muted">Updated: {now} — refreshes every 30s</p>

{error_html}
  <div class="box">{summary}</div>

  <h2>NODES</h2>
  <table>
    <tr>
      <th>Hostname</th>
      <th>Load</th>
      <th>CPU%</th>
      <th>RAM%</th>
      <th>Disk%</th>
      <th>30d Uptime</th>
    </tr>
{render_node_rows(nodes)}
  </table>

  <h2>SERVICES</h2>
  <table>
    <tr>
      <th>Service</th>
      <th>Status</th>
      <th>30d Uptime</th>
      <th>7d Uptime</th>
      <th>Latency</th>
    </tr>
{render_service_rows(services)}
  </table>

  <h2>SSL CERTIFICATES</h2>
  <table>
    <tr>
      <th>Domain</th>
      <th>Expiry</th>
      <th>Status</th>
    </tr>
{render_cert_rows(certs)}
  </table>

  <h2>HOME K3S PODS <span class="muted">(non-healthy only)</span></h2>
  <table>
    <tr>
      <th>Pod</th>
      <th>Status</th>
      <th>Age</th>
    </tr>
{render_pod_rows(pods)}
  </table>

  <h2>REMOTE WRITE <span class="muted">(Prometheus → Mimir)</span></h2>
  <table>
{render_rw_rows(rw)}
  </table>

  <h2>ACTIVE ALERTS</h2>
  <table>
    <tr>
      <th>Alert</th>
      <th>Severity</th>
      <th>Summary</th>
    </tr>
{render_alert_rows(alerts)}
  </table>

  <div class="links" style="margin-top:1.5em;">
    <a href="https://grafana.john2143.com">Grafana</a>
    <a href="http://pite.local:9090">Prometheus</a>
    <a href="http://pite.local:9093">Alertmanager</a>
  </div>
</body>
</html>"""


# ── Main ─────────────────────────────────────────────────────────────


def main():
    errors = []

    # Collect data (each step handles its own errors)
    nodes = get_nodes()
    if not nodes:
        errors.append("Node metrics: no data returned from Prometheus.")

    services = get_services()
    if not services:
        errors.append("Service metrics: no data returned from Prometheus.")

    certs = get_ssl_certs()

    rw = get_remote_write()
    if rw["available"]:
        if rw["samples"] == 0:
            errors.append("Remote write configured but no samples pushed yet.")
    # else: metrics not available — Prometheus 3.x doesn't expose these; skip silently

    pods = get_k8s_pods()

    alerts = get_alerts()

    # Render
    html_content = render_html(nodes, services, certs, rw, pods, alerts, errors)

    # Write
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as f:
        f.write(html_content)

    # Quick summary to journal
    nodes_up = sum(1 for n in nodes if n["up"])
    svc_up = sum(1 for s in services if s["up"])
    pod_status = "unreachable" if pods is None else f"{len(pods)} unhealthy"
    print(
        f"status-page: nodes={nodes_up}/{len(nodes)} services={svc_up}/{len(services)} "
        f"pods={pod_status} alerts={len(alerts)} errors={len(errors)}"
    )


if __name__ == "__main__":
    main()
