#!/usr/bin/env bash
# Runs on the rented Vast.ai instance via `ssh ... bash -s`. The caller
# (vast-bootstrap fish function in nixos/home-cli.nix) sets these env vars
# from /run/agenix/vast-credentials + ~/.config/vast/profile + defaults:
#
#   ENGINE             inference engine: "sglang" (default) or "vllm"
#                        SGLang recommended for DeepSeek V4 — zero CJK token
#                        injection vs vLLM's 50-75% rate (vllm#41985 unfixed).
#                        vLLM kept for A/B comparison and non-DS models.
#   MODEL              HF model id (required)
#   SERVED             served-model-name exposed on the OpenAI API (default deepseek-v4-flash)
#   SERVE_PORT         listen port inside the rental (default 8000)
#                        Replaces VLLM_PORT (still accepted for backward compat).
#   MAX_LEN            context length ("auto" → tuned per GPU count, see below)
#                        vLLM: --max-model-len; SGLang: --context-length
#   MEM_UTIL           GPU memory fraction ("auto" → tuned per GPU count)
#                        vLLM: --gpu-memory-utilization; SGLang: --mem-fraction-static
#   MAX_NUM_SEQS       max concurrent sequences ("auto" → tuned per GPU count)
#                        vLLM: --max-num-seqs; SGLang: --max-running-requests
#   HF_TOKEN           HuggingFace token (optional but strongly recommended:
#                      faster downloads, higher rate limits, gated models)
#   TOOL_PARSER        --tool-call-parser (vLLM only; SGLang auto-handles DSv4)
#   REASONING_PARSER   --reasoning-parser (vLLM only; SGLang auto-handles DSv4)
#   EXTRA_ARGS         space-separated engine-specific extra flags (optional)
#   FORCE_RESTART      if non-empty, kill any running server and re-launch
#                      (otherwise the script is a no-op when the server is up)
#   TENSOR_PARALLEL    tensor parallelism (auto-detected = GPU count;
#                      set to 1 to disable on multi-GPU instances)
#   LOGGING_PROXY      "1" (default) → run a Python reverse proxy in front
#                      of the engine that appends every OpenAI request+response
#                      to /workspace/metrics/queries.jsonl. "0" → engine binds
#                      SERVE_PORT directly (legacy). When enabled, engine binds
#                      127.0.0.1:SERVE_INTERNAL_PORT and the proxy listens on
#                      0.0.0.0:SERVE_PORT, so external clients are unchanged.
#   SERVE_INTERNAL_PORT private port engine binds to under LOGGING_PROXY=1
#                      (default 18000). Ignored otherwise.
#
# Auto-tuning targets DeepSeek-V4-Flash with 1-2 light users (rare concurrent
# big queries). V4-Flash KV at 1M ctx is only ~6 GiB/seq (7% of V3.2's, via
# CSA+HCA), so the binding constraint is the ~150 GB weight footprint, not KV:
#
#   1 GPU  (B200, 192 GB):  MAX_LEN=524288  MEM_UTIL=0.93 MAX_NUM_SEQS=16
#                           (weights eat ~80% VRAM; tighter MEM_UTIL avoids
#                           OOM during graph capture; max-prefill-tokens capped
#                           at 8192 to bound prefill activation spikes)
#   2 GPUs (2×B200, 384):   MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=32
#   4 GPUs (4×B200, 768):   MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=64
#   8 GPUs (8×B200, 1536):  MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=128
#
# DeepSeek-V4-Pro is the large MoE variant: 1.6T total / 49B activated.
# Native quantization (FP4 experts + FP8 other) puts weights at ~865 GB on
# disk, so 4×B200 (768 GB VRAM) CANNOT load it — 8×B200 (1536 GB) is the
# realistic minimum. When MODEL matches *DeepSeek-V4-Pro* we override:
#
#   8 GPUs (8×B200, 1536):  MAX_LEN=524288 MEM_UTIL=0.94 MAX_NUM_SEQS=32
#                           (~865 GB weights leaves ~580 GB for KV+activations)
#
# Topology choice: TP+EP (each request uses all GPUs). SGLang on DSv4 produces
# zero CJK bad tokens vs vLLM's 50-75% (vllm#41985); no sampling overrides
# needed. When ENGINE=vllm, DeepSeek V4 gets temp=0.6/top_p=0.95/top_k=40 as
# a workaround for the MLA Attention FP8 precision bug.
#
# Idempotent: if a server is already responding on $SERVE_PORT it exits 0
# unless FORCE_RESTART is set.
# Logs go to /workspace/<engine>.log; pid goes to /workspace/<engine>.pid.
#
# Recommended rental image: nvidia/cuda:12.8.0-devel-ubuntu24.04 (clean CUDA,
# no auto-launched services). Script installs python3 + venv + the engine if
# missing. The venv lives at /workspace/venv and persists across reboots.
set -euo pipefail

: "${ENGINE:=sglang}"
: "${MODEL:?missing MODEL}"
: "${SERVED:=deepseek-v4-flash}"
# SERVE_PORT is the canonical name; VLLM_PORT still accepted for backward compat.
: "${SERVE_PORT:=${VLLM_PORT:-8000}}"
: "${MAX_LEN:=auto}"
: "${MEM_UTIL:=auto}"
: "${MAX_NUM_SEQS:=auto}"
: "${HF_TOKEN:=}"
: "${TOOL_PARSER:=}"
: "${REASONING_PARSER:=}"
: "${EXTRA_ARGS:=}"
: "${FORCE_RESTART:=}"
: "${TENSOR_PARALLEL:=}"
: "${MAX_NUM_BATCHED_TOKENS:=8192}"
# Engine slug used for log/pid file naming and process matching.
readonly ENGINE_SLUG="$ENGINE"
: "${LOGGING_PROXY:=1}"
: "${SERVE_INTERNAL_PORT:=${VLLM_INTERNAL_PORT:-18000}}"

