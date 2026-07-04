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
  mqttHost = "192.168.5.76";
  mqttPort = 31883;
  mqttUser = "frigate";
  mqttPass = "pT2hmIXUXN4IkhdCGy3frXEmKYY";  # Mosquitto on argo/k8s — rotate via agenix later

  # ── NAS NFS mount for recordings + database ───────────────────────
  nasFrigatePath = "/mnt/nas/frigate";

  # ── Object labels ─────────────────────────────────────────────────
  objectLabels = rec {
    all = [
      # People & Vehicles
      "person" "car" "motorcycle" "bicycle" "school_bus" "boat"
      # Animals
      "bird" "cat" "dog" "deer" "horse" "bear" "cow" "fox" "raccoon"
      "face" "license_plate" "package" "amazon" "fedex" "ups" "usps"
      "dhl" "an_post" "purolator" "postnl" "nzpost" "postnord" "gls"
      "dpd" "royal_mail" "canada_post"
      # Objects
      "robot_lawnmower" "umbrella"
    ];
    unused = [ "truck" "other" "bus" ];
    # dont need to ML label all cars
    excludeFromDescribe = [ "car" "waste_bin" "bbq_grill" ];
    describe = lib.subtractLists excludeFromDescribe all;
  };

  # ── GenAI prompt templates (composed per-camera + per-label) ─────
  genaiPrompts = rec {
    base = ''
      You are a security camera analysis tool. You will see a
      chronological sequence of full camera frames, and then a final frame with
      a bounding box around a detected object. The bounding box is labeled with
      a {label}.

      FIRST: State exactly how many image frames you received. Example: "Frames
      received: 3".

      Then describe the full event from start to finish. Trace what happens
      across the frames: what enters, what exits, what changes. Where does the
      action begin and end? What path does the {label} take, or does that label
      even exist? Describe doors opening/closing, objects picked up or set
      down, and any other visible changes between frames.

      The first-pass detector flagged a {label}. This is the primary subject —
      describe it in detail, but also note other people, animals, or objects
      visible in the scene. The {label} may have been a false detection. If
      absent, say so and describe what IS visible. If the box is clearly around
      something else, then say so.

      Describe the progression chronologically from first frame to last. You
      may infer clear intent (e.g., a person entering a car, a cat sheltering
      from rain) but do not fabricate events you cannot see.

      Do not describe the camera characteristics (like height), but you may
      describe angle or zoom for a "PTZ" camera.
    '';
    suffix = ''
      Be concise but complete. Describe the full event. Do not editorialize. Only what is visible.
      Remember: Our first pass model may be inaccurate. Do not make assumptions about if a {label} is actually present.
    '';
    camera = {
      cam01 = "This camera sits ~12 ft up, overlooking our front walkway, front gate, sidewalk, and street intersection. The fenced area is our yard — anything inside or approaching it is priority. The camera may pan/tilt to a different scene; note if the view is not the default front-gate angle. This is a PTZ camera, so it may move its angle too.";
      cam02 = "Side yard: side door on the right, road on the left, back gate near middle-top. The fence separates our yard (to the right). Hanging plants may partially block the view. Look for cats and dogs near ground level and cats in the street.";
      cam03 = "Garage: two doors, two cars usually (blue classic on left, black Porsche on right). Workbench below camera, shelving and tools throughout. Doors behind both cars. The camera may pan/tilt. This is a PTZ camera, so it may move its angle too.";
      cam04 = "Backyard: trash storage on the left, neighbor's yard beyond the black fence on far left. Camera covers back garage door, left garage door, shed, back door, French doors, back gates, and back patio. An infrared light behind casts ground shadows — do not mistake them for objects. Focus on anything entering the house or shed, especially if doors are closed.";
      cam05 = "Front door and porch. Back driveway visible at the image rear. Camera is static, ~8 ft up. Shows inside the fence and a bit over the wall to the street above.";
      cam06 = "Driveway and front of house. Shows cars entering/leaving the driveway, people using the driveway fence gate, the road beyond the fence, and the other side's gate across the yard. Priority: anything inside our yard or about to enter the gate. Note if any gate opens or closes.";
      cam08 = "Server room interior. Visitors are rare. Describe any person's actions in detail.";
    };
    label = {
      person = "Describe: what the person is doing across the sequence (walking, carrying, entering, exiting, stopping, bending), direction and pace of movement. Then: clothing (colors, style, layers), build, items carried (packages, tools, bags), and whether approaching/leaving/loitering. Give a detailed physical description — as if for a police report — but do not assume race or gender.";
      dog = "If you see a dog, first try to identify 'Luna': a medium-sized black Labrador retriever, usually inside the fence or with a person. Describe: size, color, breed if identifiable, behavior, and whether accompanied. Do NOT assume the dog is Luna if it is not clearly her. You must be sure it is a black labrador retreiver.";
      cat = "If you see a cat, first try to identify 'Trixie' (black-and-white) or 'Mica' (gray). If unsure, say 'Other.' Don't actually say it is a specific cat unless you are unambigiously sure. Note if the cat is running from or at something. Describe: size, color, behavior.";
      package = "Describe: size, color, carrier logo if visible, where placed, who interacted with it. Watch for porch piracy: if someone takes a package and clearly leaves, describe that person in detail.";
      face = "Describe: visible facial features, approximate age, expression, direction they face.";
      fox = "If a fox: note whether our pets (cats/dogs) are also visible. Describe: size, color, behavior, whether peering at the house, and any sign of limping.";
    };
  };
  # ── GenAI sidecar package ─────────────────────────────────────────
  # Runs alongside Frigate, listens to MQTT for completed events,
  # extracts multi-frame clips + snapshot, calls Gemini, updates description.
  frigateGenaiSidecarPkg = let
    pythonEnv = pkgs.python3.withPackages (ps: [
      ps.paho-mqtt
      ps.openai
      ps.temporalio
    ]);
  in pkgs.runCommand "frigate-genai-sidecar" {
    buildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p $out/bin
    cp ${./frigate-genai-sidecar.py} $out/bin/frigate-genai-sidecar.py
    chmod +x $out/bin/frigate-genai-sidecar.py
    makeWrapper "${pythonEnv}/bin/python" "$out/bin/frigate-genai-sidecar" \
      --add-flags "$out/bin/frigate-genai-sidecar.py" \
      --prefix PATH : "${pkgs.ffmpeg}/bin"
  '';

  # Prompt templates — derived from genaiPrompts above
  frigateGenaiPromptsFile = pkgs.writeText "frigate-genai-prompts.json"
    (builtins.toJSON (genaiPrompts // { describe = objectLabels.describe; }));

  # Provider configuration — routed through LiteLLM proxy
  frigateGenaiProviderFile = pkgs.writeText "frigate-genai-provider.json" (builtins.toJSON {
    provider = "litellm";
    model = [

      "gemini/gemini-2.5-flash"
      "ollama/qwen3-vl-64k"
    ];
    api_key_env = "LITELLM_FRIGATE_KEY";
    base_url = "https://llm.2143.me/v1";
  });

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
          inertia = 1;
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
      audioEnabled = true;
      motionMask = [
        "0.401,0.023,0.323,0.27,0.28,0.419,0.295,0.464,0.308,0.475,0.315,0.516,0.312,0.56,0.301,0.567,0.277,0.57,0.252,0.576,0.233,0.59,0.205,0.636,0.163,0.704,0.118,0.842,0.1,0.993,0.595,0.999,0.597,0.89,0.59,0.856,0.575,0.836,0.559,0.817,0.548,0.785,0.541,0.757,0.538,0.732,0.534,0.705,0.526,0.688,0.515,0.682,0.502,0.67,0.496,0.661,0.491,0.652,0.486,0.641,0.482,0.627,0.478,0.608,0.475,0.583,0.472,0.563,0.471,0.544,0.458,0.523,0.454,0.503,0.453,0.481,0.45,0.456,0.45,0.403,0.45,0.369,0.452,0.342,0.455,0.32,0.46,0.295,0.462,0.271,0.462,0.256,0.461,0.239,0.448,0.217,0.425,0.189,0.419,0.073"
        "0.546,0.643,0.615,0.836,0.67,0.873,0.732,0.869,0.77,0.782,0.783,0.712,0.761,0.664,0.752,0.589,0.755,0.542,0.765,0.487,0.772,0.435,0.772,0.382,0.762,0.354,0.739,0.288,0.731,0.256,0.656,0.404,0.613,0.483,0.602,0.526,0.564,0.601"
        "0.237,0.4,0.175,0.349,0.149,0.351,0.128,0.398,0.099,0.46,0.087,0.501,0.078,0.525,0.044,0.586,0.021,0.622,0.003,0.676,0.001,0.993,0.047,0.999,0.081,0.936,0.12,0.829,0.145,0.76,0.175,0.654,0.217,0.55,0.245,0.406"
        "0.388,0.001,0.384,0.034,0.613,0.037,0.629,0.001"
      ];
      motionThreshold = 32;
      motionContourArea = 10;
      improveContrast = true;
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
    cam03 = {name = "Camera 3"; channel = "03"; stream = "sub"; motionMask = ["0.338,0.004,0.333,0.076,0.656,0.077,0.656,0.011" "0.606,0.366,0.573,0.49,0.45,0.461,0.432,0.521,0.628,0.701,0.706,0.701,0.739,0.583,0.78,0.541,0.696,0.365"]; motionThreshold = 54; motionContourArea = 10; improveContrast = true;};
    # Sideways (rotated 270°).  Main: 2160x7680 HEVC 25fps  Sub: 1536x432 H264 25fps
    cam04 = {
      name = "Camera 4";
      channel = "04"; stream = "sub"; codec = "h264";
      detectWidth = 1920; detectHeight = 1080;
      audioEnabled = true;
      motionMask = [
        "0.147,0.004,0.119,0.041,0.105,0.071,0.092,0.101,0.081,0.124,0.078,0.166,0.077,0.228,0.084,0.271,0.098,0.302,0.121,0.342,0.135,0.378,0.158,0.395,0.176,0.393,0.189,0.383,0.204,0.37,0.221,0.351,0.232,0.34,0.244,0.321,0.242,0.285,0.237,0.103,0.314,0.085,0.358,0.082,0.374,0.003"
        "0.112,0.322,0.001,0.411,0.001,0.175,0.063,0.158"
        "0.497,0.511,0.363,0.714,0.386,0.866,0.405,0.899,0.419,0.914,0.454,0.922,0.491,0.909,0.518,0.866,0.54,0.829,0.557,0.79,0.571,0.745,0.578,0.69,0.577,0.639,0.569,0.592,0.554,0.573,0.541,0.559"
        "0.759,0.633,0.726,0.588,0.701,0.611,0.691,0.66,0.676,0.73,0.673,0.782,0.678,0.835,0.678,0.896,0.714,0.893,0.748,0.813"
        "0.666,0.258,0.784,0.361,0.825,0.199,0.91,0.257,0.948,0.132,0.958,0.125,0.937,0.038,0.896,0.113,0.879,0.09,0.859,0.071,0.843,0.092,0.842,0.11,0.831,0.103,0.814,0.083,0.803,0.07,0.797,0.053,0.795,0.037,0.796,0,0.711,0,0.707,0.095,0.677,0.121"
        "0.381,0.023,0.381,0.089,0.621,0.087,0.621,0.028"
      ];
      objectMasks = {
        waste_bin = {
          mask = [ "0.302,0.54,0.254,0.417,0.225,0.452,0.223,0.538,0.23,0.605,0.238,0.655,0.245,0.711,0.252,0.763,0.257,0.795,0.276,0.828,0.297,0.896,0.326,0.918,0.347,0.9,0.358,0.863,0.354,0.773,0.354,0.638,0.347,0.561" ];
        };
      };
    };
    # Main: 2560x1920 H264 25fps  Sub: 640x480 H264 10fps
    cam05 = {
      name = "Camera 5";
      channel = "05"; stream = "sub"; codec = "h264";
      detectWidth = 2560; detectHeight = 1920;
      audioEnabled = true;
      motionMask = [
        "0.607,0.339,0.592,0.32,0.563,0.325,0.532,0.331,0.517,0.34,0.489,0.362,0.477,0.387,0.472,0.44,0.483,0.476,0.503,0.506,0.53,0.519,0.576,0.518,0.604,0.509,0.616,0.485,0.625,0.462,0.627,0.431,0.614,0.375"
        "0.729,0.146,0.756,0.206,0.78,0.22,0.83,0.265,0.864,0.302,0.904,0.348,0.976,0.394,1,0.421,1,0,0.744,0.05"
        "0.455,0.125,0.496,0.135,0.507,0.138,0.51,0.147,0.517,0.152,0.524,0.149,0.534,0.146,0.542,0.139,0.552,0.133,0.558,0.121,0.562,0.106,0.57,0.1,0.583,0.105,0.6,0.102,0.616,0.101,0.624,0.098,0.635,0.096,0.644,0.093,0.657,0.036,0.456,0.026"
        "0.66,0.322,0.61,0.331,0.595,0.324,0.587,0.294,0.592,0.268,0.608,0.191,0.63,0.167,0.655,0.162,0.703,0.173,0.733,0.211,0.736,0.29,0.738,0.315,0.755,0.318,0.776,0.326,0.794,0.341,0.806,0.374,0.814,0.41,0.833,0.464,0.823,0.522,0.809,0.548,0.791,0.547,0.765,0.523,0.73,0.505,0.725,0.476,0.713,0.425,0.706,0.394"
        "0.817,0.246,0.809,0.309,0.816,0.331,0.837,0.353,0.86,0.401,0.887,0.489,0.913,0.532,0.938,0.601,0.974,0.632,1,0.639,1,0.405"
        "0.333,0.008,0.336,0.067,0.645,0.062,0.653,0.012"
        "0.77,0.837,0.776,1,0.942,1,0.926,0.899"
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
      audioEnabled = true;
      motionMask = [
        "0.15,0.482,0.143,0.364,0.126,0.301,0.15,0.293,0.176,0.26,0.18,0.224,0.199,0.168,0.204,0.128,0.206,0.071,0.196,0.041,0.187,0.016,0.178,0.004,0,0.001,0.001,0.265,0.021,0.28,0.036,0.296,0.038,0.326,0.044,0.365,0.051,0.413,0.061,0.446,0.071,0.485,0.087,0.501,0.104,0.503,0.125,0.508"
        "0.246,0.022,0.245,0.104,0.258,0.168,0.278,0.214,0.301,0.228,0.324,0.197,0.344,0.174,0.364,0.163,0.383,0.163,0.393,0.183,0.407,0.192,0.43,0.192,0.449,0.187,0.47,0.179,0.487,0.169,0.507,0.165,0.52,0.159,0.532,0.168,0.544,0.182,0.554,0.194,0.571,0.206,0.587,0.224,0.596,0.229,0.609,0.227,0.621,0.215,0.722,0.245,0.74,0.14,0.756,0.096,0.726,0,0.666,0,0.625,0,0.248,0.001"
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
    cam08 = {name = "Camera 8"; rtspPath = "rtsp://\${EUFY_USER}:\${EUFY_PASS}@192.168.5.59/live0"; detectWidth = 1920; detectHeight = 1080; detectFps = 1; motionMask = ["0.56,0,0.466,0.023,0.467,0.172,0.602,0.235,0.625,0.129,0.619,0" "0.674,0.62,0.593,0.541,0.558,0.535,0.508,0.532,0.457,0.577,0.412,0.726,0.401,0.861,0.392,0.966,0.419,0.99,0.429,1,0.784,0.999" "0.712,0.005,0.715,0.066,0.995,0.07,0.997,0.002"]; motionThreshold = 49; motionContourArea = 10; improveContrast = true;};



  };

  # Build a per-camera Frigate config.
  # Uses ${NVR_USER}, ${NVR_PASS}, ${NVR_HOST} placeholders —
  # envsubst fills them at runtime from the agenix env file.
  mkCamera =
    key: cfg: {
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
      motion = ({
        threshold = cfg.motionThreshold or 30;
        contour_area = cfg.motionContourArea or 10;
        improve_contrast = cfg.improveContrast or true;
      } // lib.optionalAttrs (cfg ? motionMask) {
        mask = cfg.motionMask;
      });
      objects = {
        track = objectLabels.all;
        genai = {
          debug_save_thumbnails = true;
          enabled = false;  # Sidecar handles genai descriptions
          objects = objectLabels.describe;
          prompt = lib.concatStringsSep " " [
            genaiPrompts.base
            (genaiPrompts.camera.${key} or "")
            genaiPrompts.suffix
          ];
          object_prompts = lib.mapAttrs (labelName: hint:
            lib.concatStringsSep " " [
              genaiPrompts.base
              (genaiPrompts.camera.${key} or "")
              hint
              genaiPrompts.suffix
            ]
          ) genaiPrompts.label;
        };
      } // lib.optionalAttrs (cfg ? personMask || cfg ? objectMasks) {
        filters =
          (lib.optionalAttrs (cfg ? personMask) {
            person = { mask = cfg.personMask; };
          })
          // (cfg.objectMasks or {});
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
      user = mqttUser;
      password = mqttPass;
    };
    logger = {
      default = "info";
      logs = {
        "frigate.genai" = "debug";
      };
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
      # 2026-06-29 new models: 320px cd78e..., 640px 3e3c...
      path = "plus://cd78e0b872a64b00af63bed9f4972ed9";
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

    # genai = {
    #   provider = "openai";
    #   base_url = "https://llm.2143.me/v1";
    #   model = "ollama/qwen3-vl-128k";
    #   api_key = "\${LITELLM_FRIGATE_KEY}";
    # };
    # classification = {
    #   bird = { enabled = true; };
    #   custom = {
    #     cam05_front_door = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam05 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam03_garage_door_left = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam03 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam03_garage_door_right = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam03 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam06_front_gate = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam06 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam06_fence_gate = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam06 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam04_back_garage_door = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam04 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam04_back_gate = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam04 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam04_back_door = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam04 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam04_french_doors = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam04 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam02_side_door = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam02 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     cam01_front_gate = {
    #       threshold = 0.8;
    #       state_config = { motion = true; interval = 10; cameras = { cam01 = { crop = [0 0 100 100]; }; }; };
    #     };
    #     our_pets = {
    #       threshold = 0.8;
    #       object_config = { objects = [ "dog" "cat" ]; classification_type = "attribute"; };
    #     };
    #   };
    # };
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
# Patch object descriptions to send full frame (downscaled) instead of 500px crop
sed -i 's/data\["thumbnail"\] = create_thumbnail(yuv_frame, data\["box"\])/frame = cv2.cvtColor(yuv_frame, cv2.COLOR_YUV2BGR_I420); h, w = frame.shape[:2]; scale = min(1280 \/ max(h, w), 1.0); frame = cv2.resize(frame, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA); _, jpg = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85]); data["thumbnail"] = jpg.tobytes()/' /opt/frigate/frigate/data_processing/post/object_descriptions.py
# Inject reprocess button into Frigate UI
cat > /opt/frigate/web/reprocess-button.js << 'JS_EOF'
(function() {
  var SIDECAR = "http://100.64.0.1:9090";
  
  function tryInject() {
    // Find the sparkle "Regenerate" button
    var btns = document.querySelectorAll('button[aria-label*="egenerate"]');
    if (!btns.length) return false;
    
    // Check if we already injected next to THIS sparkle button
    if (btns[0].parentElement.querySelector("#sidecar-reprocess")) return true;
    
    var sparkleBtn = btns[0];
    var parent = sparkleBtn.closest('.flex.items-center.gap-3');
    if (!parent) return false;

    var btn = document.createElement("button");
    btn.id = "sidecar-reprocess";
    btn.textContent = "Reprocess";
    btn.setAttribute("aria-label", "Reprocess with multi-frame analysis");
    btn.className = sparkleBtn.className;
    btn.onclick = async function() {
      // Find event ID by looking at sibling images in the same dialog
      var eventId = null;
      // Method 1: Find the visible dialog snapshot (has object-contain class, visible in viewport)
      var imgs = document.querySelectorAll('img.object-contain[src*="/api/events/"], img[src*="/api/events/"][alt]:not([alt=""]):not([alt="Allcameras"])');
      for (var i = 0; i < imgs.length; i++) {
        var rect = imgs[i].getBoundingClientRect();
        if (rect.width > 100 && rect.height > 100) {
          var m = imgs[i].src.match(/events\/([^/]+)/);
          if (m) { eventId = m[1]; break; }
        }
      }
      if (!eventId) return;
      // Method 2: URL-based fallback
      if (!eventId) { var m2 = location.pathname.match(/events\/([^/]+)/); if (m2) eventId = m2[1]; }
      if (!eventId) return;
      btn.textContent = "...";
      btn.disabled = true;
      try {
        var r = await fetch(SIDECAR + "/reprocess/" + eventId, { method: "POST" });
        if (r.ok) {
          btn.textContent = "Sent!";
          btn.style.color = "#4ade80";
        } else {
          btn.textContent = "Failed";
          btn.style.color = "#f87171";
        }
      } catch(e) { 
        btn.textContent = "Error"; 
        btn.style.color = "#f87171";
      }
      setTimeout(function() { 
        btn.textContent = "Reprocess"; 
        btn.disabled = false; 
        btn.style.color = "";
      }, 4000);
    };
    parent.appendChild(btn);
    return true;
  }

  // Keep trying every 1s — React re-renders destroy the button
  setInterval(tryInject, 1000);
  tryInject();
})();
JS_EOF
sed -i 's|</head>|<script src="/reprocess-button.js"></script></head>|' /opt/frigate/web/index.html

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
    "d /var/lib/frigate-genai-sidecar 0755 root root -"
    "L+ /var/lib/frigate-genai-sidecar/prompts.json - - - - ${frigateGenaiPromptsFile}"
    "L+ /var/lib/frigate-genai-sidecar/provider.json - - - - ${frigateGenaiProviderFile}"
    "d /var/lib/frigate-genai-sidecar/frames 0755 root root 1h -"
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
        # Share host network — needed for MQTT (k8s NodePort), RTSP, go2rtc
        "--network=host"
      ];

      # Use our bootstrap script as the container entrypoint
      entrypoint = "/frigate-entrypoint.sh";

    };
  };
  # ── GenAI sidecar service ────────────────────────────────────────
  # Listens to MQTT for completed Frigate events, extracts multi-frame
  # clips from recordings, calls Gemini for description, writes it back.
  systemd.services.frigate-genai-sidecar = {
    description = "Frigate GenAI Sidecar — multi-frame event descriptions";
    wantedBy = ["multi-user.target"];
    after = [ "podman-frigate.service" ];
    requires = [ "podman-frigate.service" "network.target" ];
    path = [ pkgs.ffmpeg ];
    environment = {
      FRIGATE_BASE_URL = "http://localhost:5000";
      MQTT_HOST = mqttHost;
      MQTT_PORT = toString mqttPort;
      MQTT_USER = mqttUser;
      MQTT_PASSWORD = mqttPass;
      HTTP_HOST = "0.0.0.0";
      TEMPORAL_ADDRESS = "192.168.5.10:32682";
      TEMPORAL_MAX_FFMPEG = "3";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${frigateGenaiSidecarPkg}/bin/frigate-genai-sidecar";
      Restart = "on-failure";
      RestartSec = 10;
      StateDirectory = "frigate-genai-sidecar";
      EnvironmentFile = config.age.secrets.frigate-plus.path;
      User = "root";
      Group = "root";
    };
  };
  # ── Sidecar config files ── appended to tmpfiles.rules below
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
