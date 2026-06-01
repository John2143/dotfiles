# Frigate NVR — smart object detection on Reolink RTSP streams.
#
# Runs bare-metal on arch for GPU decode (NVIDIA NVENC/NVDEC) and fast CPU
# detection (OpenVINO on i9-9900K). Recordings + database live on the NAS
# over NFSv4 (10GbE).
#
# Cameras: up to 7 Reolink cameras routed through the Reolink NVR.
# Sub-streams are used for detection (low-res), main streams for clip recording.
#
# === One-time NAS setup ===
#
# On the NAS, before rebuilding:
#   sudo zfs create -o mountpoint=/tank/frigate \
#     -o recordsize=128K -o compression=lz4 -o atime=off tank/frigate
#   sudo chown 1000:1000 /tank/frigate
#
# Then rebuild NAS (adds NFS export) and arch (adds NFS mount + frigate service).
#
# === NVR credentials ===
#
# The RTSP URLs carry credentials. Create secrets/reolink-nvr.age or
# replace CHANGEME below. The password ends up in /nix/store, so agenix
# is recommended for production.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # ── Secrets (replace with agenix) ─────────────────────────────────
  nvrHost = "192.168.1.67";
  nvrUser = "admin";
  nvrPass = "CHANGEME"; # TODO: move to agenix

  # ── MQTT (required for Home Assistant integration) ─────────────────
  mqttHost = "home.ts.2143.me";
  mqttPort = 1883;
  # mqttUser = "frigate";
  # mqttPass = "CHANGEME";

  # ── NAS NFS mount for recordings + database ───────────────────────
  nasFrigatePath = "/mnt/nas/frigate";

  # ── Camera definitions ────────────────────────────────────────────
  # Edit names and stream numbers. Channel N maps to h264Preview_0N.
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
  mkCamera =
    name: cfg: {
      ffmpeg = {
        inputs = [
          {
            # Main stream — recording
            path = "rtsp://${nvrUser}:${nvrPass}@${nvrHost}/h264Preview_${cfg.channel}_main";
            roles = ["record"];
          }
          {
            # Sub stream — detection (low-res, low FPS)
            path = "rtsp://${nvrUser}:${nvrPass}@${nvrHost}/h264Preview_${cfg.channel}_sub";
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

  # Merge cameras into the Frigate settings attrset.
  cameraSettings = builtins.mapAttrs mkCamera cameras;
in {
  # ── NFS mount for Frigate storage ─────────────────────────────────
  fileSystems.${nasFrigatePath} = {
    device = "nas.ts.2143.me:/tank/frigate";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "hard"
      "noatime"
      "nconnect=4"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=10s"
      "x-systemd.mount-timeout=10s"
      "_netdev"
    ];
  };

  # Ensure the mount point directory exists.
  systemd.tmpfiles.rules = [
    "d ${nasFrigatePath} 0755 1000 1000 -"
  ];

  # ── Frigate service ───────────────────────────────────────────────
  services.frigate = {
    enable = true;

    # Hostname for the nginx vhost. Use '_' as catch-all so the UI is
    # reachable at any IP/hostname (arch.local, 192.168.5.226:5000, etc.).
    hostname = "frigate.ts.2143.me";

    # NVIDIA NVENC/NVDEC uses ffmpeg's hwaccel preset, not VA-API.
    # No vaapiDriver needed.
    checkConfig = true;

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

      # Global ffmpeg config — per-camera overrides only need inputs.
      ffmpeg = {
        hwaccel_args = "preset-nvidia-h264";
        output_args = {
          record = "preset-record-generic-audio-copy";
        };
      };

      # go2rtc is bundled with Frigate 0.14+ and provides WebRTC live view.
      # Streams here are pulled once and fanned out to detect + record consumers.
      go2rtc = {
        streams =
          builtins.mapAttrs (
            _: cfg:
              "rtsp://${nvrUser}:${nvrPass}@${nvrHost}/h264Preview_${cfg.channel}_main"
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

  # ── GPU access ────────────────────────────────────────────────────
  # Frigate runs as the 'frigate' user. NVIDIA device nodes are owned
  # by root:video on NixOS. Add frigate to the video group for NVENC/NVDEC.
  users.users.frigate.extraGroups = ["video"];

  # Open port 5000 so the web UI is reachable from the LAN / Tailscale.
  networking.firewall.allowedTCPPorts = [5000 8554 8555];

  # ── agenix placeholder — uncomment and create reolink-nvr.age ─────
  #
  # age.secrets.reolink-nvr = {
  #   file = ../secrets/reolink-nvr.age;
  #   mode = "0400";
  #   owner = "root";
  #   group = "root";
  # };
  #
  # Then replace nvrUser/nvrPass above with a preStart script that
  # sources /run/agenix/reolink-nvr.
}
