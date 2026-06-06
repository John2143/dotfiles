# Frigate NVR — smart object detection on Reolink RTSP streams.
#
# Runs in Podman using the -tensorrt image for NVIDIA GPU-accelerated
# object detection. Recordings + database live on the NAS over NFSv3.
#
# Cameras: up to 7 Reolink cameras routed through the Reolink NVR.
# Main streams are used for both detection and recording (no sub-streams).
#
# === agenix secret ===
#
# Create secrets/reolink-nvr.age containing:
#
#   NVR_USER=admin
#   NVR_PASS=the_password_here
#   NVR_HOST=192.168.1.67
#
#   agenix -e secrets/reolink-nvr.age -i ~/.ssh/id_ed25519 < /tmp/reolink-nvr.env
#
# The Frigate YAML uses ${NVR_PASS} placeholders; envsubst replaces them
# at container startup from the decrypted agenix env file.
#
# === One-time NAS setup ===
#
#   sudo zfs create -o mountpoint=/tank/frigate \
#     -o recordsize=128K -o compression=lz4 -o atime=off tank/frigate
#   sudo chown 1000:1000 /tank/frigate
#
# Then rebuild NAS first (adds NFS export), then arch.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # ── MQTT (required for Home Assistant integration) ─────────────────
  mqttHost = "home.ts.2143.me";
  mqttPort = 1883;

  # ── NAS NFS mount for recordings + database ───────────────────────
  nasFrigatePath = "/mnt/nas/frigate";

  # ── Camera definitions ────────────────────────────────────────────
  # Edit names. Each pulls one RTSP stream from the Reolink NVR:
  #   /h264Preview_0N_main  → detection + recording (full resolution)
  cameras = {
    cam01 = {name = "Camera 1"; channel = "01";};
    cam02 = {name = "Camera 2"; channel = "02";};
    cam03 = {name = "Camera 3"; channel = "03";};
    cam04 = {name = "Camera 4"; channel = "04";};
    cam05 = {name = "Camera 5"; channel = "05";};
    cam06 = {name = "Camera 6"; channel = "06";};
    cam07 = {name = "Camera 7"; channel = "07";};
  };

  # Build a per-camera Frigate config.
  # Uses ${NVR_USER}, ${NVR_PASS}, ${NVR_HOST} placeholders —
  # envsubst fills them at runtime from the agenix env file.
  mkCamera =
    _: cfg: {
      ffmpeg = {
        inputs = [
          {
            path = "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_main";
            roles = ["record" "detect"];
          }
        ];
      };
      detect = {
        width = 2560;
        height = 1440;
        fps = 5;
      };
      record = {
        enabled = true;
        retain = {
          days = 7;
          mode = "motion";
        };
        alerts = {
          pre_capture = 5;
          post_capture = 5;
          retain = {
            days = 30;
            mode = "active_objects";
          };
        };
        detections = {
          pre_capture = 5;
          post_capture = 5;
          retain = {
            days = 30;
            mode = "active_objects";
          };
        };
      };
      snapshots = {
        enabled = true;
        retain = {
          default = 30;
        };
      };
      motion = {};
    };

  cameraSettings = builtins.mapAttrs mkCamera cameras;

  # ── Frigate YAML config (built at Nix build time) ─────────────────
  # The config contains ${NVR_*} placeholders that envsubst replaces
  # at container startup from the agenix secret env file.
  yamlFormat = pkgs.formats.yaml {};

  frigateConfigFile = yamlFormat.generate "frigate-config.yml" {
    mqtt = {
      host = mqttHost;
      port = mqttPort;
    };

    detectors = {
      onnx = {
        type = "onnx";
      };
    };

    model = {
      # YOLOv9-tiny 320x320: the recommended model for GTX 1080 Ti.
      # Build it with Frigate's Dockerfile-based exporter:
      #   https://github.com/blakeblackshear/frigate/blob/dev/docs/docs/configuration/object_detectors.md#models
      path = "/config/model_cache/yolov9-t-320.onnx";
      model_type = "yolo-generic";
      width = 320;
      height = 320;
      input_tensor = "nchw";
      input_dtype = "float";
    };

    ffmpeg = {
      hwaccel_args = "preset-nvidia-h264";
    };

    go2rtc = {
      streams =
        builtins.mapAttrs (
          _: cfg:
            "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_main"
        )
        cameras;
    };

    record = {
      enabled = true;
      retain = {
        days = 7;
        mode = "motion";
      };
    };

    snapshots = {
      enabled = true;
      retain = {
        default = 30;
      };
    };

    cameras = cameraSettings;
  };

  # Bootstrap script that substitutes credentials and starts Frigate.
  # Must use #!/bin/sh (not Nix store bash) since it runs inside the container.
  frigateEntrypoint = pkgs.runCommandLocal "frigate-entrypoint" { } ''
    cat > $out << 'SCRIPT'
