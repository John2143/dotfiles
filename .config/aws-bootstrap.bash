#!/usr/bin/env bash
# AWS EC2 bootstrap: provisions and launches vLLM or SGLang on an EC2 GPU
# instance. Designed to be run inside the instance (via SSH or user-data),
# mirroring the Vast.ai bootstrap (vast-bootstrap.bash) but for AWS.
#
# Caller (an aws-bootstrap fish function) sets these env vars from
# /run/agenix/aws-credentials + ~/.config/aws/profile + defaults:
#
#   ENGINE             inference engine: "vllm" (default) or "sglang"
#   MODEL              HF model id (required)
#   SERVED             served-model-name (default deepseek-v4-flash)
#   SERVE_PORT         listen port inside the instance (default 8000)
#   MAX_LEN            context length ("auto" → tuned per GPU count, see below)
#   MEM_UTIL           GPU memory fraction ("auto" → tuned per GPU count)
#   MAX_NUM_SEQS       max concurrent sequences ("auto" → tuned per GPU count)
#   HF_TOKEN           HuggingFace token (optional, recommended for gated models)
#   TOOL_PARSER        --tool-call-parser (vLLM only)
#   REASONING_PARSER   --reasoning-parser (vLLM only)
#   EXTRA_ARGS         space-separated engine-specific extra flags (optional)
#   FORCE_RESTART      if non-empty, kill any running server and re-launch
#   TENSOR_PARALLEL    tensor parallelism (auto-detected = GPU count)
#   LOGGING_PROXY      "1" (default) → Python reverse proxy logs queries to
#                      /workspace/metrics/queries.jsonl. "0" → engine binds
#                      SERVE_PORT directly.
#   SERVE_INTERNAL_PORT private port engine binds to under LOGGING_PROXY=1
#                      (default 18000). Ignored otherwise.
#
# Instance type → GPU memory guide (for DeepSeek V4 Flash, ~158 GB weights):
#
#   g4dn.metal         8× T4 16GB    = 128 GB  ❌ CANNOT FIT (128 < 158)
#   g5.48xlarge        8× A10G 24GB  = 192 GB  ⚠️  Barely fits, ~32K ctx max
#                                                $16.29/hr on-demand
#   g6e.48xlarge       8× L40S 48GB  = 384 GB  ✅ Comfortable, $30.13/hr
#   p4de.24xlarge      8× A100 80GB  = 640 GB  ✅ Excellent, $27.45/hr
#   p5.48xlarge        8× H100 80GB  = 640 GB  ✅ Native FP8, $98.32/hr
#
# A10G (Ampere SM 8.6) and L40S (Ada SM 8.9) lack native FP8 tensor cores.
# vLLM handles this via Marlin W8A16 dequant — quality identical, ~2-3×
# slower prefill, decode mostly unaffected (memory-bound).
#
# Auto-tuning is VRAM-driven (same algorithm as vast-bootstrap.bash):
#   KV_BUDGET ≥ 1000 → MAX_LEN=1M     MAX_NUM_SEQS=128 MEM_UTIL=0.95
#             ≥ 400  → MAX_LEN=1M     MAX_NUM_SEQS=64  MEM_UTIL=0.95
#             ≥ 100  → MAX_LEN=1M     MAX_NUM_SEQS=32  MEM_UTIL=0.95
#             ≥ 15   → MAX_LEN=512k   MAX_NUM_SEQS=16  MEM_UTIL=0.93
#             ≥ 8    → MAX_LEN=128k   MAX_NUM_SEQS=8   MEM_UTIL=0.92
#             ≥ 4    → MAX_LEN=64k    MAX_NUM_SEQS=4   MEM_UTIL=0.90
#             < 4    → refuse (won't fit)
#
# Recommended AMI: AWS Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu
# 24.04). Comes with NVIDIA drivers + CUDA pre-installed. Query the latest
# AMI ID with:
#   aws ssm get-parameter --region us-east-1 \
#     --name /aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-24.04/latest/ami-id \
#     --query "Parameter.Value" --output text
#
# EBS: Attach a separate gp3 volume (≥500 GB, 3000 IOPS / 500 MBps throughput
# is fine) and mount it at /workspace. Model weights (~158 GB) + venv + logs
# live there. The volume persists across instance stop/start — only pay for
# storage when the instance is off.
#
# Idempotent: if a server is already responding on $SERVE_PORT it exits 0
# unless FORCE_RESTART is set.
# Logs go to /workspace/<engine>.log; pid goes to /workspace/<engine>.pid.
set -euo pipefail

