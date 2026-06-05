# Frigate NVR — smart object detection on Reolink RTSP streams.
#
# Runs bare-metal on arch for GPU decode (NVIDIA NVENC/NVDEC) and fast CPU
# detection (OpenVINO on i9-9900K). Recordings + database live on the NAS
# over NFSv4 (10GbE).
#
# Cameras: up to 7 Reolink cameras routed through the Reolink NVR.
# Sub-streams are used for detection (low-res), main streams for clip recording.
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
# at service start from the decrypted agenix file.
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
  # mqttUser = "frigate";
  # mqttPass = "CHANGEME";

  # ── NAS NFS mount for recordings + database ───────────────────────
  nasFrigatePath = "/mnt/nas/frigate";

  # ── Camera definitions ────────────────────────────────────────────
  # Edit names. Each pulls two RTSP streams from the Reolink NVR:
  #   /h264Preview_0N_main  → recording (full resolution)
  #   /h264Preview_0N_sub   → detection (low-res, 640x480)
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
  # Uses ${NVR_USER}, ${NVR_PASS}, ${NVR_HOST} shell variables as
  # placeholders — envsubst fills them at runtime from agenix.
  mkCamera =
    _: cfg: {
      ffmpeg = {
        inputs = [
          {
            path = "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_main";
            roles = ["record"];
          }
          {
            path = "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_sub";
            roles = ["detect"];
          }
        ];
      };
      detect = {
        width = 640;
        height = 480;
        fps = 5;
      };
      record = {
        enabled = true;
        retain = {
          days = 7;
          mode = "motion";
        };
        events = {
          pre_capture = 5;
          post_capture = 5;
          retain = {
            default = 30;
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
  ];

  # ── Frigate service ───────────────────────────────────────────────
  services.frigate = {
    enable = true;
    hostname = "frigate.ts.2143.me";
    checkConfig = false; # disabled: config contains ${PLACEHOLDER} strings
                         # that will fail YAML validation at build time.

    settings = {
      database = {
        path = "${nasFrigatePath}/frigate.db";
      };

      mqtt = {
        enabled = true;
        host = mqttHost;
        port = mqttPort;
        # user = mqttUser;
        # password = mqttPass;
      };

      detectors = {
        ov = {
          type = "openvino";
          device = "CPU";
        };
      };

      ffmpeg = {
        hwaccel_args = "preset-nvidia-h264";
        output_args = {
          record = "preset-record-generic-audio-copy";
        };
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

      version = "0.17";
    };
  };

  # ── Credential injection at runtime ───────────────────────────────
  # The Frigate YAML in /nix/store has ${NVR_PASS} etc. as literal text.
  # envsubst replaces them when the service starts, using the agenix
  # decrypted env file.
  #
  # We insert our ExecStartPre AFTER the module's own "copy config" step
  # so the substitution happens on the writable copy in /run/frigate/.

  systemd.services.frigate = {
    # Load the decrypted credentials into the service's environment.
    serviceConfig.EnvironmentFile = [
      config.age.secrets.reolink-nvr.path
    ];

    # Append envsubst AFTER the module's ExecStartPre (which copies
    # the config to /run/frigate/frigate.yml). We use mkAfter on
    # serviceConfig.ExecStartPre because preStart prepends (wrong order).
    serviceConfig.ExecStartPre = lib.mkAfter [
      (pkgs.writeShellScript "frigate-envsubst-config" ''
        if [ -f /run/frigate/frigate.yml ]; then
          ${pkgs.envsubst}/bin/envsubst \
            < /run/frigate/frigate.yml \
            > /run/frigate/frigate.yml.tmp \
          && mv /run/frigate/frigate.yml.tmp /run/frigate/frigate.yml
        fi
      '')
    ];

  # ── GPU access ────────────────────────────────────────────────────
  users.users.frigate.extraGroups = ["video"];

  # Open Frigate web UI (5000) and go2rtc (8554/8555).
  networking.firewall.allowedTCPPorts = [5000 8554 8555];
}
