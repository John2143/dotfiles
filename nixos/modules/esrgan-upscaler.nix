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
      default = "localhost/real-esrgan-api:latest";
      description = "OCI image for the Real-ESRGAN upscaler. Defaults to local image; tag your build with 'localhost/real-esrgan-api:latest'.";
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

    # Auto-build the container image as root if it doesn't exist yet.
    # NixOS runs podman containers as root, so user-built images are invisible.
    system.activationScripts.esrgan-upscaler-build = let
      buildDir = pkgs.runCommand "esrgan-upscaler-build-context" {} ''
        mkdir -p $out
        cp ${./../../containers/real-esrgan/Dockerfile} $out/Dockerfile
        cp ${./../../containers/real-esrgan/server.py} $out/server.py
        cp ${./../../containers/real-esrgan/download_weights.py} $out/download_weights.py
      '';
    in ''
      if ! podman image exists localhost/real-esrgan-api:latest; then
        echo "[esrgan-upscaler] Building container image (this may take a while)..."
        podman build -t localhost/real-esrgan-api:latest ${buildDir}
        echo "[esrgan-upscaler] Build complete."
      fi
    '';
    virtualisation.oci-containers.containers.esrgan-upscaler = {
      image = cfg.image;
      ports = ["${toString cfg.port}:${toString cfg.port}"];
      extraOptions = [
        # ROCm GPU passthrough — same pattern as vllm.nix gpuBackend="rocm"
        "--device=/dev/kfd"
        "--device=/dev/dri"
        # Use numeric GIDs; group names may not resolve inside the container
        "--group-add=26"
        "--group-add=303"
        "--ipc=host"
        "--pull=never"
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