: "${ENGINE:=vllm}"
: "${MODEL:?missing MODEL}"
: "${SERVED:=deepseek-v4-flash}"
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
readonly ENGINE_SLUG="$ENGINE"
: "${LOGGING_PROXY:=1}"
: "${SERVE_INTERNAL_PORT:=${VLLM_INTERNAL_PORT:-18000}}"

# ── /workspace setup ───────────────────────────────────────────────────────
# On AWS, /workspace is typically a separate EBS volume. The launch template
# or user-data should format + mount it. If it's not mounted, try to find
# and mount an unattached NVMe device (common for instance-store or
# pre-attached EBS). Falls back to creating /workspace on the root volume
# if nothing else is available (data won't persist across termination).
if ! mountpoint -q /workspace 2>/dev/null; then
  echo "Setting up /workspace ..."

  # Try common EBS NVMe paths: /dev/nvme1n1 (first non-root NVMe), then
  # /dev/nvme2n1, etc. Skip nvme0n1 (root volume on Nitro instances).
  WORKSPACE_DEV=""
  for dev in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/xvdb /dev/sdb; do
    if [ -b "$dev" ] && ! mount | grep -q "^$dev "; then
      WORKSPACE_DEV="$dev"
      break
    fi
  done

  if [ -n "$WORKSPACE_DEV" ]; then
    # Check if device has a filesystem already, format if not.
    if ! blkid "$WORKSPACE_DEV" >/dev/null 2>&1; then
      echo "Formatting $WORKSPACE_DEV as ext4 ..."
      mkfs.ext4 -q "$WORKSPACE_DEV"
    fi
    mkdir -p /workspace
    mount "$WORKSPACE_DEV" /workspace
    echo "Mounted $WORKSPACE_DEV at /workspace."
  else
    echo "No unattached block device found — using root volume for /workspace."
    echo "WARNING: data will be lost on instance termination."
    mkdir -p /workspace
  fi
fi

mkdir -p /workspace /workspace/tmp /workspace/pip-cache /workspace/.hf_home \
         /workspace/.vllm_cache /workspace/.triton_cache /workspace/.inductor_cache \
         /workspace/.sglang_cache /workspace/metrics
cd /workspace

