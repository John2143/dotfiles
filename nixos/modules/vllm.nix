# vLLM serving module — runs vLLM in a podman container on NVIDIA GPUs.
#
# === Why vLLM instead of Ollama for Qwen? ===
#
#   Ollama's Qwen tool calling has known reliability issues:
#   - Tool calls sometimes leak as plain text (ollama#14745)
#   - finish_reason wrong when tool calls present
#   - Template bugs cause think tags to poison context
#
#   vLLM with the qwen3_xml parser and a fixed Jinja template
#   (froggeric/Qwen-Fixed-Chat-Templates) fixes all of these.
#   See: https://www.reddit.com/r/Vllm/comments/1skks8n/
#
# === Requirements ===
#
#   - NVIDIA GPU (gpuBackend = "nvidia", default) or AMD ROCm GPU (gpuBackend = "rocm")
#   - podman or docker enabled
#   - nvidia-container-toolkit enabled (NVIDIA only)
#   - Enough VRAM for the model (Qwen3.6-35B-A3B needs ~21GB in AWQ/int4)
#
# === Usage ===
#
#   services.vllm = {
#     enable = true;
#     model = "Qwen/Qwen3.6-35B-A3B";
#     chatTemplate = ../references/qwen3.6-chat-template.jinja;
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vllm;

  # Copy the template into the Nix store so the container can mount it.
  templateDrv =
    if cfg.chatTemplate != null
    then
      pkgs.writeText "vllm-chat-template.jinja" (builtins.readFile cfg.chatTemplate)
    else null;
in {
  options.services.vllm = {
    enable = lib.mkEnableOption "vLLM model serving via podman container";

    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen/Qwen3.6-35B-A3B";
      description = "HuggingFace model identifier to serve.";
    };

    servedModelName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Name exposed via the OpenAI-compatible API. Defaults to the model identifier.";
    };

    chatTemplate = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a Jinja chat template file. When set, overrides the model's built-in template.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "TCP port for the OpenAI-compatible API.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall for the vLLM port.";
    };

    toolCallParser = lib.mkOption {
      type = lib.types.str;
      default = "qwen3_xml";
      description = ''
        Tool call parser. qwen3_xml uses C-based xml.parsers.expat — more
        robust than qwen3_coder's regex for nested JSON and special characters.
      '';
    };

    reasoningParser = lib.mkOption {
      type = lib.types.str;
      default = "qwen3";
      description = "Reasoning content parser.";
    };

    maxModelLen = lib.mkOption {
      type = lib.types.int;
      default = 65536;
      description = "Maximum context length. Lower values save VRAM.";
    };

    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.str;
      default = "0.90";
      description = "Fraction of GPU memory to use (0.0-1.0).";
    };

    maxNumSeqs = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Maximum concurrent sequences.";
    };

    kvCacheDtype = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "KV cache data type (e.g. fp8). Null uses model default.";
      example = "fp8";
    };

    languageModelOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Skip loading the vision encoder to save memory. Set false for multimodal use.";
    };

    gpuBackend = lib.mkOption {
      type = lib.types.enum ["nvidia" "rocm"];
      default = "nvidia";
      description = "GPU backend. 'nvidia' uses nvidia-container-toolkit; 'rocm' passes /dev/kfd and /dev/dri.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "vllm/vllm-openai:latest";
      description = "OCI image for vLLM. vllm/vllm-openai:latest for NVIDIA; vllm/vllm-openai-rocm:latest for ROCm.";
    };

    huggingfaceCacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/john/.cache/huggingface";
      description = "Host path for the HuggingFace model cache.";
    };

    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Extra environment variables for the vLLM container.";
      example = {
        VLLM_TEST_FORCE_FP8_MARLIN = "1";
      };
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra CLI arguments appended to the vllm serve command.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Require podman for the container runtime.
    virtualisation.podman = {
      enable = true;
      dockerCompat = lib.mkDefault true;
    };

    # NVIDIA container toolkit so --gpus=all works inside podman.
    hardware.nvidia-container-toolkit.enable = lib.mkIf (cfg.gpuBackend == "nvidia") true;

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.tmpfiles.rules = [
      "d ${cfg.huggingfaceCacheDir} 0755 john users -"
    ];

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.vllm = {
      image = cfg.image;
      ports = ["${toString cfg.port}:${toString cfg.port}"];
      extraOptions =
        (
          if cfg.gpuBackend == "nvidia"
          then ["--device=nvidia.com/gpu=all"]
          else ["--device=/dev/kfd" "--device=/dev/dri" "--group-add=video" "--group-add=render"]
        )
        ++ ["--ipc=host"];
      volumes =
        [
          "${cfg.huggingfaceCacheDir}:/root/.cache/huggingface"
        ]
        ++ lib.optionals (templateDrv != null) [
          "${templateDrv}:/app/chat-template.jinja:ro"
        ];
      environment = cfg.environmentVariables;
      cmd =
        ["--model" cfg.model]
        ++ ["--host" "0.0.0.0"]
        ++ ["--port" (toString cfg.port)]
        ++ ["--trust-remote-code"]
        ++ ["--enable-auto-tool-choice"]
        ++ ["--tool-call-parser" cfg.toolCallParser]
        ++ ["--reasoning-parser" cfg.reasoningParser]
        ++ ["--max-model-len" (toString cfg.maxModelLen)]
        ++ ["--gpu-memory-utilization" cfg.gpuMemoryUtilization]
        ++ ["--max-num-seqs" (toString cfg.maxNumSeqs)]
        ++ ["--enable-prefix-caching"]
        ++ lib.optionals (cfg.servedModelName != null) [
          "--served-model-name" cfg.servedModelName
        ]
        ++ lib.optionals (templateDrv != null) [
          "--chat-template" "/app/chat-template.jinja"
        ]
        ++ lib.optionals (cfg.kvCacheDtype != null) [
          "--kv-cache-dtype" cfg.kvCacheDtype
        ]
        ++ lib.optionals cfg.languageModelOnly [
          "--language-model-only"
        ]
        ++ cfg.extraArgs;
    };
  };
}
