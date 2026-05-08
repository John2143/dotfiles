#!/usr/bin/env python3
"""Render PNG graphs + a terminal summary from a vast-destroy metrics dir.

Usage: vast-render-metrics PATH

PATH is the per-rental directory written by vast-destroy. Expected layout:
    PATH/metrics/{gpu,sys,gpu_proc}.csv
    PATH/metrics/{pmon,nvlink}.log
    PATH/metrics/vllm.prom
    PATH/metrics/events.jsonl
    PATH/metrics/queries.jsonl  (optional, from logging proxy)
    PATH/rental.json            (optional, from vast-fetch-metrics)
    PATH/vllm.log

Every input is optional — missing files just skip the relevant output.
PNGs land alongside summary.txt at PATH/.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from pandas import Timedelta  # noqa: E402

SPARK = "▁▂▃▄▅▆▇█"

NUMERIC_GPU_COLS = ("util_gpu_pct", "util_mem_pct", "mem_used_mib",
                    "mem_total_mib", "power_w", "temp_c", "sm_clock_mhz")
NUMERIC_SYS_COLS = ("cpu_pct", "mem_used_gib", "mem_total_gib", "load1",
                    "disk_root_pct", "disk_workspace_pct",
                    "net_rx_mibps", "net_tx_mibps",
                    "disk_read_mibps", "disk_write_mibps")

ISO_LINE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+(.*)")
PARTIAL_RE = re.compile(r"\b(\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\b")
MILESTONES = [
    (re.compile(r"Loading weights took"), "weights_loaded"),
    (re.compile(r"Model loading took"), "model_loaded"),
    (re.compile(r"torch\.compile took"), "torch_compile_done"),
    (re.compile(r"DeepGEMM warmup:\s*100%"), "deepgemm_done"),
    (re.compile(r"Initial profiling/warmup run took"), "warmup_done"),
    (re.compile(r"Graph capturing finished"), "graph_capture_done"),
    (re.compile(r"Application startup complete"), "app_startup_done"),
    (re.compile(r"Engine core initialization failed"), "engine_core_failed"),
    (re.compile(r"\bRuntimeError:"), "runtime_error"),
]
IMPORTANT_EVENTS = {
    "bootstrap_start", "vllm_launch", "vllm_ready", "vllm_failed",
    "force_restart", "weights_loaded", "warmup_done",
    "engine_core_failed", "runtime_error", "monitor_start",
}


def fmt_dur(seconds):
    s = max(0, int(seconds))
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"

def fmt_sec(seconds):
    """Format seconds with appropriate precision for latency display."""
    s = max(0.0, float(seconds))
    if s < 0.001:
        return f"{s*1_000_000:.0f}µs"
    if s < 1.0:
        return f"{s*1000:.0f}ms"
    if s < 10.0:
        return f"{s:.1f}s"
    return f"{s:.0f}s"


def load_csv(path, numeric_cols):
    if not path.exists() or path.stat().st_size == 0:
        return None
    try:
        df = pd.read_csv(path, skipinitialspace=True)
    except Exception as e:
        print(f"warn: failed to parse {path}: {e}", file=sys.stderr)
        return None
    if "timestamp" not in df.columns:
        return None
    df["ts"] = pd.to_datetime(df["timestamp"], utc=True, errors="coerce")
    df = df.dropna(subset=["ts"])
    for c in numeric_cols:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def load_events(path):
    if not path.exists() or path.stat().st_size == 0:
        return []
    out = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            e["ts"] = pd.to_datetime(e["ts"], utc=True)
        except Exception:
            continue
        out.append(e)
    return out


def parse_vllm_log(path, fallback_year):
    if not path.exists():
        return []
    out = []
    for line in path.read_text(errors="replace").splitlines():
        ts = None
        rest = line
        m = ISO_LINE_RE.match(line)
        if m:
            ts = pd.to_datetime(m.group(1), utc=True, errors="coerce")
            rest = m.group(2)
        else:
            m2 = PARTIAL_RE.search(line)
            if m2:
                try:
                    ts = pd.to_datetime(
                        f"{fallback_year}-{m2.group(1)} {m2.group(2)}",
                        utc=True, errors="coerce",
                    )
                except Exception:
                    ts = None
        if ts is None or pd.isna(ts):
            continue
        for pat, lbl in MILESTONES:
            if pat.search(rest):
                out.append({"ts": ts, "type": lbl, "message": rest.strip()[:120]})
                break
    return out


def parse_vllm_prom(path):
    """Read the # T= separated Prometheus scrape file into a DataFrame.

    Pulls just the gauges we plot. All three are aggregated by mean across
    label sets within a scrape — this is correct for per-GPU gauges (e.g.
    `gpu_cache_usage_perc` reported once per TP rank in some vLLM versions),
    and harmless when there's only one label set (mean of one == that value).
    Summing would multiply by GPU count and produce >100% cache occupancy.
    """
    if not path.exists() or path.stat().st_size == 0:
        return None
    keep = {
        "vllm:gpu_cache_usage_perc": "gpu_cache_usage_perc",
        "vllm:gpu_kv_cache_usage_perc": "gpu_cache_usage_perc",
        "vllm:num_requests_running": "num_requests_running",
        "vllm:num_requests_waiting": "num_requests_waiting",
        "vllm:prompt_tokens_total": "prompt_tokens",
        "vllm:generation_tokens_total": "generation_tokens",
        "vllm:prefix_cache_hits_total": "prefix_cache_hits",
        "vllm:prefix_cache_queries_total": "prefix_cache_queries",
    }
    metric_re = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+(\S+)$")
    rows = []
    cur_ts = None
    cur = {}  # target -> list of values seen this scrape

    def flush():
        if cur_ts is not None and cur:
            rows.append({"ts": cur_ts, **{k: sum(vs) / len(vs) for k, vs in cur.items()}})

    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("# T="):
            flush()
            ts_str = line[4:].strip()
            # Handle both Unix epoch (older vLLM) and ISO 8601 (v0.11+)
            try:
                cur_ts = pd.to_datetime(int(ts_str), unit="s", utc=True)
            except (ValueError, TypeError):
                cur_ts = pd.to_datetime(ts_str, utc=True, errors="coerce")
            cur = {}
            continue
        if not line or line.startswith("#"):
            continue
        m = metric_re.match(line)
        if not m:
            continue
        target = keep.get(m.group(1))
        if not target:
            continue
        try:
            v = float(m.group(3))
        except ValueError:
            continue
        cur.setdefault(target, []).append(v)
    flush()
    if not rows:
        return None
    return pd.DataFrame(rows).sort_values("ts").reset_index(drop=True)


def parse_vllm_histograms(path):
    """Extract final cumulative histogram summaries from vLLM Prometheus.

    Returns a dict keyed by short metric name, each containing p50/p95/p99/avg/count
    approximated via linear interpolation between histogram bucket boundaries.
    """
    if not path.exists() or path.stat().st_size == 0:
        return {}
    target_hists = {
        "vllm:time_to_first_token_seconds": "ttft",
        "vllm:inter_token_latency_seconds": "itl",
        "vllm:e2e_request_latency_seconds": "e2e_latency",
        "vllm:request_queue_time_seconds": "queue_time",
        "vllm:request_prefill_time_seconds": "prefill_time",
        "vllm:request_decode_time_seconds": "decode_time",
    }
    hist_re = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)_bucket\{[^}]*le=\"([^\"]*)\"[^}]*\}\s+(\S+)$")
    count_re = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)_count\{[^}]*\}\s+(\S+)$")
    sum_re = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)_sum\{[^}]*\}\s+(\S+)$")

    # Collect the final (last) scrape's bucket/count/sum per histogram.
    final_buckets = {}   # metric -> [(le_float, cum_count)]
    final_count = {}     # metric -> total count
    final_sum = {}       # metric -> sum

    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("# T="):
            # New scrape: reset to capture only the last (cumulative) values
            final_buckets = {}
            final_count = {}
            final_sum = {}
            continue
        if not line or line.startswith("#"):
            continue
        for prefix, short in target_hists.items():
            m = hist_re.match(line)
            if m and m.group(1) == prefix:
                try:
                    le_val = float(m.group(2))
                except ValueError:
                    continue
                try:
                    cum = float(m.group(3))
                except ValueError:
                    continue
                final_buckets.setdefault(short, []).append((le_val, cum))
                break
            m2 = count_re.match(line)
            if m2 and m2.group(1) == prefix:
                try:
                    final_count[short] = float(m2.group(2))
                except ValueError:
                    pass
                break
            m3 = sum_re.match(line)
            if m3 and m3.group(1) == prefix:
                try:
                    final_sum[short] = float(m3.group(2))
                except ValueError:
                    pass
                break

    def _interp(buckets, target_frac, total):
        """Linear interpolation for target_frac (e.g. 0.5 for p50)."""
        target_cum = target_frac * total
        prev_le, prev_cum = 0.0, 0.0
        for le, cum in sorted(buckets, key=lambda x: x[0]):
            if cum >= target_cum:
                if cum == prev_cum:
                    return le
                frac = (target_cum - prev_cum) / (cum - prev_cum)
                return prev_le + frac * (le - prev_le)
            prev_le, prev_cum = le, cum
        return prev_le

    out = {}
    for short in target_hists.values():
        buckets = final_buckets.get(short, [])
        total = final_count.get(short, 0)
        if total <= 0 or not buckets:
            continue
        out[short] = {
            "count": int(total),
            "avg": final_sum.get(short, 0) / total,
            "p50": _interp(buckets, 0.50, total),
            "p95": _interp(buckets, 0.95, total),
            "p99": _interp(buckets, 0.99, total),
        }
    return out


def load_queries(path):
    """Parse queries.jsonl written by the logging proxy."""
    if not path.exists() or path.stat().st_size == 0:
        return []
    out = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        ts_str = rec.get("ts")
        duration_ms = rec.get("duration_ms")
        if not ts_str or duration_ms is None:
            continue
        try:
            ts = pd.to_datetime(ts_str, utc=True)
        except Exception:
            continue
        end_ts = ts + Timedelta(milliseconds=float(duration_ms))
        usage = None
        resp = rec.get("response", {})
        usage = resp.get("usage")
        if usage is None:
            for evt in rec.get("response_events", []):
                u = evt.get("usage")
                if u:
                    usage = u
        endpoint = rec.get("path", "")
        status = rec.get("status", 0)
        is_stream = rec.get("stream", False)
        out.append({
            "ts": ts,
            "end_ts": end_ts,
            "duration_ms": float(duration_ms),
            "endpoint": endpoint,
            "status": status,
            "is_stream": is_stream,
            "usage": usage,
        })
    return out


def load_nvlink(path):
    """Parse nvlink.log into a DataFrame with per-link cumulative + delta counters."""
    if not path.exists() or path.stat().st_size == 0:
        return None
    ts_re = re.compile(r"^# T=(.+)$")
    gpu_re = re.compile(r"^GPU (\d+):")
    link_re = re.compile(r"^\s+Link (\d+): Data Tx:\s+(\d+) KiB")
    link_rx_re = re.compile(r"^\s+Link (\d+): Data Rx:\s+(\d+) KiB")
    rows = []
    cur_ts = None
    cur_gpu = None
    for line in path.read_text(errors="replace").splitlines():
        m = ts_re.match(line)
        if m:
            cur_ts = pd.to_datetime(m.group(1), utc=True, errors="coerce")
            continue
        m2 = gpu_re.match(line)
        if m2:
            cur_gpu = int(m2.group(1))
            continue
        m3 = link_re.match(line)
        if m3 and cur_ts is not None and cur_gpu is not None:
            link = int(m3.group(1))
            tx_kib = int(m3.group(2))
            rows.append({"ts": cur_ts, "gpu": cur_gpu, "link": link,
                         "tx_kib": tx_kib, "rx_kib": None})
            continue
        m4 = link_rx_re.match(line)
        if m4 and rows and rows[-1]["rx_kib"] is None:
            rows[-1]["rx_kib"] = int(m4.group(2))
    if not rows:
        return None
    df = pd.DataFrame(rows)
    df = df.dropna(subset=["rx_kib"])
    if len(df) < 2:
        return None
    df = df.sort_values(["gpu", "link", "ts"]).reset_index(drop=True)
    df["tx_kibs"] = df.groupby(["gpu", "link"])["tx_kib"].diff()
    df["rx_kibs"] = df.groupby(["gpu", "link"])["rx_kib"].diff()
    df["dt"] = df.groupby(["gpu", "link"])["ts"].diff().dt.total_seconds()
    df = df.dropna(subset=["dt"]).copy()
    if len(df) == 0:
        return None
    df["tx_gibs"] = (df["tx_kibs"] / 1048576) / df["dt"]
    df["rx_gibs"] = (df["rx_kibs"] / 1048576) / df["dt"]
    agg = df.groupby(["ts", "gpu"])[["tx_gibs", "rx_gibs"]].sum().reset_index()
    return agg


def load_gpu_proc(path):
    """Parse gpu_proc.csv into a DataFrame."""
    if not path.exists() or path.stat().st_size == 0:
        return None
    try:
        df = pd.read_csv(path, skipinitialspace=True)
    except Exception as e:
        print(f"warn: failed to parse {path}: {e}", file=sys.stderr)
        return None
    if "timestamp" not in df.columns:
        return None
    df["ts"] = pd.to_datetime(df["timestamp"], utc=True, errors="coerce")
    df = df.dropna(subset=["ts"])
    if "used_memory_mib" in df.columns:
        df["used_memory_mib"] = pd.to_numeric(df["used_memory_mib"], errors="coerce")
    return df


def load_rental(path):
    """Load rental.json if it exists, return dict or None."""
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except Exception:
        return None
def spark(values, n=24):
    arr = np.asarray(values, dtype=float)
    arr = arr[~np.isnan(arr)]
    if arr.size == 0:
        return ""
    if arr.size <= n:
        bins = arr
    else:
        idx = np.linspace(0, arr.size, n + 1, dtype=int)
        bins = np.array([arr[idx[i]:idx[i + 1]].mean() for i in range(n)])
    hi = max(100.0, float(bins.max()) if bins.size else 100.0)
    cells = np.clip(np.round(bins / hi * (len(SPARK) - 1)).astype(int),
                    0, len(SPARK) - 1)
    return "".join(SPARK[i] for i in cells)


def add_markers(ax, events):
    if not events:
        return
    _, ymax = ax.get_ylim()
    for e in events:
        if e.get("type") not in IMPORTANT_EVENTS:
            continue
        ts = e["ts"]
        ax.axvline(ts, color="0.55", linestyle=":", linewidth=0.8, zorder=0)
        ax.text(ts, ymax, " " + e["type"], rotation=90, va="top", ha="left",
                fontsize=6.5, color="0.35")
def add_query_bars(ax, queries):
    """Draw thin horizontal bars above the plot for each query interval."""
    if not queries:
        return
    _, ymax = ax.get_ylim()
    height = ymax * 0.03
    y = ymax * 1.02
    for q in queries:
        ts = q["ts"]
        end = q["end_ts"]
        status = q["status"]
        if status >= 400:
            color = "tab:red"
        elif "/chat/completions" in q["endpoint"]:
            color = "tab:blue"
        elif "/embeddings" in q["endpoint"]:
            color = "tab:green"
        else:
            color = "tab:orange"
        ax.barh(y, (end - ts).total_seconds(), height=height,
                left=ts, color=color, alpha=0.35, zorder=0,
                edgecolor="none")
    ax.set_ylim(top=ymax * 1.06)


def fmt_xaxis(ax):
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M", tz=timezone.utc))


def render_gpu_clock(gpu, events, base):
    """SM clock frequency over time (from gpu.csv sm_clock_mhz)."""
    if "sm_clock_mhz" not in gpu.columns:
        return []
    fig, ax = plt.subplots(figsize=(12, 3.5))
    for idx, sub in gpu.groupby("index"):
        ax.plot(sub["ts"], sub["sm_clock_mhz"], label=f"GPU {idx}",
                linewidth=1.0, alpha=0.85)
    ax.set_ylabel("SM clock (MHz)")
    ax.set_title("GPU SM clock frequency over time")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "gpu_clock.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]


def render_gpu_mem_util(gpu, events, base):
    """GPU memory bandwidth utilization (from gpu.csv util_mem_pct)."""
    if "util_mem_pct" not in gpu.columns:
        return []
    fig, ax = plt.subplots(figsize=(12, 3.5))
    for idx, sub in gpu.groupby("index"):
        ax.plot(sub["ts"], sub["util_mem_pct"], label=f"GPU {idx}",
                linewidth=1.0, alpha=0.85)
    ax.set_ylim(0, 105)
    ax.set_ylabel("Memory util %")
    ax.set_title("GPU memory bandwidth utilization over time")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "gpu_mem_util.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]


def render_token_throughput(vm, events, base):
    """Derive tok/s from vLLM Prometheus counter deltas."""
    needed = ["prompt_tokens", "generation_tokens"]
    if not all(c in vm.columns for c in needed) or len(vm) < 2:
        return []
    df = vm.sort_values("ts").reset_index(drop=True)
    dt = df["ts"].diff().dt.total_seconds()
    # Detect counter resets (vLLM restart)
    d_prompt = df["prompt_tokens"].diff()
    d_gen = df["generation_tokens"].diff()
    # Clamp negative deltas (counter reset) to NaN
    d_prompt = d_prompt.where(d_prompt >= 0)
    d_gen = d_gen.where(d_gen >= 0)
    prompt_tps = d_prompt / dt
    gen_tps = d_gen / dt
    valid = dt > 0
    fig, ax = plt.subplots(figsize=(12, 3.5))
    ax.plot(df.loc[valid, "ts"], prompt_tps[valid], label="prompt tok/s",
            linewidth=1.0, color="tab:blue", alpha=0.85)
    ax.plot(df.loc[valid, "ts"], gen_tps[valid], label="generation tok/s",
            linewidth=1.0, color="tab:green", alpha=0.85)
    ax.set_ylabel("Tokens / second")
    ax.set_title("Token throughput (from vLLM prometheus counters)")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "token_throughput.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]


def render_nvlink_throughput(nvlink, events, base):
    """NVLink aggregate bandwidth from cumulative counter deltas."""
    if nvlink is None or len(nvlink) == 0:
        return []
    fig, ax = plt.subplots(figsize=(12, 3.5))
    nvlink["total_gibs"] = nvlink["tx_gibs"] + nvlink["rx_gibs"]
    for gpu_idx, sub in nvlink.groupby("gpu"):
        ax.plot(sub["ts"], sub["total_gibs"], label=f"GPU {gpu_idx}",
                linewidth=1.0, alpha=0.85)
    ax.set_ylabel("NVLink (GiB/s)")
    ax.set_title("NVLink aggregate throughput (TX+RX)")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "nvlink_bw.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]


def render_inflight(queries, events, base):
    """Concurrent in-flight requests over time (from queries.jsonl intervals)."""
    if not queries:
        return []
    events_pts = [(q["ts"], 1) for q in queries] + [(q["end_ts"], -1) for q in queries]
    events_pts.sort(key=lambda x: x[0])
    # Build 1-second resolution series
    min_ts = events_pts[0][0]
    max_ts = events_pts[-1][0]
    rng = pd.date_range(min_ts, max_ts, freq="1s")
    ts_vals = np.zeros(len(rng), dtype=int)
    idx = 0
    cur = 0
    for i, t in enumerate(rng):
        while idx < len(events_pts) and events_pts[idx][0] <= t:
            cur += events_pts[idx][1]
            idx += 1
        ts_vals[i] = cur
    fig, ax = plt.subplots(figsize=(12, 3.5))
    ax.plot(rng, ts_vals, drawstyle="steps-post", linewidth=1.0)
    ax.set_ylabel("In-flight requests")
    ax.set_title("Concurrent in-flight requests (client-side from queries.jsonl)")
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "requests_inflight.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]
def render_gpu(gpu, events, queries, base):
    out = []
    fig, ax = plt.subplots(figsize=(12, 4.5))
    for idx, sub in gpu.groupby("index"):
        ax.plot(sub["ts"], sub["util_gpu_pct"], label=f"GPU {idx}",
                linewidth=1.0, alpha=0.85)
    avg = gpu.groupby("ts")["util_gpu_pct"].mean()
    ax.plot(avg.index, avg.values, label="mean", linewidth=2.0,
            linestyle="--", color="black")
    ax.set_ylim(0, 105)
    ax.set_ylabel("GPU util %")
    ax.set_title("GPU utilization over time")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    add_query_bars(ax, queries)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "gpu_util.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    out.append(path.name)

    fig, ax = plt.subplots(figsize=(12, 3.5))
    for idx, sub in gpu.groupby("index"):
        ax.plot(sub["ts"], sub["mem_used_mib"] / 1024,
                label=f"GPU {idx}", linewidth=1.0)
    ax.set_ylabel("VRAM used (GiB)")
    ax.set_title("VRAM usage over time")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "vram.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    out.append(path.name)

    fig, ax = plt.subplots(figsize=(12, 3.5))
    ax2 = ax.twinx()
    for idx, sub in gpu.groupby("index"):
        ax.plot(sub["ts"], sub["power_w"], label=f"GPU {idx} W",
                linewidth=1.0, alpha=0.85)
        ax2.plot(sub["ts"], sub["temp_c"], linestyle=":",
                 linewidth=0.9, alpha=0.7)
    ax.set_ylabel("Power (W)")
    ax2.set_ylabel("Temp (°C)")
    ax.set_title("Power (solid) + temperature (dotted)")
    ax.legend(loc="upper right", fontsize=8)
    add_markers(ax, events)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "power_temp.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    out.append(path.name)
    return out


def render_sys(sysd, base):
    fig, axes = plt.subplots(2, 2, figsize=(12, 6), sharex=True)
    axes[0, 0].plot(sysd["ts"], sysd["cpu_pct"], linewidth=1)
    axes[0, 0].set_title("CPU %")
    axes[0, 0].set_ylim(0, 105)
    axes[0, 1].plot(sysd["ts"], sysd["mem_used_gib"], linewidth=1)
    axes[0, 1].set_title("RAM used (GiB)")
    axes[1, 0].plot(sysd["ts"], sysd["net_rx_mibps"], label="rx", linewidth=1)
    axes[1, 0].plot(sysd["ts"], sysd["net_tx_mibps"], label="tx", linewidth=1)
    axes[1, 0].set_title("Net (MiB/s)")
    axes[1, 0].legend(fontsize=7)
    axes[1, 1].plot(sysd["ts"], sysd["disk_read_mibps"], label="read", linewidth=1)
    axes[1, 1].plot(sysd["ts"], sysd["disk_write_mibps"], label="write", linewidth=1)
    axes[1, 1].set_title("Disk (MiB/s)")
    axes[1, 1].legend(fontsize=7)
    for a in axes.flat:
        fmt_xaxis(a)
    fig.autofmt_xdate()
    fig.suptitle("System metrics")
    fig.tight_layout()
    path = base / "system.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]


def render_vllm(vm, events, queries, base):
    fig, ax = plt.subplots(figsize=(12, 4))
    plotted = False
    if "gpu_cache_usage_perc" in vm.columns:
        ax.plot(vm["ts"], vm["gpu_cache_usage_perc"] * 100,
                label="KV cache %", linewidth=1)
        plotted = True
    if "num_requests_running" in vm.columns:
        ax.plot(vm["ts"], vm["num_requests_running"],
                label="running reqs", linewidth=1)
        plotted = True
    if "num_requests_waiting" in vm.columns:
        ax.plot(vm["ts"], vm["num_requests_waiting"],
                label="waiting reqs", linewidth=1)
        plotted = True
    if not plotted:
        plt.close(fig)
        return []
    ax.legend(fontsize=8)
    ax.set_title("vLLM live metrics")
    add_markers(ax, events)
    add_query_bars(ax, queries)
    fmt_xaxis(ax)
    fig.autofmt_xdate()
    fig.tight_layout()
    path = base / "vllm.png"
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return [path.name]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="Directory containing metrics/ and vllm.log")
    args = ap.parse_args()

    base = Path(args.path).resolve()
    mdir = base / "metrics"
    if not mdir.exists() and (base / "gpu.csv").exists():
        # User passed the metrics/ dir itself.
        mdir = base
        base = base.parent
    if not mdir.exists():
        print(f"No metrics directory at {base}/metrics", file=sys.stderr)
        return 1

    gpu = load_csv(mdir / "gpu.csv", NUMERIC_GPU_COLS)
    sysd = load_csv(mdir / "sys.csv", NUMERIC_SYS_COLS)
    events = load_events(mdir / "events.jsonl")
    queries = load_queries(mdir / "queries.jsonl")
    nvlink = load_nvlink(mdir / "nvlink.log")
    rental = load_rental(base / "rental.json")

    fallback_year = datetime.now(timezone.utc).year
    if events:
        fallback_year = events[0]["ts"].year
    elif gpu is not None and len(gpu):
        fallback_year = gpu["ts"].iloc[0].year
    log_events = parse_vllm_log(base / "vllm.log", fallback_year)
    all_events = events + log_events
    all_events.sort(key=lambda e: e["ts"])

    pngs = []
    if gpu is not None and len(gpu):
        pngs += render_gpu(gpu, all_events, queries, base)
        pngs += render_gpu_clock(gpu, all_events, base)
        pngs += render_gpu_mem_util(gpu, all_events, base)
    if sysd is not None and len(sysd):
        pngs += render_sys(sysd, base)
    vm = parse_vllm_prom(mdir / "vllm.prom")
    histograms = parse_vllm_histograms(mdir / "vllm.prom")
    if vm is not None and len(vm):
        pngs += render_vllm(vm, all_events, queries, base)
        pngs += render_token_throughput(vm, all_events, base)
    if nvlink is not None and len(nvlink):
        pngs += render_nvlink_throughput(nvlink, all_events, base)
    if queries:
        pngs += render_inflight(queries, all_events, base)

    # Summary text + ASCII printout
    summary_lines = [f"Metrics dir: {mdir}"]
    print()
    if gpu is not None and len(gpu):
        wall = (gpu["ts"].max() - gpu["ts"].min()).total_seconds()
        summary_lines.append(
            f"Span: {gpu['ts'].min()} → {gpu['ts'].max()} ({fmt_dur(wall)})"
        )
        for idx, sub in gpu.groupby("index"):
            avg = sub["util_gpu_pct"].mean()
            peak = sub["util_gpu_pct"].max()
            spk = spark(sub["util_gpu_pct"].values, n=24)
            line = f"  GPU {idx} util {spk}  avg {avg:5.1f}%  peak {peak:.0f}%"
            print(line)
            summary_lines.append(line)
        if "mem_used_mib" in gpu.columns:
            latest = gpu.sort_values("ts").groupby("index").tail(1)
            for _, row in latest.iterrows():
                used = row["mem_used_mib"] / 1024
                tot = row["mem_total_mib"] / 1024 if pd.notna(row["mem_total_mib"]) else 0
                line = f"  GPU {int(row['index'])} VRAM (final)             {used:.1f} / {tot:.1f} GiB"
                summary_lines.append(line)

    bootstrap = next((e for e in events if e["type"] == "bootstrap_start"), None)
    ready = next((e for e in events if e["type"] == "vllm_ready"), None)
    if bootstrap and ready:
        ttr = (ready["ts"] - bootstrap["ts"]).total_seconds()
        line = f"  time-to-vllm-ready: {fmt_dur(ttr)}"
        print(line)
        summary_lines.append(line)

    # --- GPU utilization distribution ---
    if gpu is not None and len(gpu):
        n_samples = len(gpu)
        summary_lines.append("")
        summary_lines.append(f"GPU utilization distribution ({n_samples} samples over {fmt_dur(wall)}):")
        for idx, sub in gpu.groupby("index"):
            vals = sub["util_gpu_pct"].dropna()
            if len(vals) == 0:
                continue
            idle_pct = (vals <= 1).mean() * 100
            low_pct = ((vals > 1) & (vals <= 25)).mean() * 100
            med_pct = ((vals > 25) & (vals <= 75)).mean() * 100
            high_pct = (vals > 75).mean() * 100
            p50 = np.percentile(vals, 50)
            p95 = np.percentile(vals, 95)
            p99 = np.percentile(vals, 99)
            peak = vals.max()
            line = (f"  GPU {idx}  idle (0-1%) {idle_pct:.1f}%   "
                    f"low (1-25%) {low_pct:.1f}%   "
                    f"med (25-75%) {med_pct:.1f}%   "
                    f"high (75-100%) {high_pct:.1f}%")
            summary_lines.append(line)
            line = f"         p50 {p50:5.1f}%   p95 {p95:5.1f}%   p99 {p99:5.1f}%   max {peak:.0f}%"
            summary_lines.append(line)
            print(line)

    # --- GPU power/temp ---
    if gpu is not None and len(gpu):
        summary_lines.append("")
        summary_lines.append("GPU power:")
        for idx, sub in gpu.groupby("index"):
            if "power_w" not in sub.columns:
                continue
            pw = sub["power_w"].dropna()
            if len(pw) == 0:
                continue
            peak_w = pw.max()
            avg_w = pw.mean()
            kwh = avg_w * wall / 3600 / 1000
            line = f"  GPU {idx}  peak {peak_w:.0f}W   avg {avg_w:.1f}W   total ~{kwh:.3f} kWh"
            summary_lines.append(line)
        summary_lines.append("GPU temp:")
        for idx, sub in gpu.groupby("index"):
            if "temp_c" not in sub.columns:
                continue
            tmp = sub["temp_c"].dropna()
            if len(tmp) == 0:
                continue
            peak_c = tmp.max()
            avg_c = tmp.mean()
            line = f"  GPU {idx}  peak {peak_c:.0f}°C   avg {avg_c:.1f}°C"
            summary_lines.append(line)

    # --- GPU SM clock ---
    if gpu is not None and len(gpu) and "sm_clock_mhz" in gpu.columns:
        summary_lines.append("")
        summary_lines.append("GPU SM clock:")
        for idx, sub in gpu.groupby("index"):
            clk = sub["sm_clock_mhz"].dropna()
            if len(clk) == 0:
                continue
            base_clock = clk.min()
            boost_clock = clk.max()
            line = f"  GPU {idx}  base {base_clock:.0f} MHz   boost {boost_clock:.0f} MHz"
            summary_lines.append(line)

    # --- NVLink summary ---
    if nvlink is not None and len(nvlink):
        summary_lines.append("")
        nvlink["total_gibs"] = nvlink["tx_gibs"] + nvlink["rx_gibs"]
        num_gpus = nvlink["gpu"].nunique()
        total_links = 0
        peak_bw = nvlink["total_gibs"].max()
        avg_bw = nvlink["total_gibs"].mean()
        tag = "(single-GPU rental)" if num_gpus == 1 else ""
        line = f"NVLink aggregate ({num_gpus} GPU{'s' if num_gpus > 1 else ''}{', 18 links' if num_gpus == 1 else ''}):"
        summary_lines.append(line)
        line = f"  peak TX+RX  {peak_bw:.2f} GiB/s   avg  {avg_bw:.2f} GiB/s   {tag}"
        summary_lines.append(line)

    # --- Token throughput ---
    if vm is not None and len(vm) and "prompt_tokens" in vm.columns and "generation_tokens" in vm.columns:
        df = vm.sort_values("ts").reset_index(drop=True)
        # Forward-fill token counters so diffs work across scrapes where
        # the metric was absent (NaN rows). Back-fill any leading NaN (counters start at 0).
        df["prompt_tokens"] = df["prompt_tokens"].ffill().fillna(0)
        df["generation_tokens"] = df["generation_tokens"].ffill().fillna(0)
        dt = df["ts"].diff().dt.total_seconds()
        d_prompt = df["prompt_tokens"].diff().where(lambda x: x >= 0)
        d_gen = df["generation_tokens"].diff().where(lambda x: x >= 0)
        valid = dt > 0
        prompt_tps = d_prompt[valid] / dt[valid]
        gen_tps = d_gen[valid] / dt[valid]
        total_prompt = d_prompt.sum()
        total_gen = d_gen.sum()
        if total_prompt > 0 or total_gen > 0:
            summary_lines.append("")
            summary_lines.append("Token throughput (vLLM, inter-scrape deltas):")
            line = f"  prompt    total {total_prompt:,.0f}   avg {prompt_tps.mean():,.0f} tok/s   peak {prompt_tps.max():,.0f} tok/s"
            summary_lines.append(line)
            line = f"  gen       total {total_gen:,.0f}   avg {gen_tps.mean():,.0f} tok/s   peak {gen_tps.max():,.0f} tok/s"
            summary_lines.append(line)

    # --- vLLM latencies ---
    if histograms:
        summary_lines.append("")
        summary_lines.append("vLLM latencies (from Prometheus histograms):")
        labels = {"ttft": "TTFT", "itl": "ITL", "e2e_latency": "E2E",
                  "queue_time": "queue", "prefill_time": "prefill",
                  "decode_time": "decode"}
        order = ["ttft", "itl", "e2e_latency", "queue_time", "prefill_time", "decode_time"]
        req_count = histograms.get("ttft", {}).get("count") or histograms.get("e2e_latency", {}).get("count", 0)
        header = f"  {'':>10s}  {'p50':>8s}  {'p95':>8s}  {'p99':>8s}  {'avg':>8s}"
        summary_lines.append(header)
        for key in order:
            h = histograms.get(key)
            if not h:
                continue
            lbl = labels.get(key, key)
            summary_lines.append(
                f"  {lbl:>10s}  {fmt_sec(h['p50']):>8s}  {fmt_sec(h['p95']):>8s}  "
                f"{fmt_sec(h['p99']):>8s}  {fmt_sec(h['avg']):>8s}"
            )
        summary_lines.append(f"  (based on N={req_count} requests)")

    # --- Prefix cache ---
    if vm is not None and len(vm) and "prefix_cache_hits" in vm.columns and "prefix_cache_queries" in vm.columns:
        hits = vm["prefix_cache_hits"].diff().where(lambda x: x >= 0).sum()
        queries_total = vm["prefix_cache_queries"].diff().where(lambda x: x >= 0).sum()
        if queries_total > 0:
            hit_rate = hits / queries_total * 100
            summary_lines.append("")
            summary_lines.append("Prefix cache (vLLM):")
            summary_lines.append(f"  hit rate  {hit_rate:.1f}%  ({hits:,.0f} / {queries_total:,.0f} tokens)")

    # --- Peak running/waiting ---
    if vm is not None and len(vm):
        peak_run = vm["num_requests_running"].max() if "num_requests_running" in vm.columns else 0
        peak_wait = vm["num_requests_waiting"].max() if "num_requests_waiting" in vm.columns else 0
        if peak_run > 0 or peak_wait > 0:
            summary_lines.append("")
            summary_lines.append(f"Requests (vLLM, peak over session):")
            summary_lines.append(f"  running  {peak_run:.0f}   waiting  {peak_wait:.0f}")

    # --- Queries block ---
    if queries:
        summary_lines.append("")
        summary_lines.append("Queries (client-side, from queries.jsonl):")
        total_q = len(queries)
        succ = sum(1 for q in queries if 200 <= q["status"] < 400)
        err4 = sum(1 for q in queries if 400 <= q["status"] < 500)
        err5 = sum(1 for q in queries if q["status"] >= 500)
        summary_lines.append(f"  total: {total_q}  (success {succ} / 4xx {err4} / 5xx {err5})")
        durations = [q["duration_ms"] for q in queries]
        summary_lines.append(
            f"  duration ms      p50 {np.percentile(durations, 50):,.0f}   "
            f"p95 {np.percentile(durations, 95):,.0f}   "
            f"p99 {np.percentile(durations, 99):,.0f}   "
            f"max {max(durations):,.0f}"
        )
        # Per-endpoint breakdown
        endpoints = {}
        for q in queries:
            ep = q["endpoint"] or "/"
            endpoints.setdefault(ep, []).append(q["duration_ms"])
        summary_lines.append("  per endpoint:")
        for ep, durs in sorted(endpoints.items(), key=lambda x: -len(x[1])):
            summary_lines.append(
                f"    {ep:<30s} {len(durs):>4d}  p50 {np.percentile(durs, 50):,.0f}ms  "
                f"p95 {np.percentile(durs, 95):,.0f}ms"
            )
        # Token usage
        q_with_usage = [q for q in queries if q["usage"]]
        if q_with_usage:
            total_prompt = sum(u.get("prompt_tokens", 0) or 0 for u in (q["usage"] for q in q_with_usage))
            total_completion = sum(u.get("completion_tokens", 0) or 0 for u in (q["usage"] for q in q_with_usage))
            total_tok = total_prompt + total_completion
            avg_tok = total_tok / len(q_with_usage)
            total_dur_s = sum(q["duration_ms"] for q in q_with_usage) / 1000
            avg_tok_s = total_completion / total_dur_s if total_dur_s > 0 else 0
            summary_lines.append(
                f"  tokens (usage seen on {len(q_with_usage)}/{total_q}):"
            )
            summary_lines.append(
                f"    prompt       {total_prompt:>12,}    completion {total_completion:>12,}    "
                f"total {total_tok:>12,}"
            )
            summary_lines.append(
                f"    avg per req  {avg_tok:>12,.0f}        "
                f"avg tok/s (decode) {avg_tok_s:,.0f}"
            )
            # Cost
            if rental and rental.get("dph_total"):
                dph = float(rental["dph_total"])
                wall_h = wall / 3600
                rental_cost = dph * wall_h
                summary_lines.append(
                    f"  cost (rental dph_total = ${dph:.4f}, wall = {wall_h:.1f}h):"
                )
                summary_lines.append(f"    rental cost  ${rental_cost:.2f}")
                if total_tok > 0:
                    cost_per_mtok = rental_cost / (total_tok / 1_000_000)
                    summary_lines.append(f"    $/Mtok       ${cost_per_mtok:.4f}   (total tokens basis)")
                if total_completion > 0:
                    cost_per_mtok_out = rental_cost / (total_completion / 1_000_000)
                    summary_lines.append(f"    $/Mtok-out   ${cost_per_mtok_out:.4f}   (completion tokens basis)")
            elif rental is not None:
                summary_lines.append("  cost: rental.json is missing dph_total")
            else:
                summary_lines.append("  cost: rental.json not found")
        else:
            summary_lines.append("  tokens: no usage data captured")

    summary_lines.append("")
    summary_lines.append("Events:")
    for e in all_events[:200]:
        summary_lines.append(f"  {e['ts']:%Y-%m-%d %H:%M:%S}  {e['type']:<22}  {e.get('message', '')[:80]}")
    if len(all_events) > 200:
        summary_lines.append(f"  ... +{len(all_events) - 200} more")
    (base / "summary.txt").write_text("\n".join(summary_lines) + "\n")

    print()
    if pngs:
        print(f"  PNGs in {base}/:  " + "  ".join(pngs))
    print(f"  summary.txt: {base / 'summary.txt'}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