# ── Lifecycle events ───────────────────────────────────────────────────────
emit_event() {
  local type="$1" msg="${2:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  msg="${msg//$'\n'/\\n}"
  msg="${msg//$'\r'/\\r}"
  msg="${msg//$'\t'/\\t}"
  printf '{"ts":"%s","type":"%s","message":"%s","engine":"%s","platform":"aws"}\n' \
    "$ts" "$type" "$msg" "$ENGINE_SLUG" \
    >> /workspace/metrics/events.jsonl
}
emit_event bootstrap_start "model=${MODEL} served=${SERVED} port=${SERVE_PORT}"

# ── Environment: pin transient state to /workspace ────────────────────────
export TMPDIR=/workspace/tmp
export HF_HOME="${HF_HOME:-/workspace/.hf_home}"
export PIP_CACHE_DIR=/workspace/pip-cache
# AWS EBS is reliable storage; hf-xet parallel downloads are fine here.
export HF_HUB_DISABLE_XET=0
export HF_HUB_ENABLE_HF_TRANSFER=1

export VLLM_CACHE_ROOT=/workspace/.vllm_cache
export TRITON_CACHE_DIR=/workspace/.triton_cache
export TORCHINDUCTOR_CACHE_DIR=/workspace/.inductor_cache

# ── Clean any previous engine processes ────────────────────────────────────
# On the Deep Learning AMI, nothing auto-launches on GPU instances. Still,
# be defensive against stale processes from a previous bootstrap.
pkill -f 'vllm serve' 2>/dev/null || true
pkill -f 'sglang.launch_server' 2>/dev/null || true
pkill -f 'logging-proxy.py' 2>/dev/null || true
rm -f /workspace/proxy.pid

# ── Probe for existing server ─────────────────────────────────────────────
PROBE_PORT="${SERVE_PORT}"
[ "$LOGGING_PROXY" = "1" ] && PROBE_PORT="${SERVE_INTERNAL_PORT}"

if curl -fsS "http://localhost:${PROBE_PORT}/v1/models" >/dev/null 2>&1; then
  if [ -z "${FORCE_RESTART}" ]; then
    emit_event early_exit_already_running ""
    echo "${ENGINE_SLUG} already responding on :${PROBE_PORT} — bootstrap is a no-op."
    echo "(Pass --restart to aws-bootstrap to force a re-launch with new flags.)"
    curl -s "http://localhost:${PROBE_PORT}/v1/models" | head -c 400
    echo
    start_monitor_if_needed
    start_logging_proxy_if_needed
    exit 0
  fi
  emit_event force_restart ""
  echo "FORCE_RESTART set — stopping running ${ENGINE_SLUG} to re-launch ..."
  pkill -f "${ENGINE_SLUG}" 2>/dev/null || true
  pkill -f 'logging-proxy.py' 2>/dev/null || true
  rm -f /workspace/proxy.pid
  for _ in $(seq 1 30); do
    curl -fsS "http://localhost:${PROBE_PORT}/v1/models" >/dev/null 2>&1 || break
    sleep 1
  done
fi

# ── System dependencies ────────────────────────────────────────────────────
# The Deep Learning AMI ships NVIDIA drivers + CUDA but may be missing
# python3-venv, python3-dev (for Triton JIT), and build-essential.
NEED_APT=0
command -v python3 >/dev/null 2>&1 || NEED_APT=1
command -v gcc >/dev/null 2>&1 || NEED_APT=1
python3 -c 'import ensurepip, venv' >/dev/null 2>&1 || NEED_APT=1
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")
[ -n "$PYVER" ] && [ -e "/usr/include/python${PYVER}/Python.h" ] || NEED_APT=1
ldconfig -p 2>/dev/null | grep -q 'libnuma\.so\.1' || NEED_APT=1

if [ "$NEED_APT" = 1 ]; then
  echo "Installing python3 + pip + venv + dev headers + build-essential via apt ..."
  emit_event apt_install_start ""
  APT_OK=
  for _ in 1 2 3; do
    if apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      python3 python3-pip python3-venv python3-dev \
      build-essential ca-certificates curl \
      moreutils gawk \
      libnuma1; then
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

# ── Has extra flag helper ──────────────────────────────────────────────────
has_extra_flag() {
  printf '%s\n' "$EXTRA_ARGS" | grep -qE -- "(^|[[:space:]])$1([[:space:]]|=|\$)"
}

# ── DeepSeek V4 specific config (vLLM) ─────────────────────────────────────
if [ "$ENGINE_SLUG" = "vllm" ]; then
  case "$MODEL" in
    *DeepSeek-V4*|*deepseek-v4*)
      if ! has_extra_flag --kv-cache-dtype; then
        echo "Auto-setting --kv-cache-dtype fp8 for DeepSeek V4 (vLLM)."
        EXTRA_ARGS="--kv-cache-dtype fp8 ${EXTRA_ARGS}"
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
  echo "ENGINE=sglang: SGLang's MLA attention path has correct precision (no CJK injection)."
fi

# ── Metrics monitor (same as vast-bootstrap) ───────────────────────────────
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
  echo "timestamp,pid,gpu_uuid,used_memory_mib" > "$GPROC_CSV"
fi

NET_IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')
[ -z "$NET_IFACE" ] && NET_IFACE=eth0

PREV_CPU_TOTAL=
PREV_CPU_IDLE=
PREV_RX=
PREV_TX=
PREV_RD=
PREV_WR=
PREV_T=

