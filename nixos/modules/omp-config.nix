{...}: {
  home.file = {
    ".omp/agent/models.yml".text = ''
      providers:
        # vLLM on office — reliable Qwen tool calling (qwen3_xml parser +
        # froggeric fixed template). Prefer over ollama for agentic work.
        office-vllm:
          baseUrl: http://office:8000/v1
          api: openai-completions
          auth: none
          models:
            - id: qwen3.6:27b
              name: Qwen 3.6 (Office vLLM)
              reasoning: true
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 65536
              maxTokens: 8192

        # Cloud GPU rented via Vast.ai. Tunneled to localhost:8001 by the
        # `vast-tunnel` fish function (host discovered live via the
        # vastai API; see _vast-load in this file).
        # Bring up: `vast-create OFFER_ID`, then `vast-bootstrap`, then `vast-tunnel`.
        # The contextWindow/served-model name reflect a typical DeepSeek V4
        # Flash rental; if you serve a different model from the same secret,
        # vLLM still answers requests for the id below as long as it's set
        # via VAST_SERVED_MODEL_NAME.
        vast-vllm:
          baseUrl: http://localhost:8001/v1
          api: openai-completions
          auth: none
          models:
            - id: deepseek-v4-flash
              name: DeepSeek V4 Flash (Vast.ai)
              reasoning: true
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 1000000
              maxTokens: 384000

        office-ollama:
          baseUrl: http://office:11434/v1
          api: openai-completions
          auth: none
          models:
            - id: gemma4
              name: Gemma 4 (Office ROCm)
              reasoning: false
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 128000
              maxTokens: 8192
            - id: qwen3.6:27b
              name: Qwen 3 (Office ROCm)
              reasoning: true
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 128000
              maxTokens: 8192

        # CPU-only instance on office (port 11435). Same model dir as ROCm
        # instance — no extra storage needed. Useful when the GPU is busy or
        # ROCm is misbehaving.
        office-ollama-cpu:
          baseUrl: http://office:11435/v1
          api: openai-completions
          auth: none
          models:
            - id: gemma4
              name: Gemma 4 (Office CPU)
              reasoning: false
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 128000
              maxTokens: 8192
            - id: qwen3.6:27b
              name: Qwen 3 (Office CPU)
              reasoning: true
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 128000
              maxTokens: 8192

        # arch GPU has <8GB VRAM — only gemma4 fits, no vLLM.
        arch-ollama:
          baseUrl: http://arch:11434/v1
          api: openai-completions
          auth: none
          models:
            - id: gemma4
              name: Gemma 4 (Arch CUDA)
              reasoning: false
              input: [text]
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 128000
              maxTokens: 8192
    '';

    ".omp/agent/config.yml".text = ''
      modelRoles:
        default: vast-vllm/deepseek-v4-flash
        smol: office-ollama-cpu/gemma4

      modelProviderOrder:
        - vast-vllm
        - office-vllm
        - office-ollama
        - office-ollama-cpu
        - arch-ollama
        - anthropic
        - openai
        - google

      enabledModels:
        - "vast-vllm/*"
        - "office-vllm/*"
        - "office-ollama/*"
        - "office-ollama-cpu/*"
        - "arch-ollama/*"
        - "anthropic/*"
        - "openai/*"
        - "google/*"

      retry:
        enabled: true
        maxRetries: 3
        baseDelayMs: 2000
        fallbackChains:
          default:
            - "arch-ollama/gemma4"
            - "anthropic/claude-sonnet-4-6"
    '';

    ".omp/agent/keybindings.json".text = ''
      {
        "app.model.select": ["alt+l"]
      }
    '';
  };
}