mkdir -p /workspace /workspace/tmp /workspace/pip-cache /workspace/.hf_home \
         /workspace/.vllm_cache /workspace/.triton_cache /workspace/.inductor_cache \
         /workspace/.sglang_cache /workspace/metrics
cd /workspace

# Append a structured lifecycle event to /workspace/metrics/events.jsonl.
# Render-time graphs use these to draw vertical markers at "vllm_launch",
# "vllm_ready", etc. — anchored to absolute UTC timestamps so they line up
# with gpu.csv / sys.csv. Keeping this in bootstrap (not the monitor) is
# deliberate: bootstrap controls the lifecycle; the monitor just samples.
emit_event() {
  local type="$1" msg="${2:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  msg="${msg//$'\n'/\\n}"
  msg="${msg//$'\r'/\\r}"
  msg="${msg//$'\t'/\\t}"
  printf '{"ts":"%s","type":"%s","message":"%s","engine":"%s"}\n' \
    "$ts" "$type" "$msg" "$ENGINE_SLUG" \
    >> /workspace/metrics/events.jsonl
}
emit_event bootstrap_start "model=${MODEL} served=${SERVED} port=${SERVE_PORT}"

# Vast.ai's vLLM-flavored templates put a 32 GB overlay on / while the real
# storage lives at /workspace (terabytes). HF Hub's default temp paths spill
# onto / and fill it up mid-download, which surfaces as
# "Background writer channel closed" from hf-xet. Pin everything to /workspace.
export TMPDIR=/workspace/tmp
export HF_HOME="${HF_HOME:-/workspace/.hf_home}"
export PIP_CACHE_DIR=/workspace/pip-cache
# hf-xet's parallel writer is the source of the channel-closed errors on
# Vast.ai overlays; the legacy resumable downloader is slower but reliable.
export HF_HUB_DISABLE_XET=1
export HF_HUB_ENABLE_HF_TRANSFER=0

# Pin vLLM/Triton/Torch JIT caches to /workspace so they survive instance
# pause/unpause cycles. Without these, each cold start spends 1-3 min
# recompiling Triton helper kernels, capturing torch.compile graphs, and
# rebuilding inductor artifacts — even though weights and venv are already
# warm. Persisting these brings warm-start time from ~90s to ~10-15s on
# pause/unpause of the same instance.
#
# Note: these only help on the SAME instance. A fresh rental (new
# instance id) starts with empty /workspace and rebuilds them once. To
# also share across rentals, push them to RustFS post-bootstrap — left as
# future work; the JIT artifacts are GPU-arch specific (Blackwell vs
# Hopper) so the cache is only valid for matching GPU SKU rentals.
export VLLM_CACHE_ROOT=/workspace/.vllm_cache
export TRITON_CACHE_DIR=/workspace/.triton_cache
export TORCHINDUCTOR_CACHE_DIR=/workspace/.inductor_cache

# Clear /tmp on the overlay if it's >50% full so existing junk doesn't
# bottleneck a fresh download.
if [ "$(df --output=pcent / | tail -1 | tr -dc 0-9)" -gt 50 ]; then
  rm -rf /tmp/* /tmp/.[!.]* 2>/dev/null || true
fi

# Vast.ai's "vLLM …" / "SGLang …" templates auto-launch via supervisord,
# which holds the entire GPU before our serve command runs. Stop it cleanly
# if present (no-op on bare cuda/pytorch images).
if command -v supervisorctl >/dev/null 2>&1; then
  if supervisorctl status vllm 2>/dev/null | grep -q RUNNING; then
    echo "Stopping supervisord-managed vllm to free the GPU ..."
    supervisorctl stop vllm || true
    sleep 3
  fi
  if supervisorctl status sglang 2>/dev/null | grep -q RUNNING; then
    echo "Stopping supervisord-managed sglang to free the GPU ..."
    supervisorctl stop sglang || true
    sleep 3
  fi
fi
# Belt-and-suspenders: kill any orphan engine processes.
# For vLLM: 'vllm serve' + forked EngineCore children.
# For SGLang: 'sglang.launch_server' + sglang worker processes.
# The metrics monitor has neither substring, so it is unaffected.
# The proxy is killed separately.
if [ "$ENGINE_SLUG" = "vllm" ]; then
  pkill -f 'vllm' 2>/dev/null || true
elif [ "$ENGINE_SLUG" = "sglang" ]; then
  pkill -f 'sglang' 2>/dev/null || true
fi
# Always kill the other engine too (stale from a previous ENGINE= switch).
pkill -f 'vllm serve' 2>/dev/null || true
pkill -f 'sglang.launch_server' 2>/dev/null || true

# True iff EXTRA_ARGS already contains the named flag (whole-word, so
# --tool-call-parser doesn't match --tool-call-parser-foo). Used to suppress
# auto-defaults whenever the caller has overridden them via VAST_EXTRA_ARGS,
# avoiding duplicate-flag arguments to vllm.
has_extra_flag() {
  printf '%s\n' "$EXTRA_ARGS" | grep -qE -- "(^|[[:space:]])$1([[:space:]]|=|\$)"
}

# vLLM-specific DeepSeek V4 workarounds. SGLang needs none of these —
# its MLA attention implementation has correct FP8 precision (zero CJK
# bad tokens vs vLLM's 50-75% at temp=1.0/top_p=1.0, per vllm#41985).
if [ "$ENGINE_SLUG" = "vllm" ]; then
  case "$MODEL" in
    *DeepSeek-V4*|*deepseek-v4*)
      if ! has_extra_flag --kv-cache-dtype; then
        echo "Auto-setting --kv-cache-dtype fp8 for DeepSeek V4 (vLLM)."
        EXTRA_ARGS="--kv-cache-dtype fp8 ${EXTRA_ARGS}"
      fi
      # Sampling override for vllm#41985 (CJK token injection) +
      # repetition collapse. Drop when vllm#41985 closes. See header.
      if ! has_extra_flag --override-generation-config; then
        echo "Auto-overriding sampling: temp=0.6 top_p=0.95 top_k=40 (vllm#41985 + repetition collapse)."
        EXTRA_ARGS="--override-generation-config {\"temperature\":0.6,\"top_p\":0.95,\"top_k\":40} ${EXTRA_ARGS}"
      fi
      if [ -z "$TOOL_PARSER" ] && ! has_extra_flag --tool-call-parser; then
        echo "Auto-setting --tool-call-parser deepseek_v4 for DeepSeek V4 (vLLM)."
        TOOL_PARSER=deepseek_v4
      fi
      if [ -z "$REASONING_PARSER" ] && ! has_extra_flag --reasoning-parser; then
        echo "Auto-setting --reasoning-parser deepseek_v4 for DeepSeek V4 (vLLM)."
        REASONING_PARSER=deepseek_v4
      fi
      ;;
  esac
else
  echo "ENGINE=sglang: no DeepSeek V4 workarounds needed (MLA attention precision is correct)."
fi

# Background sampler: nvidia-smi GPU stats + vLLM /metrics scrape, every 5s,
# appended to /workspace/metrics/. vast-destroy scp's this directory down
# before terminating the rental, giving you a per-session record of GPU
# utilization, KV-cache occupancy, request latency, etc.
#
# Idempotent: pid file at /workspace/metrics/monitor.pid. If the recorded
# PID is alive we leave it alone — running this on `vast-bootstrap --restart`
# preserves continuous metrics across vLLM relaunches.
start_monitor_if_needed() {
  mkdir -p /workspace/metrics
  local pidfile=/workspace/metrics/monitor.pid
  if [ -f "$pidfile" ]; then
    local oldpid
    oldpid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      echo "Metrics monitor already running (pid $oldpid) — leaving as-is."
      return 0
    fi
  fi
  cat > /workspace/metrics-monitor.sh <<'MONEOF'
#!/usr/bin/env bash
# Polls nvidia-smi + vLLM /metrics + system stats every $1 seconds.
# Started by vast-bootstrap via nohup; outputs append-only.
#
# Files written under /workspace/metrics/:
#   gpu.csv       - per-GPU util/mem/power/temp/sm_clock
#   sys.csv       - cpu%, mem, load1, disk%, net rx/tx, disk r/w (delta-rate)
#   gpu_proc.csv  - per-PID GPU memory (compute-apps)
#   pmon.log      - raw `nvidia-smi pmon` snapshots, # T=<iso> separators
#   nvlink.log    - raw `nvidia-smi nvlink -gt d` snapshots, # T=<iso> seps
#   vllm.prom     - raw Prometheus /metrics scrape, # T=<iso> separators
set -u
INTERVAL="${1:-5}"
PORT="${2:-8000}"
DIR=/workspace/metrics
mkdir -p "$DIR"
GPU_CSV="$DIR/gpu.csv"
SYS_CSV="$DIR/sys.csv"
GPROC_CSV="$DIR/gpu_proc.csv"
PMON_LOG="$DIR/pmon.log"
NVLINK_LOG="$DIR/nvlink.log"
VLLM_OUT="$DIR/vllm.prom"

if [ ! -s "$GPU_CSV" ]; then
  echo "timestamp,index,util_gpu_pct,util_mem_pct,mem_used_mib,mem_total_mib,power_w,temp_c,sm_clock_mhz" > "$GPU_CSV"
fi
if [ ! -s "$SYS_CSV" ]; then
  echo "timestamp,cpu_pct,mem_used_gib,mem_total_gib,load1,disk_root_pct,disk_workspace_pct,net_rx_mibps,net_tx_mibps,disk_read_mibps,disk_write_mibps" > "$SYS_CSV"
fi
if [ ! -s "$GPROC_CSV" ]; then
  # process_name is intentionally omitted: nvidia-smi --format=csv does not
  # quote embedded commas (e.g. "python /workspace/venv/bin/vllm serve, x"),
  # which corrupts row shape downstream. pid + gpu_uuid uniquely identify
  # the process if a future reader needs the name.
  echo "timestamp,pid,gpu_uuid,used_memory_mib" > "$GPROC_CSV"
fi

# Default route's interface is the one HF downloads land on.
NET_IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')
[ -z "$NET_IFACE" ] && NET_IFACE=eth0

# Delta-tracking state (CPU jiffies, network bytes, disk sectors). Empty
# until the first iteration completes; sys.csv writes start on iteration 2.
PREV_CPU_TOTAL=
PREV_CPU_IDLE=
PREV_RX=
PREV_TX=
PREV_RD=
PREV_WR=
PREV_T=

read_cpu() {
  # /proc/stat first line: cpu user nice system idle iowait irq softirq steal
  local _ u n s i io ir si st rest
  read -r _ u n s i io ir si st rest < /proc/stat
  printf '%s %s\n' "$((u+n+s+i+io+ir+si+st))" "$((i+io))"
}
read_net() {
  awk -v ifc="$NET_IFACE" '$1 ~ "^"ifc":" {gsub(":", " "); print $2, $10}' /proc/net/dev
}
read_dio() {
  # Sum read sectors (col 6) + written sectors (col 10) across real block
  # devices (skip loop/ram/dm-).
  awk '$3 !~ /^(loop|ram|dm-)/ {r+=$6; w+=$10} END {printf "%d %d\n", r, w}' /proc/diskstats
}

while true; do
  NOW_S=$(date +%s)
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  nvidia-smi \
    --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu,clocks.current.sm \
    --format=csv,noheader,nounits >> "$GPU_CSV" 2>/dev/null || true

  nvidia-smi \
    --query-compute-apps=timestamp,pid,gpu_uuid,used_memory \
    --format=csv,noheader,nounits >> "$GPROC_CSV" 2>/dev/null || true

  printf '# T=%s\n' "$TS" >> "$PMON_LOG"
  timeout 3 nvidia-smi pmon -c 1 -s pucvmet >> "$PMON_LOG" 2>/dev/null || true

  printf '# T=%s\n' "$TS" >> "$NVLINK_LOG"
  timeout 3 nvidia-smi nvlink -gt d >> "$NVLINK_LOG" 2>/dev/null || true

  # System CSV — needs a previous sample for rate math.
  read CPU_TOTAL CPU_IDLE < <(read_cpu)
  read RX TX < <(read_net)
  read RD WR < <(read_dio)

  if [ -n "$PREV_T" ] && [ "$NOW_S" -gt "$PREV_T" ]; then
    DT=$((NOW_S - PREV_T))
    DCPU_TOTAL=$((CPU_TOTAL - PREV_CPU_TOTAL))
    DCPU_IDLE=$((CPU_IDLE - PREV_CPU_IDLE))
    if [ "$DCPU_TOTAL" -gt 0 ]; then
      CPU_PCT=$(awk -v dt="$DCPU_TOTAL" -v di="$DCPU_IDLE" 'BEGIN{printf "%.1f", (1 - di/dt)*100}')
    else
      CPU_PCT=0
    fi
    DRX=$((RX - PREV_RX))
    DTX=$((TX - PREV_TX))
    DRD=$((RD - PREV_RD))
    DWR=$((WR - PREV_WR))
    NET_RX=$(awk -v b="$DRX" -v dt="$DT" 'BEGIN{printf "%.2f", b/dt/1048576}')
    NET_TX=$(awk -v b="$DTX" -v dt="$DT" 'BEGIN{printf "%.2f", b/dt/1048576}')
    # /proc/diskstats reports 512-byte sectors.
    DIO_R=$(awk -v s="$DRD" -v dt="$DT" 'BEGIN{printf "%.2f", s*512/dt/1048576}')
    DIO_W=$(awk -v s="$DWR" -v dt="$DT" 'BEGIN{printf "%.2f", s*512/dt/1048576}')

    MEM_USED=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.2f", (t-a)/1048576}' /proc/meminfo)
    MEM_TOTAL=$(awk '/^MemTotal:/{printf "%.2f", $2/1048576}' /proc/meminfo)
    LOAD1=$(awk '{print $1}' /proc/loadavg)
    DISK_ROOT=$(df --output=pcent / 2>/dev/null | awk 'NR==2 {gsub("%",""); print $1+0}')
    DISK_WS=$(df --output=pcent /workspace 2>/dev/null | awk 'NR==2 {gsub("%",""); print $1+0}')

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$TS" "$CPU_PCT" "$MEM_USED" "$MEM_TOTAL" "$LOAD1" \
      "$DISK_ROOT" "$DISK_WS" "$NET_RX" "$NET_TX" \
      "$DIO_R" "$DIO_W" >> "$SYS_CSV"
  fi

  PREV_CPU_TOTAL=$CPU_TOTAL
  PREV_CPU_IDLE=$CPU_IDLE
  PREV_RX=$RX
  PREV_TX=$TX
  PREV_RD=$RD
  PREV_WR=$WR
  PREV_T=$NOW_S

  printf '# T=%s\n' "$TS" >> "$VLLM_OUT"
  curl -fsS --max-time 2 "http://localhost:${PORT}/metrics" >> "$VLLM_OUT" 2>/dev/null || true

  sleep "$INTERVAL"
done
MONEOF
  chmod +x /workspace/metrics-monitor.sh
  nohup bash /workspace/metrics-monitor.sh 5 "${SERVE_PORT}" \
    >>/workspace/metrics/monitor.log 2>&1 &
  echo "$!" > "$pidfile"
  disown 2>/dev/null || true
  echo "Started metrics monitor (pid $(cat "$pidfile"), 5s cadence → /workspace/metrics/)."
  emit_event monitor_start "pid=$(cat "$pidfile")"
}

# Logging proxy: tiny Python reverse proxy that records every OpenAI-style
# request + response to /workspace/metrics/queries.jsonl. Engine binds to
# 127.0.0.1:${SERVE_INTERNAL_PORT}; the proxy listens on 0.0.0.0:${SERVE_PORT}
# and forwards transparently. High-frequency monitoring endpoints (/metrics,
# /health, /v1/models) pass through without logging so the JSONL stays
# signal-only. Idempotent via /workspace/proxy.pid.
start_logging_proxy_if_needed() {
  [ "$LOGGING_PROXY" = "1" ] || return 0
  mkdir -p /workspace/metrics
  local pidfile=/workspace/proxy.pid
  if [ -f "$pidfile" ]; then
    local oldpid
    oldpid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      echo "Logging proxy already running (pid $oldpid) — leaving as-is."
      return 0
    fi
  fi

  # httpx isn't always pulled in by the engine directly; install on demand.
  if ! /workspace/venv/bin/python -c 'import httpx, fastapi, uvicorn' >/dev/null 2>&1; then
    echo "Installing logging-proxy deps (httpx) into /workspace/venv ..."
    /workspace/venv/bin/pip install --quiet httpx fastapi uvicorn || {
      echo "Warning: failed to install proxy deps — skipping logging proxy." >&2
      return 0
    }
  fi

  cat > /workspace/logging-proxy.py <<'PROXYEOF'
#!/usr/bin/env python3
"""Reverse proxy that logs every OpenAI-style request/response to JSONL.

Started by vast-bootstrap when LOGGING_PROXY=1. Listens on $PROXY_PORT and
forwards to http://127.0.0.1:$UPSTREAM_PORT. For paths in LOG_PATHS, the full
request body and response body (or assembled SSE deltas) are appended to
$LOG_FILE as one JSON record per line. Other paths pass through silently.

Auth headers are preserved on the wire to upstream but redacted in the log.
"""
import asyncio
import json
import os
import time
import uuid
from contextlib import asynccontextmanager

import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import Response, StreamingResponse

PROXY_PORT    = int(os.environ.get("PROXY_PORT", "8000"))
UPSTREAM_PORT = int(os.environ.get("UPSTREAM_PORT", "18000"))
LOG_FILE      = os.environ.get("LOG_FILE", "/workspace/metrics/queries.jsonl")
UPSTREAM      = f"http://127.0.0.1:{UPSTREAM_PORT}"

# Bodies of these paths land in the log. /metrics, /health, /v1/models are
# scraped every 5s by metrics-monitor.sh — excluding them keeps the log
# focused on actual user traffic.
LOG_PATHS = {
    "/v1/chat/completions",
    "/v1/completions",
    "/v1/embeddings",
    "/v1/responses",
    "/v1/rerank",
    "/v1/score",
    "/tokenize",
    "/v1/audio/transcriptions",
}

# Hop-by-hop headers per RFC 7230 + Host (we are the host) + Content-Length
# (httpx recomputes from the body it sees). Stripping these prevents httpx
# from rejecting/duplicating them on the upstream request.
HOP_BY_HOP = {"connection", "keep-alive", "transfer-encoding", "te",
              "trailer", "proxy-authorization", "proxy-authenticate",
              "upgrade", "host", "content-length"}
SECRET_HEADERS = {"authorization", "x-api-key", "cookie",
                  "proxy-authorization", "openai-api-key"}


def _filter(headers):
    return [(k, v) for k, v in headers.items() if k.lower() not in HOP_BY_HOP]


def _redact(headers):
    return {k: ("[redacted]" if k.lower() in SECRET_HEADERS else v)
            for k, v in headers.items()}


_log_lock = asyncio.Lock()


def _append(line):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line)


async def _write_log(record):
    line = json.dumps(record, ensure_ascii=False, default=str) + "\n"
    async with _log_lock:
        await asyncio.to_thread(_append, line)


@asynccontextmanager
async def lifespan(app):
    # read=None: long completions on V4-Pro can stream for >10 min; a fixed
    # read timeout would sever them mid-token.
    timeout = httpx.Timeout(connect=5.0, read=None, write=60.0, pool=5.0)
    limits = httpx.Limits(max_connections=256)
    app.state.client = httpx.AsyncClient(base_url=UPSTREAM, timeout=timeout,
                                          limits=limits)
    try:
        yield
    finally:
        await app.state.client.aclose()


app = FastAPI(lifespan=lifespan)


@app.api_route("/{path:path}",
               methods=["GET", "POST", "PUT", "DELETE", "PATCH",
                        "OPTIONS", "HEAD"])
async def proxy(path: str, request: Request):
    body = await request.body()
    target = "/" + path
    if request.url.query:
        target = f"{target}?{request.url.query}"
    headers = _filter(request.headers)
    full_path = "/" + path
    client: httpx.AsyncClient = request.app.state.client

    if full_path not in LOG_PATHS:
        upstream = await client.request(request.method, target,
                                         content=body, headers=headers)
        return Response(content=upstream.content,
                        status_code=upstream.status_code,
                        headers=dict(_filter(upstream.headers)))

    started = time.time()
    request_id = uuid.uuid4().hex[:16]
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    try:
        req_json = json.loads(body.decode("utf-8")) if body else None
    except Exception:
        req_json = {"_raw": body.decode("utf-8", errors="replace")}

    is_stream = isinstance(req_json, dict) and req_json.get("stream") is True

    if not is_stream:
        upstream = await client.request(request.method, target,
                                         content=body, headers=headers)
        elapsed_ms = round((time.time() - started) * 1000, 1)
        try:
            resp_json = json.loads(upstream.content.decode("utf-8"))
        except Exception:
            resp_json = {"_raw": upstream.content.decode("utf-8", errors="replace")}
        await _write_log({
            "ts": ts,
            "request_id": request_id,
            "path": full_path,
            "method": request.method,
            "duration_ms": elapsed_ms,
            "status": upstream.status_code,
            "stream": False,
            "request_headers": _redact(request.headers),
            "request": req_json,
            "response": resp_json,
        })
        return Response(content=upstream.content,
                        status_code=upstream.status_code,
                        headers=dict(_filter(upstream.headers)))

    # Streaming path: forward bytes to client unmodified, accumulate for the
    # log record after the upstream stream closes.
    req = client.build_request(request.method, target,
                                content=body, headers=headers)
    upstream = await client.send(req, stream=True)
    chunks = []

    async def streamer():
        try:
            async for chunk in upstream.aiter_raw():
                chunks.append(chunk)
                yield chunk
        finally:
            await upstream.aclose()
            elapsed_ms = round((time.time() - started) * 1000, 1)
            raw = b"".join(chunks).decode("utf-8", errors="replace")
            events = []
            # OpenAI SSE: lines beginning with "data: ", terminated by [DONE].
            # We don't try to merge deltas here — the raw event stream is the
            # most faithful record and downstream tools can re-assemble.
            for line in raw.split("\n"):
                line = line.strip()
                if line.startswith("data:"):
                    payload = line[5:].strip()
                    if payload and payload != "[DONE]":
                        try:
                            events.append(json.loads(payload))
                        except Exception:
                            events.append({"_raw": payload})
            await _write_log({
                "ts": ts,
                "request_id": request_id,
                "path": full_path,
                "method": request.method,
                "duration_ms": elapsed_ms,
                "status": upstream.status_code,
                "stream": True,
                "request_headers": _redact(request.headers),
                "request": req_json,
                "response_events": events,
            })

    return StreamingResponse(streamer(),
                              status_code=upstream.status_code,
                              headers=dict(_filter(upstream.headers)),
                              media_type=upstream.headers.get("content-type"))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PROXY_PORT,
                log_level="warning", access_log=False)
PROXYEOF
  chmod +x /workspace/logging-proxy.py

  PROXY_PORT="${SERVE_PORT}" UPSTREAM_PORT="${SERVE_INTERNAL_PORT}" \
  LOG_FILE=/workspace/metrics/queries.jsonl \
  nohup /workspace/venv/bin/python /workspace/logging-proxy.py \
    >>/workspace/metrics/proxy.log 2>&1 &
  echo "$!" > "$pidfile"
  disown 2>/dev/null || true
  echo "Started logging proxy (pid $(cat "$pidfile"), :${SERVE_PORT} → :${SERVE_INTERNAL_PORT}, log → /workspace/metrics/queries.jsonl)."
  emit_event proxy_start "pid=$(cat "$pidfile") port=${SERVE_PORT} upstream=${SERVE_INTERNAL_PORT}"
}

# Probe the engine directly. With LOGGING_PROXY=1, the engine binds to a
# private internal port; probing $SERVE_PORT would also hit the proxy, but
# probing the internal port lets us tell engine-up-but-proxy-down apart
# from both-down.
PROBE_PORT="${SERVE_PORT}"
[ "$LOGGING_PROXY" = "1" ] && PROBE_PORT="${SERVE_INTERNAL_PORT}"

if curl -fsS "http://localhost:${PROBE_PORT}/v1/models" >/dev/null 2>&1; then
  if [ -z "${FORCE_RESTART}" ]; then
    emit_event early_exit_already_running ""
    echo "${ENGINE_SLUG} already responding on :${PROBE_PORT} — bootstrap is a no-op."
    echo "(Pass --restart to vast-bootstrap to force a re-launch with new flags.)"
    curl -s "http://localhost:${PROBE_PORT}/v1/models" | head -c 400
    echo
    start_monitor_if_needed
    start_logging_proxy_if_needed
    exit 0
  fi
  emit_event force_restart ""
  echo "FORCE_RESTART set — stopping running ${ENGINE_SLUG} to re-launch with new flags ..."
  pkill -f "${ENGINE_SLUG}" 2>/dev/null || true
  pkill -f 'vllm-logging-proxy.py' 2>/dev/null || true
  pkill -f 'logging-proxy.py' 2>/dev/null || true
  rm -f /workspace/proxy.pid
  for _ in $(seq 1 30); do
    curl -fsS "http://localhost:${PROBE_PORT}/v1/models" >/dev/null 2>&1 || break
    sleep 1
  done
fi

# Always ensure system build deps are present, regardless of whether the
# venv + vllm are already installed. Triton JIT-compiles helper kernels at
# vllm startup using gcc + Python.h every time, so these need to be there
# on every bootstrap, not just on the first install.
#   - python3 + venv module (Ubuntu 24.04 enforces PEP 668; system pip blocked)
#   - python3-dev (Python.h) for triton's JIT C compilation at vllm startup
#   - build-essential for the gcc/headers used by triton + DeepGEMM
# nvidia/cuda:*-devel ships CUDA + gcc but typically misses python3-dev
# and python3-venv. apt is idempotent — already-installed pkgs are no-ops.
NEED_APT=0
command -v python3 >/dev/null 2>&1 || NEED_APT=1
command -v gcc >/dev/null 2>&1 || NEED_APT=1
python3 -c 'import ensurepip, venv' >/dev/null 2>&1 || NEED_APT=1
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")
[ -n "$PYVER" ] && [ -e "/usr/include/python${PYVER}/Python.h" ] || NEED_APT=1
if [ "$NEED_APT" = 1 ]; then
  echo "Installing python3 + pip + venv + dev headers + build-essential via apt ..."
  emit_event apt_install_start ""
  APT_OK=
  for _ in 1 2 3; do
    if apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      python3 python3-pip python3-venv python3-dev \
      build-essential ca-certificates curl \
      moreutils gawk; then
      APT_OK=1
      break
    fi
    echo "apt attempt failed; waiting 5s before retry ..."
    sleep 5
  done
  if [ -z "${APT_OK}" ]; then
    emit_event apt_install_failed ""
    echo "apt failed after 3 attempts." >&2
    exit 1
  fi
  emit_event apt_install_done ""
fi

# Reuse a previously-created venv if it exists (subsequent bootstraps after
# the first are near-instant — model weights are also cached on /workspace).
if [ -x /workspace/venv/bin/python3 ]; then
  export PATH="/workspace/venv/bin:$PATH"
fi

if [ "$ENGINE_SLUG" = "vllm" ] && ! command -v vllm >/dev/null 2>&1; then
  echo "vllm CLI not found; bootstrapping venv + vllm ..."

  if [ -d /workspace/venv ] && { [ ! -x /workspace/venv/bin/python3 ] || [ ! -x /workspace/venv/bin/pip ]; }; then
    echo "Removing incomplete /workspace/venv from a previous failed attempt ..."
    rm -rf /workspace/venv
  fi

  if [ ! -d /workspace/venv ]; then
    echo "Creating venv at /workspace/venv ..."
    python3 -m venv /workspace/venv
  fi

  echo "pip install vllm into /workspace/venv (~5 min) ..."
  emit_event pip_install_start ""
  /workspace/venv/bin/pip install --quiet --upgrade pip
  /workspace/venv/bin/pip install --quiet vllm
  emit_event pip_install_done ""
  export PATH="/workspace/venv/bin:$PATH"
elif [ "$ENGINE_SLUG" = "sglang" ] && ! command -v sglang >/dev/null 2>&1; then
  echo "sglang CLI not found; bootstrapping venv + sglang ..."

  if [ -d /workspace/venv ] && { [ ! -x /workspace/venv/bin/python3 ] || [ ! -x /workspace/venv/bin/pip ]; }; then
    echo "Removing incomplete /workspace/venv from a previous failed attempt ..."
    rm -rf /workspace/venv
  fi

  if [ ! -d /workspace/venv ]; then
    echo "Creating venv at /workspace/venv ..."
    python3 -m venv /workspace/venv
  fi

  echo "pip install sglang[all] into /workspace/venv (~5 min) ..."
  emit_event pip_install_start ""
  /workspace/venv/bin/pip install --quiet --upgrade pip
  /workspace/venv/bin/pip install --quiet "sglang[all]"
  emit_event pip_install_done ""
  export PATH="/workspace/venv/bin:$PATH"
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "Warning: nvidia-smi not found inside the rental. ${ENGINE_SLUG} will likely fail to start." >&2
fi

# Detect GPU count so we can pick topology-aware defaults.
GPU_COUNT=1
if command -v nvidia-smi >/dev/null 2>&1; then
  DETECTED=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
  [ "${DETECTED}" -ge 1 ] && GPU_COUNT="${DETECTED}"
fi

# Resolve "auto" defaults based on GPU count. See header for rationale.
# Track which knobs the caller left as "auto" so the V4-Pro override below
# only adjusts auto-resolved values, not explicit caller settings.
MAX_LEN_AUTO=0; MEM_UTIL_AUTO=0; MAX_NUM_SEQS_AUTO=0
[ "$MAX_LEN" = auto ]      && MAX_LEN_AUTO=1
[ "$MEM_UTIL" = auto ]     && MEM_UTIL_AUTO=1
[ "$MAX_NUM_SEQS" = auto ] && MAX_NUM_SEQS_AUTO=1

case "${GPU_COUNT}" in
  1) DEF_MAX_LEN=524288  DEF_MEM_UTIL=0.93 DEF_MAX_NUM_SEQS=16  ;;
  2) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=32  ;;
  4) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=64  ;;
  8) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=128 ;;
  *) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=64  ;;
esac

# DeepSeek-V4-Pro: 1.6T MoE, ~865 GB weights in native FP4/FP8 quant.
# Needs 8×B200 (1536 GB) minimum — 4×B200 (768 GB) is short by ~100 GB of
# weight storage alone. Pull MAX_LEN and MAX_NUM_SEQS down so KV fits in
# the smaller post-weights headroom (~580 GB on 8×B200).
case "$MODEL" in
  *DeepSeek-V4-Pro*|*deepseek-v4-pro*)
    if [ "${GPU_COUNT}" -lt 8 ]; then
      echo "Error: DeepSeek V4 Pro needs ≥8 B200s (~865 GB weights); you have ${GPU_COUNT} GPU(s)." >&2
      echo "       Use V4-Flash on smaller rentals, or rent an 8×B200 host." >&2
      exit 1
    fi
    DEF_MAX_LEN=524288 DEF_MEM_UTIL=0.94 DEF_MAX_NUM_SEQS=32
    ;;
esac

[ "$MAX_LEN_AUTO" = 1 ]      && MAX_LEN="$DEF_MAX_LEN"
[ "$MEM_UTIL_AUTO" = 1 ]     && MEM_UTIL="$DEF_MEM_UTIL"
[ "$MAX_NUM_SEQS_AUTO" = 1 ] && MAX_NUM_SEQS="$DEF_MAX_NUM_SEQS"

echo "Topology: ${GPU_COUNT} GPU(s) → MAX_LEN=${MAX_LEN} MEM_UTIL=${MEM_UTIL} MAX_NUM_SEQS=${MAX_NUM_SEQS}"

# TP=GPU_COUNT on multi-GPU; favors single-request latency over throughput.
# vLLM: --tensor-parallel-size; SGLang: --tp-size
if [ -z "${TENSOR_PARALLEL}" ]; then
  tp_flag=""
  if [ "$ENGINE_SLUG" = "vllm" ]; then
    tp_flag="--tensor-parallel-size"
  else
    tp_flag="--tp-size"
  fi
  if ! has_extra_flag "$tp_flag"; then
    if [ "${GPU_COUNT}" -gt 1 ]; then
      echo "Auto-setting ${tp_flag} ${GPU_COUNT}."
      TENSOR_PARALLEL="${GPU_COUNT}"
    fi
  fi
fi

# Single-GPU prefill activation can spike past the ~30 GB free after V4-Flash
# weights. vLLM: --max-num-batched-tokens; SGLang: --max-prefill-tokens
if [ "${GPU_COUNT}" = "1" ]; then
  if [ "$ENGINE_SLUG" = "vllm" ] && ! has_extra_flag --max-num-batched-tokens; then
    EXTRA_ARGS="--max-num-batched-tokens ${MAX_NUM_BATCHED_TOKENS} ${EXTRA_ARGS}"
  elif [ "$ENGINE_SLUG" = "sglang" ] && ! has_extra_flag --max-prefill-tokens; then
    EXTRA_ARGS="--max-prefill-tokens ${MAX_NUM_BATCHED_TOKENS} ${EXTRA_ARGS}"
  fi
fi

# DeepSeek V4 is MoE. vLLM: --enable-expert-parallel; SGLang: --enable-ep-moe
if [ "$ENGINE_SLUG" = "vllm" ]; then
  ep_flag="--enable-expert-parallel"
else
  ep_flag="--enable-ep-moe"
fi
case "$MODEL" in
  *DeepSeek-V4*|*deepseek-v4*)
    if [ -z "${DISABLE_EXPERT_PARALLEL:-}" ] \
       && [ "${GPU_COUNT}" -ge 4 ] \
       && ! has_extra_flag "$ep_flag"; then
      echo "Auto-enabling ${ep_flag} for ${GPU_COUNT}-GPU MoE."
      EXTRA_ARGS="${ep_flag} ${EXTRA_ARGS}"
    fi
    ;;
esac

if [ -n "${HF_TOKEN}" ]; then
  export HF_TOKEN HUGGING_FACE_HUB_TOKEN="${HF_TOKEN}"
fi

# Build engine CLI args. Caller's EXTRA_ARGS wins (per-flag suppression).
# When LOGGING_PROXY=1, engine binds to 127.0.0.1:${SERVE_INTERNAL_PORT}
# and the Python proxy on ${SERVE_PORT} is externally reachable.
if [ "$LOGGING_PROXY" = "1" ]; then
  BIND_HOST=127.0.0.1
  BIND_PORT="${SERVE_INTERNAL_PORT}"
else
  BIND_HOST=0.0.0.0
  BIND_PORT="${SERVE_PORT}"
fi

if [ "$ENGINE_SLUG" = "vllm" ]; then
  ARGS=(serve "${MODEL}")
  has_extra_flag --host                       || ARGS+=(--host "${BIND_HOST}")
  has_extra_flag --port                       || ARGS+=(--port "${BIND_PORT}")
  has_extra_flag --trust-remote-code          || ARGS+=(--trust-remote-code)
  has_extra_flag --max-model-len              || ARGS+=(--max-model-len "${MAX_LEN}")
  has_extra_flag --gpu-memory-utilization     || ARGS+=(--gpu-memory-utilization "${MEM_UTIL}")
  has_extra_flag --max-num-seqs               || ARGS+=(--max-num-seqs "${MAX_NUM_SEQS}")
  has_extra_flag --served-model-name          || ARGS+=(--served-model-name "${SERVED}")

  if [ -n "${TOOL_PARSER}" ] && ! has_extra_flag --tool-call-parser; then
    ARGS+=(--enable-auto-tool-choice --tool-call-parser "${TOOL_PARSER}")
  fi
  if [ -n "${REASONING_PARSER}" ] && ! has_extra_flag --reasoning-parser; then
    ARGS+=(--reasoning-parser "${REASONING_PARSER}")
    has_extra_flag --default-chat-template-kwargs \
      || ARGS+=(--default-chat-template-kwargs '{"thinking": true}')
  fi
  if [ -n "${TENSOR_PARALLEL}" ] && ! has_extra_flag --tensor-parallel-size; then
    ARGS+=(--tensor-parallel-size "${TENSOR_PARALLEL}")
  fi
else
  # SGLang CLI
  ARGS=(sglang.launch_server --model "${MODEL}")
  has_extra_flag --host                       || ARGS+=(--host "${BIND_HOST}")
  has_extra_flag --port                       || ARGS+=(--port "${BIND_PORT}")
  has_extra_flag --trust-remote-code          || ARGS+=(--trust-remote-code)
  has_extra_flag --context-length             || ARGS+=(--context-length "${MAX_LEN}")
  has_extra_flag --mem-fraction-static        || ARGS+=(--mem-fraction-static "${MEM_UTIL}")
  has_extra_flag --max-running-requests       || ARGS+=(--max-running-requests "${MAX_NUM_SEQS}")
  has_extra_flag --served-model-name          || ARGS+=(--served-model-name "${SERVED}")

  if [ -n "${TENSOR_PARALLEL}" ] && ! has_extra_flag --tp-size; then
    ARGS+=(--tp-size "${TENSOR_PARALLEL}")
  fi
fi

if [ -n "${EXTRA_ARGS}" ]; then
  # Word-splitting is intentional so EXTRA_ARGS can carry multiple flags.
  # shellcheck disable=SC2206
  EXTRA=(${EXTRA_ARGS})
  ARGS+=("${EXTRA[@]}")
fi

# Final sanity scan: warn on any flag that ended up in ARGS twice.
DUP_FLAGS=$(printf '%s\n' "${ARGS[@]}" | grep -E '^--' | sort | uniq -d)
if [ -n "$DUP_FLAGS" ]; then
  echo "Warning: duplicate ${ENGINE_SLUG} flag(s) in ARGS — CLI may reject:" >&2
  printf '  %s\n' $DUP_FLAGS >&2
fi

# Kill any previous instance of this engine + proxy, then launch.
pkill -f "${ENGINE_SLUG}" 2>/dev/null || true
pkill -f 'vllm-logging-proxy.py' 2>/dev/null || true
pkill -f 'logging-proxy.py' 2>/dev/null || true
rm -f /workspace/proxy.pid
sleep 3

readonly LOGFILE="/workspace/${ENGINE_SLUG}.log"
readonly PIDFILE="/workspace/${ENGINE_SLUG}.pid"

echo "Launching: ${ARGS[*]}"
echo "=== ${ENGINE_SLUG} launch args: ${ARGS[*]}" >> "$LOGFILE"
emit_event vllm_launch "args=${ARGS[*]} engine=${ENGINE_SLUG}"
nohup bash -c '"$@" 2>&1 | ts "%Y-%m-%dT%H:%M:%SZ "' \
  _ "${ARGS[@]}" >>"$LOGFILE" &
ENGINE_PID=$!
echo "${ENGINE_PID}" > "$PIDFILE"

# Start the monitor before the readiness wait so GPU/VRAM/power samples cover
# the interesting window — weights load, compile, warmup. Idempotent via pidfile.
start_monitor_if_needed
# Start the logging proxy alongside the engine so external clients hitting
# :${SERVE_PORT} get a clean 502 (not connection-refused) during warmup.
start_logging_proxy_if_needed

echo "Waiting for /v1/models on :${BIND_PORT} (cold-cold start ~30 min; up to 40 min ceiling) ..."
# 480 × 5s = 40 min ceiling.
for _ in $(seq 1 480); do
  if curl -fsS "http://localhost:${BIND_PORT}/v1/models" >/dev/null 2>&1; then
    echo "${ENGINE_SLUG} is ready."
    emit_event vllm_ready "engine=${ENGINE_SLUG}"
    curl -s "http://localhost:${BIND_PORT}/v1/models" | head -c 400
    echo
    exit 0
  fi
  if ! kill -0 "${ENGINE_PID}" 2>/dev/null; then
    echo "${ENGINE_SLUG} process exited unexpectedly. Last 50 log lines:" >&2
    tail -n 50 "$LOGFILE" >&2 || true
    emit_event vllm_failed "engine=${ENGINE_SLUG} process exited during startup"
    exit 1
  fi
  sleep 5
done

echo "Timed out waiting for ${ENGINE_SLUG} readiness. Tail of ${LOGFILE}:" >&2
tail -n 50 "$LOGFILE" >&2 || true
emit_event vllm_failed "engine=${ENGINE_SLUG} timeout waiting for /v1/models"
exit 1