read_cpu() {
  local _ u n s i io ir si st rest
  read -r _ u n s i io ir si st rest < /proc/stat
  printf '%s %s\n' "$((u+n+s+i+io+ir+si+st))" "$((i+io))"
}
read_net() {
  awk -v ifc="$NET_IFACE" '$1 ~ "^"ifc":" {gsub(":", " "); print $2, $10}' /proc/net/dev
}
read_dio() {
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

# ── Logging proxy (same as vast-bootstrap) ─────────────────────────────────
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

Started by aws-bootstrap when LOGGING_PROXY=1. Listens on $PROXY_PORT and
forwards to http://127.0.0.1:$UPSTREAM_PORT. Auth headers are redacted in
the log but preserved on the wire.
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

LOG_PATHS = {
    "/v1/chat/completions", "/v1/completions", "/v1/embeddings",
    "/v1/responses", "/v1/rerank", "/v1/score",
    "/tokenize", "/v1/audio/transcriptions",
}

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
            "ts": ts, "request_id": request_id, "path": full_path,
            "method": request.method, "duration_ms": elapsed_ms,
            "status": upstream.status_code, "stream": False,
            "request_headers": _redact(request.headers),
            "request": req_json, "response": resp_json,
        })
        return Response(content=upstream.content,
                        status_code=upstream.status_code,
                        headers=dict(_filter(upstream.headers)))

    # Streaming path
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
                "ts": ts, "request_id": request_id, "path": full_path,
                "method": request.method, "duration_ms": elapsed_ms,
                "status": upstream.status_code, "stream": True,
                "request_headers": _redact(request.headers),
                "request": req_json, "response_events": events,
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
  echo "Started logging proxy (pid $(cat "$pidfile"), :${SERVE_PORT} → :${SERVE_INTERNAL_PORT})."
  emit_event proxy_start "pid=$(cat "$pidfile") port=${SERVE_PORT} upstream=${SERVE_INTERNAL_PORT}"
}

# ── Venv + engine installation ─────────────────────────────────────────────
pip_install_retry() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if /workspace/venv/bin/pip install --quiet \
         --retries 10 --timeout 120 "$@"; then
      return 0
    fi
    echo "pip install attempt ${attempt} failed; waiting 10s before retry ..." >&2
    sleep 10
  done
  return 1
}

bootstrap_venv_and_install() {
  local pkg="$1"
  if [ -d /workspace/venv ] && { [ ! -x /workspace/venv/bin/python3 ] || [ ! -x /workspace/venv/bin/pip ]; }; then
    echo "Removing incomplete /workspace/venv from a previous failed attempt ..."
    rm -rf /workspace/venv
  fi
  if [ ! -d /workspace/venv ]; then
    echo "Creating venv at /workspace/venv ..."
    python3 -m venv /workspace/venv
  fi
  echo "pip install ${pkg} into /workspace/venv (~5 min) ..."
  emit_event pip_install_start "pkg=${pkg}"
  if ! pip_install_retry --upgrade pip; then
    emit_event pip_install_failed "pkg=pip-upgrade"
    echo "Failed to upgrade pip after 5 attempts." >&2
    exit 1
  fi
  if ! pip_install_retry "${pkg}"; then
    emit_event pip_install_failed "pkg=${pkg}"
    echo "Failed to install ${pkg} after 5 attempts." >&2
    exit 1
  fi
  emit_event pip_install_done "pkg=${pkg}"
  export PATH="/workspace/venv/bin:$PATH"
}

engine_importable() {
  [ -x /workspace/venv/bin/python ] && \
    /workspace/venv/bin/python -c "import $1" >/dev/null 2>&1
}

if [ "$ENGINE_SLUG" = "vllm" ] && ! engine_importable vllm; then
  echo "vllm not importable; bootstrapping venv + vllm ..."
  bootstrap_venv_and_install vllm
elif [ "$ENGINE_SLUG" = "sglang" ] && ! engine_importable sglang; then
  echo "sglang not importable; bootstrapping venv + sglang ..."
  bootstrap_venv_and_install "sglang[all]"
fi

# ── SGLang transformers upgrade for DSv4 ───────────────────────────────────
if [ "$ENGINE_SLUG" = "sglang" ]; then
  case "$MODEL" in
    *DeepSeek-V4*|*deepseek-v4*)
      if [ -x /workspace/venv/bin/python ] && \
         ! /workspace/venv/bin/python -c 'from transformers.models.auto.configuration_auto import CONFIG_MAPPING; assert "deepseek_v4" in CONFIG_MAPPING' >/dev/null 2>&1; then
        echo "Upgrading transformers from git (DSv4 model_type not yet in released transformers) ..."
        emit_event transformers_upgrade_start ""
        if pip_install_retry --upgrade \
             'git+https://github.com/huggingface/transformers.git'; then
          emit_event transformers_upgrade_done ""
        else
          emit_event transformers_upgrade_failed ""
          echo "Warning: transformers git upgrade failed — DSv4 may not load." >&2
        fi
      fi
      ;;
  esac
