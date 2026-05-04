{...}: {
  home.file = {
    ".config/vast/profile.example".text = ''
      # ---------- Identifies which rental the helpers target ----------
      # Must match the --label passed by `vast-create`. Multiple labels
      # let you run different workloads in parallel (one rental per label).
      VAST_LABEL=vllm-deepseek-v4

      # ---------- Model + serving config ----------
      VAST_MODEL=deepseek-ai/DeepSeek-V4-Flash
      VAST_SERVED_MODEL_NAME=deepseek-v4-flash
      VAST_MAX_MODEL_LEN=1000000
      VAST_GPU_MEM_UTIL=0.95

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
      # Tool/reasoning parsers for models that need them. DeepSeek V4
      # auto-gets deepseek_v4 parsers from vast-bootstrap.bash; only set
      # these for other models (e.g. Qwen3).
      # Also auto-adds --default-chat-template-kwargs '{"thinking": true}'
      # for DeepSeek V4 so that thinking is enabled by default (the V4
      # template disables it otherwise). To force non-think, pass
      # chat_template_kwargs: {"thinking": false} per request.
      # VAST_TOOL_CALL_PARSER=qwen3_xml
      # VAST_REASONING_PARSER=qwen3
      # Extra `vllm serve` flags. DeepSeek V4 auto-gets --kv-cache-dtype
      # fp8 from vast-bootstrap.bash; only set this for other tweaks.
      # VAST_EXTRA_ARGS=--quantization fp4
      # Tensor parallelism: auto-detected from GPU count (2x GPU → 2).
      # Override here to force a specific value or disable (set to 1).
      # VAST_TENSOR_PARALLEL=1

      # ---------- Manual host override (skip API discovery) ----------
      # By default, vast-bootstrap/vast-tunnel/vast-status discover
      # VAST_HOST and VAST_SSH_PORT from `vastai show instances --label
      # $VAST_LABEL`. Set them here to pin to a specific instance or
      # if the API is unreachable.
      # VAST_HOST=1.2.3.4
      # VAST_SSH_PORT=12345
    '';
  };
}
