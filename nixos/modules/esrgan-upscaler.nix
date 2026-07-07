{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.esrgan-upscaler;
in {
  options.services.esrgan-upscaler = {
    enable = lib.mkEnableOption "Real-ESRGAN image upscaling service (podman + ROCm)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7870;
      description = "TCP port for the upscale API.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/john2143/real-esrgan-api:latest";
      description = "OCI image for the Real-ESRGAN upscaler.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "RealESRGAN_x4plus";
      description = ''
        Real-ESRGAN model name. Options:
        - RealESRGAN_x4plus (default, general 4x)
        - RealESRGAN_x4plus_anime (anime-optimized 4x)
        - RealESRGAN_x2plus (2x upscaling)
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the upscale port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Podman is required for the container runtime.
    virtualisation.podman.enable = true;

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
    ];

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.esrgan-upscaler = {
      image = cfg.image;
      ports = ["${toString cfg.port}:${toString cfg.port}"];
      extraOptions = [
        # ROCm GPU passthrough — same pattern as vllm.nix gpuBackend="rocm"
        "--device=/dev/kfd"
        "--device=/dev/dri"
        "--group-add=video"
        "--group-add=render"
        "--ipc=host"
      ];
      environment = {
        ESRGAN_MODEL = cfg.model;
      };
      autoStart = true;
    };

    # Restart the container on failure (oci-containers default is no restart).
    systemd.services."podman-esrgan-upscaler" = {
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