#!/bin/sh
set -e
# Copy the Nix-generated config template into the writable /config dir.
# Frigate requires /config to be a mount point; Nix store paths are read-only.
cp /nix-config.yml /config/config.yml.tpl
# Substitute NVR_* placeholders in the config template.
# The env vars (NVR_USER, NVR_PASS, NVR_HOST) are provided by
# the agenix secret via Podman's --env-file.
/usr/local/bin/envsubst < /config/config.yml.tpl > /config/config.yml
# Start Frigate's init process.
exec /init
SCRIPT
    chmod +x $out
  '';
in {
  # ── agenix secret: NVR credentials ─────────────────────────────────
  age.secrets.reolink-nvr = {
    file = ../../secrets/reolink-nvr.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # ── NFS mount for Frigate storage ─────────────────────────────────
  fileSystems.${nasFrigatePath} = {
    device = "192.168.5.175:/tank/frigate";
    fsType = "nfs";
    options = [
      "nfsvers=3"
      "hard"
      "noatime"
      "nolock"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=10s"
      "x-systemd.mount-timeout=10s"
      "_netdev"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${nasFrigatePath} 0755 1000 1000 -"
    "d /var/lib/frigate 0755 1000 1000 -"
  ];

  # ── NVIDIA Container Toolkit for GPU passthrough ──────────────────
  hardware.nvidia-container-toolkit.enable = true;

  # ── Frigate Podman container ──────────────────────────────────────
  virtualisation.oci-containers = {
    backend = "podman";
    containers.frigate = {
      image = "ghcr.io/blakeblackshear/frigate:stable-tensorrt";
      autoStart = true;

      # Load NVR credentials from the decrypted agenix file.
      # This sets NVR_USER, NVR_PASS, NVR_HOST in the container environment.
      environmentFiles = [
        config.age.secrets.reolink-nvr.path
      ];

      volumes = [
        # Writable config directory (local, not NAS — NFS root_squash prevents writes)
        "/var/lib/frigate:/config"
        # Nix-generated config template (copied to /config by entrypoint)
        "${frigateConfigFile}:/nix-config.yml:ro"

        # Bootstrap entrypoint that runs envsubst then execs /init
        "${frigateEntrypoint}:/frigate-entrypoint.sh:ro"
        # Static Go envsubst binary for credential substitution
        "${pkgs.envsubst}/bin/envsubst:/usr/local/bin/envsubst:ro"
        # Recordings and exports on NAS
        "${nasFrigatePath}:/media/frigate"
        # Timezone
        "/etc/localtime:/etc/localtime:ro"
      ];

      extraOptions = [
        # GPU passthrough
        "--device=nvidia.com/gpu=all"
        # Podman security: needed for GPU access
        "--security-opt=label=disable"
        # Map container root to host user (NFS root_squash workaround)
        # Video group for /dev/dri/* (NVIDIA DRM)
        "--group-add=video"
      ];

      # Use our bootstrap script as the container entrypoint
      entrypoint = "/frigate-entrypoint.sh";

      ports = [
        "127.0.0.1:5000:5000"  # Frigate web UI — localhost only
        "8554:8554"             # go2rtc TCP
        "8554:8554/udp"         # go2rtc UDP
        "8555:8555"             # go2rtc TCP
        "8555:8555/udp"         # go2rtc UDP
      ];
    };
  };
}
