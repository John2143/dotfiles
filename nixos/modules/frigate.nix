# Frigate NVR — smart object detection on Reolink RTSP streams.
#
# Runs in Podman using the -tensorrt image for NVIDIA GPU-accelerated
# object detection. Recordings + database live on the NAS over NFSv3.
#
# Cameras: 6 Reolink cameras routed through the Reolink NVR + 1 direct RTSP.


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
    cam01 = {name = "Camera 1"; channel = "01"; codec = "hevc"; detectWidth = 1920; detectHeight = 1080; lprEnable = true;};
    cam02 = {name = "Camera 2"; channel = "02"; codec = "hevc"; detectWidth = 1920; detectHeight = 1080;};
    cam03 = {name = "Camera 3"; channel = "03"; stream = "sub"; detectFps = 2;};
    # cam04 is sideways (rotated 270°). Sub-stream via NVR, no rotation for now.
    cam04 = { name = "Camera 4"; channel = "04"; stream = "sub"; detectWidth = 1920; detectHeight = 1080; detectFps = 2; };



    cam05 = {name = "Camera 5"; channel = "05"; stream = "sub"; detectHeight = 1920;};
    cam06 = {name = "Camera 6"; channel = "06"; codec = "hevc"; detectWidth = 1920; detectHeight = 1080; detectFps = 2; lprEnable = true;};

    # cam08 is a direct RTSP camera (not routed through the Reolink NVR).
    cam08 = {name = "Camera 8"; rtspPath = "rtsp://\${EUFY_USER}:\${EUFY_PASS}@192.168.5.59/live0"; detectWidth = 1920; detectHeight = 1080; detectFps = 1;};



  };

  # Build a per-camera Frigate config.
  # Uses ${NVR_USER}, ${NVR_PASS}, ${NVR_HOST} placeholders —
  # envsubst fills them at runtime from the agenix env file.
  mkCamera =
    _: cfg: {
      ffmpeg = {
        hwaccel_args =
          if cfg.codec or "h264" == "hevc"
          then "preset-nvidia-h265"

          else "preset-nvidia-h264";
        inputs = [
          ({
            path =
              if cfg ? rtspPath
              then cfg.rtspPath
              else "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_${cfg.stream or "main"}";
            roles = ["record" "detect"];
          } // lib.optionalAttrs (cfg ? inputArgs) { input_args = cfg.inputArgs; })
        ];

      } // lib.optionalAttrs (cfg ? outputArgs) { output_args = cfg.outputArgs; };
      detect = {
        enabled = cfg.detectEnabled or true;
        width = cfg.detectWidth or 2560;
        height = cfg.detectHeight or 1440;
        fps = cfg.detectFps or 5;
      };

      record = {
        enabled = true;
        events = {
          pre_capture = 5;
          post_capture = 5;
          retain = {
            default = 7;
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
      objects = {
        track = ["person" "bicycle" "car" "motorcycle" "bus" "truck" "bird" "cat" "dog" "bear"];
      };
      lpr = {
        enabled = cfg.lprEnable or false;
      };
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
      onnx_0 = {
        type = "onnx";
      };
      onnx_1 = {
        type = "onnx";
      };
    };
    model = {
      path = "/config/model_cache/yolov9-c-640.onnx";
      model_type = "yolo-generic";
      width = 640;
      height = 640;
      input_tensor = "nchw";
      input_dtype = "float";
    };
    face_recognition = {
      enabled = true;
      model_size = "large";
      detection_threshold = 0.7;
      recognition_threshold = 0.9;
      min_area = 500;
      device = "GPU";
    };
    lpr = {
      enabled = true;
      model_size = "large";
      detection_threshold = 0.7;
      recognition_threshold = 0.9;
      device = "GPU";
    };



    go2rtc = {
      streams =
        builtins.mapAttrs (
          _: cfg:
            (cfg.go2rtcPrefix or "")
            + (if cfg ? rtspPath then cfg.rtspPath
            else "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_${cfg.stream or "main"}")
            + (cfg.go2rtcSuffix or "")
          ) cameras;
    };

    record = {
      enabled = true;
      events = {
        retain = {
          default = 7;
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
  # Podman looks for CDI specs in /etc/cdi, but NixOS generates them in /run/cdi.
  environment.etc."cdi/nvidia-container-toolkit.json".source = "/run/cdi/nvidia-container-toolkit.json";
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
        # 7 cameras × 1440p: Frigate recommends ≥994MB SHM. Use 2GB for headroom.
        "--shm-size=2g"
        # Podman security: needed for GPU access
        "--security-opt=label=disable"
        # Map container root to host user (NFS root_squash workaround)
        # Video group for /dev/dri/* (NVIDIA DRM)
        "--group-add=video"
      ];

      # Use our bootstrap script as the container entrypoint
      entrypoint = "/frigate-entrypoint.sh";

      ports = [
        "127.0.0.1:5000:5000"  # Frigate web UI — localhost
        "100.64.0.1:5000:5000"  # Frigate web UI — Tailscale
        "8554:8554"             # go2rtc TCP
        "8554:8554/udp"         # go2rtc UDP
        "8555:8555"             # go2rtc TCP
        "8555:8555/udp"         # go2rtc UDP
      ];
    };
  };
  # ── Auto-build YOLOv9 ONNX model if missing ──────────────────────
  systemd.services.build-frigate-model = {
    description = "Build Frigate YOLOv9 ONNX model if missing";
    wantedBy = ["multi-user.target"];
    before = ["podman-frigate.service"];
    path = [ pkgs.podman ];
    script = ''
      MODEL=/var/lib/frigate/model_cache/yolov9-c-640.onnx
      if [ -f "$MODEL" ]; then
        echo "Model already exists at $MODEL"
        exit 0
      fi
      echo "Building YOLOv9-c-640 ONNX model (this may take ~15 minutes)..."
      mkdir -p /var/lib/frigate/model_cache
      podman build \
        --build-arg MODEL_SIZE=c \
        --build-arg IMG_SIZE=640 \
        --output type=local,dest=/var/lib/frigate/model_cache \
        -f ${../frigate/Dockerfile.yolov9} \
        /tmp
      chown 1000:1000 "$MODEL"
      echo "Model built: $(ls -lh "$MODEL" | awk '{print $5}')"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 1800;
      User = "root";
    };
  };

  systemd.services."podman-frigate" = {
    after = [ "build-frigate-model.service" ];
    requires = [ "build-frigate-model.service" ];
  };
}
