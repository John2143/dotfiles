{ ... }:
{
  home.file = {
    ".config/vast/profile.example".text = ''
      # ---------- Identifies which rental the helpers target ----------
      # Must match the --label passed by `vast-create`. Multiple labels
      # let you run different workloads in parallel (one rental per label).
      VAST_LABEL=vllm-deepseek-v4

      # ---------- Engine ----------
      # "sglang" (default, recommended for DeepSeek V4) or "vllm".
      # SGLang produces zero CJK bad tokens vs vLLM's 50-75% rate (vllm#41985).
      # vLLM kept for A/B comparison and non-DS models.
      # VAST_ENGINE=sglang

      # ---------- Model + serving config ----------
      VAST_MODEL=deepseek-ai/DeepSeek-V4-Flash
      VAST_SERVED_MODEL_NAME=deepseek-v4-flash
      # For the large 1.6T MoE variant, switch to:
      #   VAST_MODEL=deepseek-ai/DeepSeek-V4-Pro
      #   VAST_SERVED_MODEL_NAME=deepseek-v4-pro
      # V4-Pro weights are ~865 GB in native FP4/FP8 quant — 8×B200 (1536 GB)
      # is the minimum; vast-bootstrap exits on <8 GPUs to avoid a 30-min
      # download that ends in OOM. It also tightens MAX_LEN / MAX_NUM_SEQS
      # to fit the post-weights KV headroom (~580 GB free on 8×B200).
      # "auto" → vast-bootstrap.bash picks values per GPU count + model. See
      # its header for the full per-topology table. Override with explicit
      # numbers if needed.
      #   V4-Flash:
      #     1×B200: MAX_LEN=524288  MEM_UTIL=0.93 MAX_NUM_SEQS=16
      #     2×B200: MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=32
      #     4×B200: MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=64
      #     8×B200: MAX_LEN=1000000 MEM_UTIL=0.95 MAX_NUM_SEQS=128
      #   V4-Pro (≥8 B200s required — 4×B200 short on weight storage):
      #     8×B200: MAX_LEN=524288  MEM_UTIL=0.94 MAX_NUM_SEQS=32
      VAST_MAX_MODEL_LEN=auto
      VAST_GPU_MEM_UTIL=auto
      VAST_MAX_NUM_SEQS=auto

      # ---------- Networking ----------
      # VAST_LOCAL_PORT is on your laptop; VAST_VLLM_PORT is inside the
      # rental container. Must match the port in models.yml's vast-vllm
      # provider URL (currently http://localhost:8001/v1).
      VAST_LOCAL_PORT=8001
      VAST_VLLM_PORT=8000
      VAST_SSH_USER=root

      # ---------- Optional ----------
      # NOTE: VAST_HF_TOKEN is a *secret*; put it in the encrypted
      # vast-credentials.age file, not here. (envsource sources both,
      # credentials wins.)
      # Tool/reasoning parsers for vLLM-only models that need them. SGLang
      # auto-handles DeepSeek V4; only set these for non-DS models on vLLM
      # (e.g. Qwen3).
      # VAST_TOOL_CALL_PARSER=qwen3_xml
      # VAST_REASONING_PARSER=qwen3
      # Extra engine flags (passed through to vllm serve or sglang.launch_server).
      # VAST_EXTRA_ARGS=--quantization fp4
      # Tensor parallelism: auto-detected from GPU count (2x GPU → 2).
      # Override here to force a specific value or disable (set to 1).
      # VAST_TENSOR_PARALLEL=1

      # Logging proxy: when 1 (default), a tiny Python reverse proxy sits
      # in front of the engine and appends every OpenAI-style request+response
      # to /workspace/metrics/queries.jsonl. The engine binds privately to
      # 127.0.0.1:18000; the proxy listens on $VAST_VLLM_PORT and forwards
      # transparently — clients are unchanged. queries.jsonl rides back
      # automatically with vast-fetch-metrics / vast-destroy. Set to 0 to
      # disable and bind the engine directly on $VAST_VLLM_PORT (legacy mode).
      # VAST_LOGGING_PROXY=0

      # ---------- Manual host override (skip API discovery) ----------
      # By default, vast-bootstrap/vast-tunnel/vast-logs query the API and
      # pick a running instance with VAST_LABEL — auto if exactly one
      # matches, else error and ask for an explicit INSTANCE_ID. Set these
      # to pin to a specific host (useful when the API is flaky or for a
      # rental created outside the normal flow). The pin is incompatible
      # with passing INSTANCE_ID to the helpers — comment these out to use
      # the multi-instance picker.
      # VAST_HOST=1.2.3.4
      # VAST_SSH_PORT=12345
    '';
  };
}
