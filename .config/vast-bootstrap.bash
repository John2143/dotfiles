#!/usr/bin/env bash
# Runs on the rented Vast.ai instance via `ssh ... bash -s`. The caller
# (vast-bootstrap fish function in nixos/home-cli.nix) sets these env vars
# from /run/agenix/vast-credentials + ~/.config/vast/profile + defaults:
#
#   MODEL              HF model id (required)
#   SERVED             served-model-name exposed on the OpenAI API (default deepseek-v4-flash)
#   VLLM_PORT          listen port inside the rental (default 8000)
#   MAX_LEN            --max-model-len ("auto" → tuned per GPU count, see below)
#   MEM_UTIL           --gpu-memory-utilization ("auto" → tuned per GPU count)
#   MAX_NUM_SEQS       --max-num-seqs ("auto" → tuned per GPU count)
#   HF_TOKEN           HuggingFace token (optional but strongly recommended:
#                      faster downloads, higher rate limits, gated models)
#   TOOL_PARSER        --tool-call-parser, e.g. qwen3_xml (optional)
#   REASONING_PARSER   --reasoning-parser, e.g. qwen3 (optional)
#   EXTRA_ARGS         space-separated extra flags (optional)
#   FORCE_RESTART      if non-empty, kill any running vllm and re-launch
#                      (otherwise the script is a no-op when vllm is up)
#   TENSOR_PARALLEL    --tensor-parallel-size N (auto-detected = GPU count;
#                      set to 1 to disable on multi-GPU instances)
#
# Auto-tuning targets DeepSeek-V4-Flash with 1-2 light users (rare concurrent
# big queries). V4-Flash KV at 1M ctx is only ~6 GiB/seq (7% of V3.2's, via
# CSA+HCA), so the binding constraint is the ~150 GB weight footprint, not KV:
#
#   1 GPU  (B200, 192 GB): MAX_LEN=524288  MEM_UTIL=0.93 MAX_NUM_SEQS=16
#                          (weights eat ~80% VRAM; tighter MEM_UTIL avoids
#                          OOM during CUDA graph capture; --max-num-batched-tokens
#                          capped at 8192 to bound prefill activation spikes)
#   2 GPUs (2×B200, 384):  MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=32
#   4 GPUs (4×B200, 768):  MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=64
#
# Topology choice: TP+EP (each request uses all GPUs) over the vLLM recipe's
# DP+EP default. DP+EP optimizes throughput for many concurrent users; TP+EP
# minimizes per-request latency, which matters more with 1-2 users.
#
# Idempotent: if a vLLM server is already responding on $VLLM_PORT it exits 0
# unless FORCE_RESTART is set.
# Logs go to /workspace/vllm.log; pid goes to /workspace/vllm.pid.
#
# Recommended rental image: nvidia/cuda:12.8.0-devel-ubuntu24.04 (clean CUDA,
# no auto-launched services). Script installs python3 + venv + vllm if
# missing. The venv lives at /workspace/venv and persists across reboots.

set -euo pipefail

: "${MODEL:?missing MODEL}"
: "${SERVED:=deepseek-v4-flash}"
: "${VLLM_PORT:=8000}"
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

mkdir -p /workspace /workspace/tmp /workspace/pip-cache /workspace/.hf_home
cd /workspace

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