fi

# ── GPU detection ──────────────────────────────────────────────────────────
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "Warning: nvidia-smi not found. ${ENGINE_SLUG} will likely fail to start." >&2
fi

GPU_COUNT=1
TOTAL_VRAM_GIB=0
FP8_NATIVE=1
GPU_NAME="unknown"
CC=""
if command -v nvidia-smi >/dev/null 2>&1; then
  DETECTED=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
  [ "${DETECTED}" -ge 1 ] && GPU_COUNT="${DETECTED}"
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  VRAM_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
  if [ -n "${VRAM_MIB}" ]; then
    TOTAL_VRAM_GIB=$(awk -v n="${GPU_COUNT}" -v m="${VRAM_MIB}" \
      'BEGIN{printf "%d", n*m/1024}')
  fi
  CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
  CC_MAJOR=$(printf '%s' "${CC}" | cut -d. -f1)
  # SM 9.0+ (Hopper H100, Blackwell) = native FP8. SM 8.x (Ampere A10G/A100,
  # Ada L40S) = Marlin emulation.
  if [ -n "${CC_MAJOR}" ] && [ "${CC_MAJOR}" -lt 9 ] 2>/dev/null; then
    FP8_NATIVE=0
  fi
fi

# Detect AWS instance type from metadata (informational).
AWS_INSTANCE_TYPE=""
AWS_INSTANCE_TYPE=$(curl -sf --max-time 2 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "")

echo "Instance: ${AWS_INSTANCE_TYPE:-unknown} | GPU topology: ${GPU_COUNT}× ${GPU_NAME} (CC ${CC:-?}, ${TOTAL_VRAM_GIB} GiB total, FP8-native=${FP8_NATIVE})"

# ── Weight estimation + auto-tuning ────────────────────────────────────────
WEIGHT_GIB=0
case "$MODEL" in
  *DeepSeek-V4-Pro*|*deepseek-v4-pro*)  WEIGHT_GIB=865 ;;
  *DeepSeek-V4*|*deepseek-v4*)          WEIGHT_GIB=158 ;;
esac

MAX_LEN_AUTO=0; MEM_UTIL_AUTO=0; MAX_NUM_SEQS_AUTO=0
[ "$MAX_LEN" = auto ]      && MAX_LEN_AUTO=1
[ "$MEM_UTIL" = auto ]     && MEM_UTIL_AUTO=1
[ "$MAX_NUM_SEQS" = auto ] && MAX_NUM_SEQS_AUTO=1

