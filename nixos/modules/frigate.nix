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
    # Main: 3840x2160 4K HEVC 25fps  Sub: 640x360 H264 25fps
    cam01 = {
      name = "Camera 1";
      channel = "01"; codec = "hevc";
      detectWidth = 1920; detectHeight = 1080;
      audioEnabled = true;
      lprQuality = true;
      motionMask = [
        "0.998,0.275,0.716,0.186,0.675,0.1,0.637,0.086,0.587,0.075,0.549,0.102,0.524,0.111,0.491,0.106,0.449,0.097,0.405,0.102,0.377,0.097,0.337,0.102,0.31,0.11,0.27,0.106,0.253,0.104,0.219,0.101,0.215,0.073,0.196,0.075,0.181,0.09,0.166,0.11,0.146,0.116,0.123,0.12,0.104,0.117,0.061,0.111,0.023,0.097,0.002,0.095,0,0.004,0.998,0"
        "0.421,0.674,0.209,0.828,0.3,0.991,0.451,0.997,0.64,0.998,0.676,0.757,0.513,0.679,0.472,0.763"
        "0.792,0.733,0.716,0.814,0.719,0.87,0.723,0.917,0.681,0.947,0.669,0.997,0.835,0.99"
        "0.219,0.1,0.214,0.14,0.23,0.202,0.264,0.173,0.288,0.183,0.292,0.146,0.321,0.153,0.362,0.151,0.367,0.123,0.357,0.103"
        "0.53,0.27,0.488,0.34,0.464,0.42,0.469,0.442,0.485,0.467,0.477,0.505,0.509,0.509,0.542,0.444,0.548,0.399,0.542,0.364"
      ];
      personMask = [
        "0.514,0.183,0.495,0.199,0.498,0.27,0.511,0.323,0.541,0.327,0.546,0.306,0.546,0.265,0.544,0.248,0.535,0.248,0.526,0.226"
        "0.573,0.243,0.571,0.3,0.592,0.289,0.594,0.231"
      ];
      zones = {
        inside_walkway_to_house = {
          friendly_name = "Inside Walkway to house";
          loitering_time = 1;
          coordinates = "0.437,0.47,0.31,0.55,0.23,0.633,0.103,0.721,0.054,0.744,0.013,0.766,0.001,0.773,0,0.999,0.293,0.994,0.198,0.848,0.486,0.617,0.627,0.532,0.541,0.327";
        };
        in_court = {
          friendly_name = "In Court";
          loitering_time = 0;
          coordinates = "0.533,0.288,0.605,0.318,0.653,0.334,0.716,0.352,0.784,0.373,0.856,0.399,0.926,0.417,0.999,0.551,0.996,0.998,0.887,0.993,0.86,0.926,0.835,0.876,0.813,0.842,0.788,0.793,0.759,0.744,0.744,0.723,0.723,0.678,0.696,0.642,0.665,0.579,0.632,0.517,0.609,0.46,0.592,0.422,0.575,0.382,0.556,0.319";
        };
        road_speed_zone = {
          friendly_name = "Road Speed Zone";
          loitering_time = 0;
          speed_threshold = 10;
          distances = "8.75,11.51,8.7,14.75";
          coordinates = "0.644,0.214,0.642,0.268,0.899,0.366,0.902,0.321";
        };
      };
    };
    # Main: 3840x2160 4K HEVC 25fps  Sub: 640x360 H264 25fps
    cam02 = {
      name = "Camera 2";
      channel = "02"; codec = "hevc";
      detectWidth = 1920; detectHeight = 1080;
      motionMask = [
        "0.401,0.023,0.323,0.27,0.28,0.419,0.295,0.464,0.308,0.475,0.315,0.516,0.312,0.56,0.301,0.567,0.277,0.57,0.252,0.576,0.233,0.59,0.205,0.636,0.163,0.704,0.118,0.842,0.1,0.993,0.595,0.999,0.597,0.89,0.59,0.856,0.575,0.836,0.559,0.817,0.548,0.785,0.541,0.757,0.538,0.732,0.534,0.705,0.526,0.688,0.515,0.682,0.502,0.67,0.496,0.661,0.491,0.652,0.486,0.641,0.482,0.627,0.478,0.608,0.475,0.583,0.472,0.563,0.471,0.544,0.458,0.523,0.454,0.503,0.453,0.481,0.45,0.456,0.45,0.403,0.45,0.369,0.452,0.342,0.455,0.32,0.46,0.295,0.462,0.271,0.462,0.256,0.461,0.239,0.448,0.217,0.425,0.189,0.419,0.073"
        "0.546,0.643,0.615,0.836,0.67,0.873,0.732,0.869,0.77,0.782,0.783,0.712,0.761,0.664,0.752,0.589,0.755,0.542,0.765,0.487,0.772,0.435,0.772,0.382,0.762,0.354,0.739,0.288,0.731,0.256,0.656,0.404,0.613,0.483,0.602,0.526,0.564,0.601"
        "0.237,0.4,0.175,0.349,0.149,0.351,0.128,0.398,0.099,0.46,0.087,0.501,0.078,0.525,0.044,0.586,0.021,0.622,0.003,0.676,0.001,0.993,0.047,0.999,0.081,0.936,0.12,0.829,0.145,0.76,0.175,0.654,0.217,0.55,0.245,0.406"
      ];
      zones = {
        side_door = {
          friendly_name = "Side Door";
          loitering_time = 0;
          coordinates = "0.965,0.117,0.539,0.519,0.42,0.588,0.468,0.731,0.524,0.895,0.559,0.997,0.999,0.994";
        };
        in_court = {
          friendly_name = "In Court";
          loitering_time = 0;
          coordinates = "0.387,0.004,0.048,0.993,0,0.999,0.001,0.002";
        };
        in_back_yard = {
          friendly_name = "In Back Yard";
          loitering_time = 0;
          coordinates = "0.405,0.027,0.317,0.303,0.242,0.579,0.177,0.807,0.135,0.99,0.229,0.998,0.282,0.996,0.354,0.991,0.382,0.756,0.387,0.595,0.423,0.56,0.48,0.557,0.519,0.519,0.542,0.437,0.528,0.34,0.511,0.212,0.488,0.14,0.501,0.083,0.512,0.045,0.516,0.019,0.519,0.002";
        };
      };
    };
    # Main: 2560x1440 H264 15fps  Sub: 640x360 H264 10fps
    cam03 = {name = "Camera 3"; channel = "03"; stream = "sub";};
    # Sideways (rotated 270°).  Main: 2160x7680 HEVC 25fps  Sub: 1536x432 H264 25fps
    cam04 = {
      name = "Camera 4";
      channel = "04"; stream = "sub"; codec = "h264";
      detectWidth = 1920; detectHeight = 1080;
      motionMask = [
        "0.147,0.004,0.119,0.041,0.105,0.071,0.092,0.101,0.081,0.124,0.078,0.166,0.077,0.228,0.084,0.271,0.098,0.302,0.121,0.342,0.135,0.378,0.158,0.395,0.176,0.393,0.189,0.383,0.204,0.37,0.221,0.351,0.232,0.34,0.244,0.321,0.242,0.285,0.237,0.103,0.314,0.085,0.358,0.082,0.374,0.003"
        "0.112,0.322,0.001,0.411,0.001,0.175,0.063,0.158"
        "0.497,0.511,0.363,0.714,0.386,0.866,0.405,0.899,0.419,0.914,0.454,0.922,0.491,0.909,0.518,0.866,0.54,0.829,0.557,0.79,0.571,0.745,0.578,0.69,0.577,0.639,0.569,0.592,0.554,0.573,0.541,0.559"
        "0.759,0.633,0.726,0.588,0.701,0.611,0.691,0.66,0.676,0.73,0.673,0.782,0.678,0.835,0.678,0.896,0.714,0.893,0.748,0.813"
        "0.666,0.258,0.784,0.361,0.825,0.199,0.91,0.257,0.948,0.132,0.958,0.125,0.937,0.038,0.896,0.113,0.879,0.09,0.859,0.071,0.843,0.092,0.842,0.11,0.831,0.103,0.814,0.083,0.803,0.07,0.797,0.053,0.795,0.037,0.796,0,0.711,0,0.707,0.095,0.677,0.121"
      ];
    };
    # Main: 2560x1920 H264 25fps  Sub: 640x480 H264 10fps
    cam05 = {
      name = "Camera 5";
      channel = "05"; stream = "sub"; codec = "h264";
      detectWidth = 2560; detectHeight = 1920;
      motionMask = [
        "0.607,0.339,0.592,0.32,0.563,0.325,0.532,0.331,0.517,0.34,0.489,0.362,0.477,0.387,0.472,0.44,0.483,0.476,0.503,0.506,0.53,0.519,0.576,0.518,0.604,0.509,0.616,0.485,0.625,0.462,0.627,0.431,0.614,0.375"
        "0.729,0.146,0.756,0.206,0.78,0.22,0.83,0.265,0.864,0.302,0.904,0.348,0.976,0.394,1,0.421,1,0,0.744,0.05"
        "0.455,0.125,0.496,0.135,0.507,0.138,0.51,0.147,0.517,0.152,0.524,0.149,0.534,0.146,0.542,0.139,0.552,0.133,0.558,0.121,0.562,0.106,0.57,0.1,0.583,0.105,0.6,0.102,0.616,0.101,0.624,0.098,0.635,0.096,0.644,0.093,0.657,0.036,0.456,0.026"
        "0.66,0.322,0.61,0.331,0.595,0.324,0.587,0.294,0.592,0.268,0.608,0.191,0.63,0.167,0.655,0.162,0.703,0.173,0.733,0.211,0.736,0.29,0.738,0.315,0.755,0.318,0.776,0.326,0.794,0.341,0.806,0.374,0.814,0.41,0.833,0.464,0.823,0.522,0.809,0.548,0.791,0.547,0.765,0.523,0.73,0.505,0.725,0.476,0.713,0.425,0.706,0.394"
        "0.817,0.246,0.809,0.309,0.816,0.331,0.837,0.353,0.86,0.401,0.887,0.489,0.913,0.532,0.938,0.601,0.974,0.632,1,0.639,1,0.405"
      ];
      zones = {
        front_door = {
          friendly_name = "Front Door";
          loitering_time = 0;
          coordinates = "0.244,0.129,0.312,0.125,0.342,0.5,0.312,0.537,0.274,0.529";
        };
        porch = {
          friendly_name = "Porch";
          loitering_time = 0;
          coordinates = "0.774,0.777,0.244,0.611,0.242,0.362,0.345,0.31,0.39,0.327,0.425,0.391,0.478,0.413,0.548,0.428,0.653,0.458,0.764,0.481";
        };
      };
    };
    # Main: 4512x2512 HEVC 25fps  Sub: 896x512 H264 25fps
    cam06 = {
      name = "Camera 6";
      channel = "06"; codec = "hevc";
      detectWidth = 1920; detectHeight = 1080;
      lprQuality = true;
      motionMask = [
        "0.15,0.482,0.143,0.364,0.126,0.301,0.15,0.293,0.176,0.26,0.18,0.224,0.199,0.168,0.204,0.128,0.206,0.071,0.196,0.041,0.187,0.016,0.178,0.004,0,0.001,0.001,0.265,0.021,0.28,0.036,0.296,0.038,0.326,0.044,0.365,0.051,0.413,0.061,0.446,0.071,0.485,0.087,0.501,0.104,0.503,0.125,0.508"
        "0.245,0.022,0.244,0.104,0.257,0.168,0.277,0.214,0.3,0.228,0.323,0.197,0.343,0.174,0.363,0.163,0.382,0.163,0.392,0.183,0.406,0.192,0.429,0.192,0.448,0.187,0.469,0.179,0.486,0.169,0.506,0.165,0.519,0.159,0.531,0.168,0.543,0.182,0.553,0.194,0.57,0.206,0.586,0.224,0.595,0.229,0.608,0.227,0.62,0.215,0.631,0.198,0.663,0.078,0.647,0.037,0.622,0.007,0.247,0.001"
      ];
      zones = {
        house = {
          friendly_name = "House";
          loitering_time = 0;
          coordinates = "0.725,0.101,0.721,0.276,0.811,0.352,0.879,0.393,0.94,0.45,0.983,0.482,1,0.501,1,0.209,0.88,0.107";
        };
        driveway_gate = {
          friendly_name = "Driveway Gate";
          loitering_time = 0;
          coordinates = "0.001,0.424,0.145,0.375,0.181,0.361,0.249,0.342,0.312,0.329,0.328,0.329,0.337,0.403,0.359,0.492,0.38,0.609,0.401,0.739,0.424,0.885,0.439,0.978,0.001,0.999";
        };
        front_driveway = {
          friendly_name = "Front Driveway";
          loitering_time = 0;
          coordinates = "0.778,0.317,0.433,0.534,0.549,0.993,0.824,0.981,0.995,0.791,0.987,0.511,0.953,0.46";
        };
      };
    };
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
        inputs =
          if cfg ? lprQuality && cfg.lprQuality then [
            # Sub stream for detection (low GPU load)
            ({
              path = "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_sub";
              roles = ["detect"] ++ lib.optional (cfg.audioEnabled or false) "audio";
            } // lib.optionalAttrs (cfg ? inputArgs) { input_args = cfg.inputArgs; })
            # Main stream for recording + LPR (full resolution)
            ({
              path = "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_main";
              roles = ["record"];
            } // lib.optionalAttrs (cfg ? inputArgs) { input_args = cfg.inputArgs; })
          ] else [
          ({
            path =
              if cfg ? rtspPath
              then cfg.rtspPath
              else "rtsp://\${NVR_USER}:\${NVR_PASS}@\${NVR_HOST}/h264Preview_${cfg.channel}_${cfg.stream or "main"}";
            roles = ["record" "detect"] ++ lib.optional (cfg.audioEnabled or false) "audio";
          } // lib.optionalAttrs (cfg ? inputArgs) { input_args = cfg.inputArgs; })
        ];

      } // lib.optionalAttrs (cfg ? outputArgs) { output_args = cfg.outputArgs; };
      detect = {
        enabled = cfg.detectEnabled or true;
        width = cfg.detectWidth or 2560;
        height = cfg.detectHeight or 1440;
        fps = cfg.detectFps or 6;
      };

      record = {
        enabled = true;
        events = {
          pre_capture = 3;
          post_capture = 3;
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
      motion = {} // lib.optionalAttrs (cfg ? motionMask) {
        mask = cfg.motionMask;
      };
      objects = {
        track = [
          # People & Vehicles
          "person" "car" "motorcycle" "bicycle" "truck" "bus" "school_bus" "boat"
          # Animals
          "bird" "cat" "dog" "deer" "horse" "bear" "cow" "fox" "raccoon"
          # Deliveries & Logos
          "face" "license_plate" "package" "amazon" "fedex" "ups" "usps"
          "dhl" "an_post" "purolator" "postnl" "nzpost" "postnord" "gls"
          "dpd" "royal_mail" "canada_post" "other"
          # Objects
          "waste_bin" "bbq_grill" "robot_lawnmower" "umbrella"
        ];
        genai = {
          enabled = true;
        };
      } // lib.optionalAttrs (cfg ? personMask) {
        filters = {
          person = {
            mask = cfg.personMask;
          };
        };
      };
      lpr = {
        enabled = true;
      };
    } // lib.optionalAttrs (cfg ? zones) {
      zones = cfg.zones;
    } // lib.optionalAttrs (cfg.audioEnabled or false) {
      audio = {
        enabled = true;
        listen = ["bark" "scream" "speech" "yell"];
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
    };
    model = {
      # Downgrade: path = "/config/model_cache/yolov9-c-640.onnx"; model_type = "yolo-generic"; width = 640; height = 640; input_tensor = "nchw"; input_dtype = "float";

      # 2026-04-15 base: plus://3468817eacc0ca053c0256a2113b1c04 (yolonas 640x640, generic)
      # 2026-06-28 fine-tuned: plus://1ca03994c082c07c73d984000135929d (640x640, 155 annotated images)
      path = "plus://1ca03994c082c07c73d984000135929d";
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

    genai = {
      provider = "ollama";
      base_url = "http://100.64.0.3:11434";
      model = "huihui_ai/qwen3-vl-abliterated:8b";
    };
    classification = {
      bird = {
        enabled = true;
      };
      # Custom MobileNetV2 classifiers — train in Frigate UI (Classification page)
      # custom = {
      #   <model_name> = {
      #     threshold = 0.8;
      #     object_config = {
      #       objects = [ "person" ];   # which tracked object to classify
      #       classification_type = "sub_label";  # or "attribute"
      #     };
      #   };
      # };
    };
    semantic_search = {
      enabled = true;
      model_size = "large";
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
# Patch GenAI timeout to 600s — requests queue behind each other with num_parallel=1
sed -i 's/timeout: int = 120)/timeout: int = 600)/' /opt/frigate/frigate/genai/__init__.py
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
  age.secrets.frigate-plus = {
    file = ../../secrets/frigate-plus.age;
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
        config.age.secrets.frigate-plus.path
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
  /*
  # ── Downgrade to YOLOv9 (uncomment all lines between START/END) ──
  systemd.services.build-frigate-model = {
    description = "Build Frigate YOLOv9 ONNX model if missing";
    wantedBy = ["multi-user.target"];
    before = ["podman-frigate.service"];
    path = [ pkgs.podman ];
    script = '''
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
    ''';
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
  */
}
