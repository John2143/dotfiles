{ ... }:
let
  # Skills -- source of truth in dotfiles/.claude/skills/. Enumerate all skill
  # directories and create symlinks for both OMP (~/.omp/agent/skills/) and
  # Claude Code / OpenClaude (~/.claude/skills/).
  skillsDir = ../../.claude/skills;
  skills = builtins.readDir skillsDir;
  skillNames = builtins.filter (name: skills.${name} == "directory") (builtins.attrNames skills);

  mkSkillLinks = name:
    let
      skillDir = skillsDir + "/${name}";
      dirContents = builtins.readDir skillDir;
      files = builtins.filter (fname: dirContents.${fname} == "regular") (builtins.attrNames dirContents);
      mkLink = fname: {
        ".claude/skills/${name}/${fname}".source = "${skillsDir}/${name}/${fname}";
        ".omp/agent/skills/${name}/${fname}".source = "${skillsDir}/${name}/${fname}";
      };
    in
      builtins.foldl' (acc: fname: acc // mkLink fname) { } files;

  skillLinks = builtins.foldl' (acc: name: acc // mkSkillLinks name) { } skillNames;
in
{
  home.file = skillLinks // {
    # ---- OMP config ----
    ".omp/agent/models.yml".text = ''
      providers:
        # vLLM on office -- reliable Qwen tool calling (qwen3_xml parser +
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

        # DeepSeek's official API. Cheaper than self-hosting on Vast for
        # 1-2 user agentic load (break-even is ~600 req/hr at promo
        # pricing) AND avoids vllm#41985 — DeepSeek runs their own
        # tilelang stack, no vLLM MLA FP8 precision bug, no CJK token
        # injection or repetition collapse. Pricing per 1M tokens
        # (current 2026-05-08; promo on V4-Pro expires 2026-05-31 and
        # prices 4x to $1.74 / $3.48):
        #   v4-flash: $0.14 / $0.28      (no promo, stable)
        #   v4-pro:   $0.435 / $0.87     (75% promo)
        # Cache hits are ~50× cheaper on input.
        # Requires DEEPSEEK_API_KEY in /run/agenix/llm-runtime-keys.
        # Get one: https://platform.deepseek.com/api_keys
        deepseek:
          baseUrl: https://api.deepseek.com/v1
          api: openai-completions
          apiKey: DEEPSEEK_API_KEY
          models:
            - id: deepseek-v4-flash
              name: DeepSeek V4 Flash (Direct API)
              reasoning: true
              input: [text]
              cost: { input: 0.14, output: 0.28, cacheRead: 0.0028, cacheWrite: 0 }
              contextWindow: 1000000
              maxTokens: 65536
            - id: deepseek-v4-pro
              name: DeepSeek V4 Pro (Direct API)
              reasoning: true
              input: [text]
              cost: { input: 0.435, output: 0.87, cacheRead: 0.003625, cacheWrite: 0 }
              contextWindow: 1000000
              maxTokens: 65536

        # OpenAI fallback for the smol safety classifier. Used only when
        # DeepSeek is unreachable — OpenAI's global routing is the most
        # reliable fallback available. gpt-4.1-nano is their cheapest model
        # that supports json_schema structured output (~$0.10/1M tokens).
        # Requires OPENAI_API_KEY in /run/agenix/llm-runtime-keys.
        # Get one: https://platform.openai.com/api-keys
        openai:
          baseUrl: https://api.openai.com/v1
          api: openai-completions
          apiKey: OPENAI_API_KEY
          models:
            - id: gpt-4.1-nano
              name: GPT-4.1 Nano (OpenAI)
              reasoning: false
              input: [text]
              cost: { input: 0.01, output: 0.04, cacheRead: 0.0025, cacheWrite: 0 }
              contextWindow: 1000000
              maxTokens: 8192

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
        # instance -- no extra storage needed. Useful when the GPU is busy or
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

        # OpenRouter — unified API gateway for 300+ models. Used for:
        #   - Gemini Flash/Pro (cheap, fast, 1M context — excellent smol)
        #   - Web search via :online suffix ($0.005/req Exa search)
        #   - Anthropic fallback (routes around direct-API outages)
        #   - Provider diversity for resilience
        # Requires OPENROUTER_API_KEY in /run/agenix/llm-runtime-keys.
        # Get one: https://openrouter.ai/settings/keys
        openrouter:
          baseUrl: https://openrouter.ai/api/v1
          api: openai-completions
          apiKey: OPENROUTER_API_KEY
          models:
            # Gemini Flash Lite — cheapest smol option on OR. $0.10/$0.40 per 1M,
            # 1M context. Lightweight reasoning model, faster than full Flash.
            - id: google/gemini-2.5-flash-lite
              name: Gemini 2.5 Flash Lite (OpenRouter)
              reasoning: true
              input: [text]
              cost: { input: 0.10, output: 0.40, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 1048576
              maxTokens: 65536

            # Gemini Flash — Google's workhorse. $0.30/$2.50 per 1M, 1M context.
            # Supports text and image input (video/audio not yet in OMP schema).
            # Built-in thinking with configurable reasoning effort.
            - id: google/gemini-2.5-flash
              name: Gemini 2.5 Flash Multimodal (OpenRouter)
              reasoning: true
              input: [text, image]
              cost: { input: 0.30, output: 2.50, cacheRead: 0.03, cacheWrite: 0.08333 }
              contextWindow: 1048576
              maxTokens: 65536

            # Gemini Flash with OpenRouter web search. Adds $0.005/req for Exa
            # search results. Supports text and image input.
            - id: google/gemini-2.5-flash:online
              name: Gemini 2.5 Flash Multimodal Online (OpenRouter)
              reasoning: true
              input: [text, image]
              cost: { input: 0.30, output: 2.50, cacheRead: 0.03, cacheWrite: 0.08333 }
              contextWindow: 1048576
              maxTokens: 65536

            # Gemini Pro — heavier reasoning for hard tasks. $1.25/$10 per 1M.
            - id: google/gemini-2.5-pro
              name: Gemini 2.5 Pro (OpenRouter)
              reasoning: true
              input: [text]
              cost: { input: 1.25, output: 10.00, cacheRead: 0.03125, cacheWrite: 0 }
              contextWindow: 1048576
              maxTokens: 65536

            # Claude Sonnet via OpenRouter — fallback when direct Anthropic is
            # down. Same $3/$15 pricing as direct, but OR can route through
            # multiple providers (including Anthropic itself).
            - id: anthropic/claude-sonnet-4-6
              name: Claude Sonnet 4.6 (OpenRouter)
              reasoning: true
              input: [text]
              cost: { input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75 }
              contextWindow: 1000000
              maxTokens: 65536

            # Claude Haiku via OpenRouter. $1/$5 per 1M.
            - id: anthropic/claude-haiku-4-5
              name: Claude Haiku 4.5 (OpenRouter)
              reasoning: true
              input: [text]
              cost: { input: 1.00, output: 5.00, cacheRead: 0.08, cacheWrite: 1.00 }
              contextWindow: 200000
              maxTokens: 65536

        # Google Gemini direct API. Cheaper than OpenRouter (no $0.005/req
        # surcharge) and one less hop. Same models, same pricing.
        # Requires GEMINI_API_KEY in /run/agenix/llm-runtime-keys.
        # Get one: https://aistudio.google.com/apikey
        google:
          api: google-generative-ai
          baseUrl: https://generativelanguage.googleapis.com/v1beta
          apiKey: GEMINI_API_KEY
          models:
            # Flash Lite — Google's cheapest. $0.10/$0.40 per 1M, 1M context.
            - id: gemini-2.5-flash-lite
              name: Gemini 2.5 Flash Lite (Google)
              reasoning: true
              input: [text]
              cost: { input: 0.10, output: 0.40, cacheRead: 0, cacheWrite: 0 }
              contextWindow: 1048576
              maxTokens: 65536

            # Flash — workhorse multimodal. $0.30/$2.50 per 1M, 1M context.
            - id: gemini-2.5-flash
              name: Gemini 2.5 Flash (Google)
              reasoning: true
              input: [text, image]
              cost: { input: 0.30, output: 2.50, cacheRead: 0.03, cacheWrite: 0.08333 }
              contextWindow: 1048576
              maxTokens: 65536

            # Pro — heavy reasoning. $1.25/$10 per 1M, 1M context.
            - id: gemini-2.5-pro
              name: Gemini 2.5 Pro (Google)
              reasoning: true
              input: [text]
              cost: { input: 1.25, output: 10.00, cacheRead: 0.03125, cacheWrite: 0 }
              contextWindow: 1048576
              maxTokens: 65536
    '';

    ".omp/agent/config.yml".text = ''
      modelRoles:
        #default: vast-vllm/deepseek-v4-flash
        default: deepseek/deepseek-v4-pro
        #smol: office-ollama-cpu/gemma4
        smol: google/gemini-2.5-flash
        slow: anthropic/claude-opus-4-7

      modelProviderOrder:
        - vast-vllm
        - deepseek
        - openrouter
        - office-vllm
        - office-ollama
        - office-ollama-cpu
        - anthropic
        - openai
        - google

      enabledModels:
        - "vast-vllm/*"
        - "deepseek/*"
        - "office-vllm/*"
        - "office-ollama/*"
        - "office-ollama-cpu/*"
        - "anthropic/*"
        - "openrouter/*"
        - "openai/*"
        - "google/*"

      retry:
        enabled: true
        maxRetries: 3
        baseDelayMs: 2000
        fallbackChains:
          default:
            - "deepseek/deepseek-v4-pro"
            - "openrouter/anthropic/claude-sonnet-4-6"
            - "anthropic/claude-sonnet-4-6"
            - "office-ollama/qwen3.6:27b"
          smol:
            - "google/gemini-2.5-flash-lite"
            - "anthropic/claude-haiku-4-5"

      # Tools — enable setting-gated tools that ship disabled by default.
      inspect_image.enabled: true
      calc.enabled: true
      render_mermaid.enabled: true
      checkpoint.enabled: true
      providers.webSearch: brave
    '';

    ".omp/agent/keybindings.json".text = ''
      {
        "app.model.select": ["alt+l"]
      }
    '';

    # UI stats hook — timestamps, turn timing, and tokens/sec in the status bar.
    # Purely observational (no blocking), loaded from extensions/ so it auto-loads
    # with every `omp` invocation (no --hook needed). Reads token usage from
    # turn_end and agent_end events and displays it via ctx.ui.setStatus.
    ".omp/agent/extensions/ui-stats.ts".source = ../../.omp/agent/extensions/ui-stats.ts;
    # System prompt — sourced from GlobalCLAUDE.md at the repo root so both
    # OMP and OpenClaude share the same instructions. Update in one place.
    ".omp/agent/system-prompt.md".text = builtins.readFile ../../GlobalCLAUDE.md;

    # GlobalCLAUDE.md symlinked to ~/.claude/CLAUDE.md so OpenClaude
    # auto-discovers it as user-level instructions (read on every session).
    ".claude/CLAUDE.md".source = ../../GlobalCLAUDE.md;
    # ---- OpenClaude config ----
    # User-level settings. Provider/model selection happens via env vars
    # (loaded by the `openclaude` fish wrapper from /run/agenix/llm-runtime-keys).
    ".openclaude/settings.json".text = ''
      {
        "effortLevel": "medium",
        "theme": "dark",
        "skipAutoPermissionPrompt": true
      }
    '';

    # Keybindings — alt+l opens the model selector.
    ".openclaude/keybindings.json".text = ''
      {
        "app.model.select": ["alt+l"]
      }
    '';
  };
}