KV_BUDGET=0
if [ "$WEIGHT_GIB" -gt 0 ] && [ "$TOTAL_VRAM_GIB" -gt 0 ]; then
  # Activation reserve: 10 GiB on FP8-native GPUs, 30 GiB on Ampere/Ada
  # (Marlin produces BF16 intermediates per layer, ~3× the native FP8 reserve).
  ACT_RESERVE=10
  [ "$FP8_NATIVE" = 0 ] && ACT_RESERVE=30
  KV_BUDGET=$((TOTAL_VRAM_GIB - WEIGHT_GIB - ACT_RESERVE))

  if [ "$KV_BUDGET" -lt 4 ]; then
    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════╗" >&2
    echo "║  INSUFFICIENT GPU MEMORY                                    ║" >&2
    echo "╠══════════════════════════════════════════════════════════════╣" >&2
    printf "║  Instance:    %-46s ║\n" "${AWS_INSTANCE_TYPE:-unknown}" >&2
    printf "║  GPUs:        %d× %-40s ║\n" "${GPU_COUNT}" "${GPU_NAME}" >&2
    printf "║  Total VRAM:  %-3d GiB (need ≥%d GiB)                      ║\n" "${TOTAL_VRAM_GIB}" "$((WEIGHT_GIB + ACT_RESERVE + 4))" >&2
    echo "╠══════════════════════════════════════════════════════════════╣" >&2
    echo "║  g4dn (T4 16GB)    → 128 GB max — CANNOT fit DeepSeek V4    ║" >&2
    echo "║  Minimum: g5.48xlarge (8× A10G 24GB = 192 GB)               ║" >&2
    echo "║  Recommended: g6e.48xlarge (8× L40S 48GB = 384 GB)          ║" >&2
    echo "║  Best value:  p4de.24xlarge (8× A100 80GB = 640 GB)         ║" >&2
    echo "╚══════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    emit_event bootstrap_failed "insufficient_vram total=${TOTAL_VRAM_GIB} needed=$((WEIGHT_GIB + ACT_RESERVE + 4))"
    exit 1
  fi

  # Tiers calibrated to V4-Flash on real hardware. Breakpoints account for
  # nvidia-smi reporting raw VRAM minus reserved (e.g. A10G shows ~22.35 GiB
  # not 24, so 8× ≈ 179 GiB not 192).
  #
  #   g5.48xlarge       (8×A10G, KV≈11)  → 128K ctx, 8 seq
  #   g6e.48xlarge      (8×L40S, KV≈200) → 1M ctx, 32 seq
  #   p4de.24xlarge     (8×A100, KV≈450) → 1M ctx, 64 seq
  #   p5.48xlarge       (8×H100, KV≈450) → 1M ctx, 64 seq (native FP8)
  if   [ "$KV_BUDGET" -ge 1000 ]; then DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=128
  elif [ "$KV_BUDGET" -ge 400 ];  then DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=64
  elif [ "$KV_BUDGET" -ge 100 ];  then DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=32
  elif [ "$KV_BUDGET" -ge 15 ];   then DEF_MAX_LEN=524288  DEF_MEM_UTIL=0.93 DEF_MAX_NUM_SEQS=16
  elif [ "$KV_BUDGET" -ge 8 ];    then DEF_MAX_LEN=131072  DEF_MEM_UTIL=0.92 DEF_MAX_NUM_SEQS=8
  else                                 DEF_MAX_LEN=65536   DEF_MEM_UTIL=0.90 DEF_MAX_NUM_SEQS=4
  fi

  # V4-Pro: clamp context, halve concurrency (massive activation spikes).
  case "$MODEL" in
    *DeepSeek-V4-Pro*|*deepseek-v4-pro*)
      [ "$DEF_MAX_LEN" -gt 524288 ] && DEF_MAX_LEN=524288
      DEF_MAX_NUM_SEQS=$((DEF_MAX_NUM_SEQS / 2))
      [ "$DEF_MAX_NUM_SEQS" -lt 8 ] && DEF_MAX_NUM_SEQS=8
      ;;
  esac

  echo "Memory plan: weights≈${WEIGHT_GIB} GiB + activations≈${ACT_RESERVE} GiB + KV budget=${KV_BUDGET} GiB → tier MAX_LEN=${DEF_MAX_LEN} MAX_NUM_SEQS=${DEF_MAX_NUM_SEQS}"
else
  # Unknown model: fall back to GPU-count tiers (assumes reasonable headroom).
  case "${GPU_COUNT}" in
    1) DEF_MAX_LEN=524288  DEF_MEM_UTIL=0.93 DEF_MAX_NUM_SEQS=16  ;;
    2) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=32  ;;
    4) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=64  ;;
    8) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=128 ;;
    *) DEF_MAX_LEN=1000000 DEF_MEM_UTIL=0.95 DEF_MAX_NUM_SEQS=64  ;;
  esac
fi

[ "$MAX_LEN_AUTO" = 1 ]      && MAX_LEN="$DEF_MAX_LEN"
[ "$MEM_UTIL_AUTO" = 1 ]     && MEM_UTIL="$DEF_MEM_UTIL"
[ "$MAX_NUM_SEQS_AUTO" = 1 ] && MAX_NUM_SEQS="$DEF_MAX_NUM_SEQS"

echo "Tuning: MAX_LEN=${MAX_LEN} MEM_UTIL=${MEM_UTIL} MAX_NUM_SEQS=${MAX_NUM_SEQS}"

# Heads-up on non-FP8-native GPUs.
if [ "$FP8_NATIVE" = 0 ]; then
  echo "Note: ${GPU_NAME} (CC ${CC}) lacks native FP8 tensor cores — using Marlin W8A16 dequant."
  if [ "$ENGINE_SLUG" = "sglang" ]; then
    case "$MODEL" in
      *DeepSeek-V4*|*deepseek-v4*)
        echo "      If sglang fails to load DSv4, retry with ENGINE=vllm (more mature Marlin path)." >&2
        ;;
    esac
  fi
