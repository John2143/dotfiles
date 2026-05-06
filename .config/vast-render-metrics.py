#!/usr/bin/env python3
"""Render PNG graphs + a terminal summary from a vast-destroy metrics dir.

Usage: vast-render-metrics PATH

PATH is the per-rental directory written by vast-destroy. Expected layout:
    PATH/metrics/{gpu,sys,gpu_proc}.csv
    PATH/metrics/{pmon,nvlink}.log
    PATH/metrics/vllm.prom
    PATH/metrics/events.jsonl
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
            cur_ts = pd.to_datetime(line[4:].strip(), utc=True, errors="coerce")
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


def fmt_xaxis(ax):
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M", tz=timezone.utc))


def render_gpu(gpu, events, base):
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


def render_vllm(vm, events, base):
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
        pngs += render_gpu(gpu, all_events, base)
    if sysd is not None and len(sysd):
        pngs += render_sys(sysd, base)
    vm = parse_vllm_prom(mdir / "vllm.prom")
    if vm is not None and len(vm):
        pngs += render_vllm(vm, all_events, base)

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
