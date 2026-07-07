# ── Frigate GenAI configuration ─────────────────────────────────────
# Shared between frigate.nix (NixOS module) and flake.nix (CI builds).
# Import this directly in CI — no NixOS evaluation needed.
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  # ── Object labels ─────────────────────────────────────────────────
  objectLabels = rec {
    all = [
      "person" "car" "motorcycle" "bicycle" "school_bus" "boat"
      "bird" "cat" "dog" "deer" "horse" "bear" "cow" "fox" "raccoon"
      "face" "license_plate" "package" "amazon" "fedex" "ups" "usps"
      "dhl" "an_post" "purolator" "postnl" "nzpost" "postnord" "gls"
      "dpd" "royal_mail" "canada_post"
      "robot_lawnmower" "umbrella"
    ];
    unused = [ "truck" "other" "bus" ];
    excludeFromDescribe = [ "car" "waste_bin" "bbq_grill" ];
    describe = lib.subtractLists excludeFromDescribe all;
  };

  # ── GenAI prompt templates (composed per-camera + per-label) ─────
  genaiPrompts = {
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
    car = ''
      You are a vehicle identification tool. You will see one snapshot of a
      vehicle detected by a security camera. The bounding box labels it as a car.

      Identify the make, model, approximate year, and color of the vehicle.
      If the vehicle is not clearly visible or the image is too blurry, say so.

      Format: "Make Model (~year), color. [Additional visible details]"
      Be concise. One sentence. If multiple vehicles are visible, describe the
      one in the bounding box.
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

  # ── Python environment ──────────────────────────────────────────
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.paho-mqtt
    ps.openai
    ps.temporalio
    ps.pillow
    ps.boto3
  ]);

  # ── GenAI sidecar package ─────────────────────────────────────────
  frigateGenaiSidecarPkg = pkgs.runCommand "frigate-genai-sidecar" {
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

  # ── GenAI Docker images ──────────────────────────────────────────
  frigateGenaiGenaiImage = pkgs.dockerTools.buildLayeredImage {
    name = "frigate-genai-genai";
    tag = "v1";
    contents = [ pythonEnv pkgs.cacert ];
    extraCommands = ''
      mkdir -p var/lib/frigate-genai-sidecar
      cp ${frigateGenaiPromptsFile} var/lib/frigate-genai-sidecar/prompts.json
      cp ${frigateGenaiProviderFile} var/lib/frigate-genai-sidecar/provider.json
    '';
    config.Entrypoint = [ "${pythonEnv}/bin/python" "${./frigate-genai-sidecar.py}" ];
  };

  frigateGenaiFfmpegImage = pkgs.dockerTools.buildLayeredImage {
    name = "frigate-genai-ffmpeg";
    tag = "v1";
    contents = [ pythonEnv pkgs.cacert pkgs.ffmpeg ];
    extraCommands = ''
      mkdir -p var/lib/frigate-genai-sidecar
      cp ${frigateGenaiPromptsFile} var/lib/frigate-genai-sidecar/prompts.json
      cp ${frigateGenaiProviderFile} var/lib/frigate-genai-sidecar/provider.json
    '';
    config.Entrypoint = [ "${pythonEnv}/bin/python" "${./frigate-genai-sidecar.py}" ];
  };
in {
  inherit
    objectLabels
    genaiPrompts
    pythonEnv
    frigateGenaiSidecarPkg
    frigateGenaiPromptsFile
    frigateGenaiProviderFile
    frigateGenaiGenaiImage
    frigateGenaiFfmpegImage
  ;
}