fi

# ── Tensor parallelism ─────────────────────────────────────────────────────
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

# ── Prefill activation cap ─────────────────────────────────────────────────
PER_GPU_HEADROOM=0
if [ "$KV_BUDGET" -gt 0 ] && [ "$GPU_COUNT" -gt 0 ]; then
  PER_GPU_HEADROOM=$((KV_BUDGET / GPU_COUNT))
fi
NEED_PREFILL_CAP=0
if [ "$PER_GPU_HEADROOM" -gt 0 ] && [ "$PER_GPU_HEADROOM" -lt 40 ]; then
  NEED_PREFILL_CAP=1
elif [ "$KV_BUDGET" = 0 ] && [ "${GPU_COUNT}" = "1" ]; then
  NEED_PREFILL_CAP=1
fi
if [ "$NEED_PREFILL_CAP" = 1 ]; then
  if [ "$ENGINE_SLUG" = "vllm" ] && ! has_extra_flag --max-num-batched-tokens; then
    EXTRA_ARGS="--max-num-batched-tokens ${MAX_NUM_BATCHED_TOKENS} ${EXTRA_ARGS}"
  elif [ "$ENGINE_SLUG" = "sglang" ] && ! has_extra_flag --max-prefill-tokens; then
    EXTRA_ARGS="--max-prefill-tokens ${MAX_NUM_BATCHED_TOKENS} ${EXTRA_ARGS}"
  fi
fi

# ── Expert parallel for MoE ────────────────────────────────────────────────
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

# ── HF token ───────────────────────────────────────────────────────────────
if [ -n "${HF_TOKEN}" ]; then
  export HF_TOKEN HUGGING_FACE_HUB_TOKEN="${HF_TOKEN}"
fi

# ── Build engine CLI args ──────────────────────────────────────────────────
if [ "$LOGGING_PROXY" = "1" ]; then
  BIND_HOST=127.0.0.1
  BIND_PORT="${SERVE_INTERNAL_PORT}"
else
  BIND_HOST=0.0.0.0
  BIND_PORT="${SERVE_PORT}"
fi

if [ "$ENGINE_SLUG" = "vllm" ]; then
  ARGS=(/workspace/venv/bin/vllm serve "${MODEL}")
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
  ARGS=(/workspace/venv/bin/python -m sglang.launch_server --model "${MODEL}")
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
  EXTRA=(${EXTRA_ARGS})
  ARGS+=("${EXTRA[@]}")
fi

# ── Duplicate flag warning ─────────────────────────────────────────────────
DUP_FLAGS=$(printf '%s\n' "${ARGS[@]}" | grep -E '^--' | sort | uniq -d)
if [ -n "$DUP_FLAGS" ]; then
  echo "Warning: duplicate ${ENGINE_SLUG} flag(s) in ARGS — CLI may reject:" >&2
  printf '  %s\n' $DUP_FLAGS >&2
fi

# ── Launch ─────────────────────────────────────────────────────────────────
pkill -f "${ENGINE_SLUG}" 2>/dev/null || true
pkill -f 'logging-proxy.py' 2>/dev/null || true
rm -f /workspace/proxy.pid
sleep 3

readonly LOGFILE="/workspace/${ENGINE_SLUG}.log"
readonly PIDFILE="/workspace/${ENGINE_SLUG}.pid"

echo "Launching: ${ARGS[*]}"
echo "=== ${ENGINE_SLUG} launch args: ${ARGS[*]}" >> "$LOGFILE"
emit_event vllm_launch "args=${ARGS[*]} engine=${ENGINE_SLUG} instance=${AWS_INSTANCE_TYPE:-unknown}"
nohup bash -c '"$@" 2>&1 | ts "%Y-%m-%dT%H:%M:%SZ "' \
  _ "${ARGS[@]}" >>"$LOGFILE" &
ENGINE_PID=$!
echo "${ENGINE_PID}" > "$PIDFILE"

start_monitor_if_needed
start_logging_proxy_if_needed

echo "Waiting for /v1/models on :${BIND_PORT} (cold start: model download ~20 min + engine warmup ~5-10 min) ..."
# 480 × 5s = 40 min ceiling (plenty for model download + warmup on AWS EBS).
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