# Clear /tmp on the overlay if it's >50% full so existing junk doesn't
# bottleneck a fresh download.
if [ "$(df --output=pcent / | tail -1 | tr -dc 0-9)" -gt 50 ]; then
  rm -rf /tmp/* /tmp/.[!.]* 2>/dev/null || true
fi

# Vast.ai's "vLLM …" templates auto-launch their own vllm via supervisord,
# which holds the entire GPU before our serve command runs. Stop it cleanly
# if present (no-op on bare cuda/pytorch images).
if command -v supervisorctl >/dev/null 2>&1; then
  if supervisorctl status vllm 2>/dev/null | grep -q RUNNING; then
    echo "Stopping supervisord-managed vllm to free the GPU ..."
    supervisorctl stop vllm || true
    sleep 3
  fi
fi
# Belt-and-suspenders: kill any orphan vllm/EngineCore processes.
# NOTE: `VLLM::EngineCore` is an internal vLLM process name (not a stable
# interface) — could change in a future vLLM release. If it stops matching,
# the supervisorctl stop + pkill -f 'vllm serve' above already cover the main
# teardown; this is speculative cleanup.
pkill -9 -f 'VLLM::EngineCore' 2>/dev/null || true

# DeepSeek V4 currently asserts kv_cache_dtype starts with "fp8". Set it
# automatically if the caller didn't pass --kv-cache-dtype themselves.
case "$MODEL" in
  *DeepSeek-V4*|*deepseek-v4*)
    if ! printf '%s\n' "$EXTRA_ARGS" | grep -q -- '--kv-cache-dtype'; then
      echo "Auto-setting --kv-cache-dtype fp8 for DeepSeek V4."
      EXTRA_ARGS="--kv-cache-dtype fp8 ${EXTRA_ARGS}"
    fi
    if [ -z "$TOOL_PARSER" ]; then
      echo "Auto-setting --tool-call-parser deepseek_v4 for DeepSeek V4."
      TOOL_PARSER=deepseek_v4
    fi
    if [ -z "$REASONING_PARSER" ]; then
      echo "Auto-setting --reasoning-parser deepseek_v4 for DeepSeek V4."
      REASONING_PARSER=deepseek_v4
    fi
    ;;
esac

if curl -fsS "http://localhost:${VLLM_PORT}/v1/models" >/dev/null 2>&1; then
  if [ -z "${FORCE_RESTART}" ]; then
    echo "vLLM already responding on :${VLLM_PORT} — bootstrap is a no-op."
    echo "(Pass --restart to vast-bootstrap to force a re-launch with new flags.)"
    curl -s "http://localhost:${VLLM_PORT}/v1/models" | head -c 400
    echo
    exit 0
  fi
  echo "FORCE_RESTART set — stopping running vLLM to re-launch with new flags ..."
  pkill -f 'vllm serve' 2>/dev/null || true
  pkill -9 -f 'VLLM::EngineCore' 2>/dev/null || true
  for _ in $(seq 1 30); do
    curl -fsS "http://localhost:${VLLM_PORT}/v1/models" >/dev/null 2>&1 || break
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
  APT_OK=
  for _ in 1 2 3; do
    if apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      python3 python3-pip python3-venv python3-dev \
      build-essential ca-certificates curl; then
      APT_OK=1
      break
    fi
    echo "apt attempt failed; waiting 5s before retry ..."
    sleep 5
  done
  if [ -z "${APT_OK}" ]; then
    echo "apt failed after 3 attempts." >&2
    exit 1
  fi
fi

# Reuse a previously-created venv if it exists (subsequent bootstraps after
# the first are near-instant — model weights are also cached on /workspace).
if [ -x /workspace/venv/bin/vllm ]; then
  export PATH="/workspace/venv/bin:$PATH"
fi

if ! command -v vllm >/dev/null 2>&1; then
  echo "vllm CLI not found; bootstrapping venv + vllm ..."

  # If a previous attempt left an incomplete venv (e.g. python but no pip,
  # which happens when `python3 -m venv` runs without ensurepip available),
  # nuke it so we can recreate cleanly.
  if [ -d /workspace/venv ] && { [ ! -x /workspace/venv/bin/python3 ] || [ ! -x /workspace/venv/bin/pip ]; }; then
    echo "Removing incomplete /workspace/venv from a previous failed attempt ..."
    rm -rf /workspace/venv
  fi

  if [ ! -d /workspace/venv ]; then
    echo "Creating venv at /workspace/venv ..."
    python3 -m venv /workspace/venv
  fi

  echo "pip install vllm into /workspace/venv (~5 min) ..."
  /workspace/venv/bin/pip install --quiet --upgrade pip
  # To pin a specific vLLM version for reproducibility, replace with:
  #   /workspace/venv/bin/pip install --quiet "vllm==X.Y.Z"
  /workspace/venv/bin/pip install --quiet vllm

  export PATH="/workspace/venv/bin:$PATH"
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "Warning: nvidia-smi not found inside the rental. vLLM will likely fail to start." >&2
fi

# Detect GPU count so we can pick topology-aware defaults.
GPU_COUNT=1
if command -v nvidia-smi >/dev/null 2>&1; then
  DETECTED=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
  [ "${DETECTED}" -ge 1 ] && GPU_COUNT="${DETECTED}"
fi

# Resolve "auto" defaults based on GPU count. See header for rationale.
case "${GPU_COUNT}" in
  1)
    [ "$MAX_LEN" = auto ]      && MAX_LEN=524288
    [ "$MEM_UTIL" = auto ]     && MEM_UTIL=0.93
    [ "$MAX_NUM_SEQS" = auto ] && MAX_NUM_SEQS=16
    ;;
  2)
    [ "$MAX_LEN" = auto ]      && MAX_LEN=1000000
    [ "$MEM_UTIL" = auto ]     && MEM_UTIL=0.95
    [ "$MAX_NUM_SEQS" = auto ] && MAX_NUM_SEQS=32
    ;;
  *)
    [ "$MAX_LEN" = auto ]      && MAX_LEN=1000000
    [ "$MEM_UTIL" = auto ]     && MEM_UTIL=0.95
    [ "$MAX_NUM_SEQS" = auto ] && MAX_NUM_SEQS=64
    ;;
esac
echo "Topology: ${GPU_COUNT} GPU(s) → MAX_LEN=${MAX_LEN} MEM_UTIL=${MEM_UTIL} MAX_NUM_SEQS=${MAX_NUM_SEQS}"

# TP=GPU_COUNT on multi-GPU; favors single-request latency over throughput.
if [ -z "${TENSOR_PARALLEL}" ] && ! printf '%s\n' "$EXTRA_ARGS" | grep -q -- '--tensor-parallel-size'; then
  if [ "${GPU_COUNT}" -gt 1 ]; then
    echo "Auto-setting --tensor-parallel-size ${GPU_COUNT}."
    TENSOR_PARALLEL="${GPU_COUNT}"
  fi
fi

# Single-GPU prefill activation can spike past the ~30 GB free after V4-Flash
# weights; cap chunked-prefill batch size unless the caller already set it.
if [ "${GPU_COUNT}" = "1" ] && ! printf '%s\n' "$EXTRA_ARGS" | grep -q -- '--max-num-batched-tokens'; then
  EXTRA_ARGS="--max-num-batched-tokens ${MAX_NUM_BATCHED_TOKENS} ${EXTRA_ARGS}"
fi

# DeepSeek V4 is MoE; shard experts across GPUs on multi-GPU rentals.
case "$MODEL" in
  *DeepSeek-V4*|*deepseek-v4*)
    if [ "${GPU_COUNT}" -gt 1 ] && ! printf '%s\n' "$EXTRA_ARGS" | grep -q -- '--enable-expert-parallel'; then
      echo "Auto-enabling --enable-expert-parallel for multi-GPU MoE."
      EXTRA_ARGS="--enable-expert-parallel ${EXTRA_ARGS}"
    fi
    ;;
esac

if [ -n "${HF_TOKEN}" ]; then
  export HF_TOKEN HUGGING_FACE_HUB_TOKEN="${HF_TOKEN}"
fi

ARGS=(
  serve "${MODEL}"
  --host 0.0.0.0
  --port "${VLLM_PORT}"
  --trust-remote-code
  --max-model-len "${MAX_LEN}"
  --gpu-memory-utilization "${MEM_UTIL}"
  --enable-prefix-caching
  --max-num-seqs "${MAX_NUM_SEQS}"
  --served-model-name "${SERVED}"
)
if [ -n "${TOOL_PARSER}" ]; then
  ARGS+=(--enable-auto-tool-choice --tool-call-parser "${TOOL_PARSER}")
fi
if [ -n "${REASONING_PARSER}" ]; then
  ARGS+=(--reasoning-parser "${REASONING_PARSER}")
  # DeepSeek V4's chat template disables thinking by default, unlike Qwen3
  # which enables it. Without this, the model never emits reasoning tokens,
  # so the reasoning parser has nothing to split and reasoning_content is
  # always null. Enable thinking server-wide; clients can still disable
  # per-request via chat_template_kwargs: {"thinking": false}.
  ARGS+=(--default-chat-template-kwargs '{"thinking": true}')
fi
if [ -n "${TENSOR_PARALLEL}" ]; then
  ARGS+=(--tensor-parallel-size "${TENSOR_PARALLEL}")
fi
if [ -n "${EXTRA_ARGS}" ]; then
  # Word-splitting is intentional so EXTRA_ARGS can carry multiple flags.
  # shellcheck disable=SC2206
  EXTRA=(${EXTRA_ARGS})
  ARGS+=("${EXTRA[@]}")
fi

pkill -f 'vllm serve' 2>/dev/null || true
sleep 1

echo "Launching: vllm ${ARGS[*]}"
echo "=== vllm launch args: ${ARGS[*]}" >> /workspace/vllm.log
nohup vllm "${ARGS[@]}" >/workspace/vllm.log 2>&1 &
VLLM_PID=$!
echo "${VLLM_PID}" >/workspace/vllm.pid

echo "Waiting for /v1/models on :${VLLM_PORT} (model download dominates first-run time; ~minutes) ..."
for _ in $(seq 1 240); do
  if curl -fsS "http://localhost:${VLLM_PORT}/v1/models" >/dev/null 2>&1; then
    echo "vLLM is ready."
    curl -s "http://localhost:${VLLM_PORT}/v1/models" | head -c 400
    echo
    exit 0
  fi
  if ! kill -0 "${VLLM_PID}" 2>/dev/null; then
    echo "vllm process exited unexpectedly. Last 50 log lines:" >&2
    tail -n 50 /workspace/vllm.log >&2 || true
    exit 1
  fi
  sleep 5
done

echo "Timed out waiting for vLLM readiness. Tail of /workspace/vllm.log:" >&2
tail -n 50 /workspace/vllm.log >&2 || true
exit 1
