{ lib }:
let
  models = [
    # ── Claude ──
    { modelName = "claude-fable-5";  ompName = "Claude Fable 5";
      inputTypes = ["text"];  contextWindow = 1000000; maxTokens = 128000;
      supportsToolChoice = true;  tiers = ["official" "fast"];
      pricing = { fast = { input = 1.65; output = 8.25; cacheRead = 0.165; cacheWrite = 2.0625; inputPerToken = "0.00000165"; outputPerToken = "0.00000825"; cacheReadPerToken = "0.000000165"; cacheWritePerToken = "0.0000020625"; }; };
      legacyNames = { official = "fabog"; fast = "fabfast"; };
    }
    { modelName = "claude-opus-4-6";  ompName = "Claude Opus 4.6";
      inputTypes = ["text"];  contextWindow = 1000000; maxTokens = 128000;
      supportsToolChoice = true;  tiers = ["official" "fast"];
    }
    { modelName = "claude-opus-4-8";  ompName = "Claude Opus 4.8";
      inputTypes = ["text"];  contextWindow = 1000000; maxTokens = 128000;
      supportsToolChoice = true;  tiers = ["official" "fast"];
      pricing = { fast = { input = 0.34375; output = 1.71875; cacheRead = 0.034375; cacheWrite = 0.429688; inputPerToken = "0.00000034375"; outputPerToken = "0.00000171875"; cacheReadPerToken = "0.000000034375"; cacheWritePerToken = "0.000000429688"; }; };
    }
    # ── GPT 5.6 ──
    { modelName = "gpt-5.6-terra";  ompName = "GPT 5.6 Terra";
      inputTypes = ["text"];  contextWindow = 1050000; maxTokens = 128000;
      supportsToolChoice = true;  tiers = ["official" "fast"];
    }
    { modelName = "gpt-5.6-luna";  ompName = "GPT 5.6 Luna";
      inputTypes = ["text"];  contextWindow = 1050000; maxTokens = 128000;
      supportsToolChoice = true;  tiers = ["official" "fast"];
    }
    { modelName = "gpt-5.6-sol";  ompName = "GPT 5.6 Sol";
      inputTypes = ["text"];  contextWindow = 1050000; maxTokens = 128000;
      supportsToolChoice = true;  tiers = ["official" "fast"];
    }
    # ── Gemini Pro/Flash (multimodal) ──
    { modelName = "gemini-3.1-pro";  yunwuModel = "gemini-3.1-pro-preview";
      ompName = "Gemini 3.1 Pro";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-3.1-flash";  yunwuModel = "gemini-3.1-flash-preview";
      ompName = "Gemini 3.1 Flash";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-3-pro";  yunwuModel = "gemini-3-pro-preview";
      ompName = "Gemini 3 Pro";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-3-flash";  yunwuModel = "gemini-3-flash-preview";
      ompName = "Gemini 3 Flash";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-3.5-flash";  yunwuModel = "gemini-3.5-flash";
      ompName = "Gemini 3.5 Flash";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-2.5-pro";  yunwuModel = "gemini-2.5-pro";
      ompName = "Gemini 2.5 Pro";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-2.5-flash";  yunwuModel = "gemini-2.5-flash";
      ompName = "Gemini 2.5 Flash";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-pro-latest";  yunwuModel = "gemini-pro-latest";
      ompName = "Gemini Pro Latest";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-flash-latest";  yunwuModel = "gemini-flash-latest";
      ompName = "Gemini Flash Latest";  inputTypes = ["text" "image"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    # ── Gemini Flash Lite (text-only) ──
    { modelName = "gemini-3.1-flash-lite";  yunwuModel = "gemini-3.1-flash-lite-preview";
      ompName = "Gemini 3.1 Flash Lite";  inputTypes = ["text"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-2.5-flash-lite";  yunwuModel = "gemini-2.5-flash-lite";
      ompName = "Gemini 2.5 Flash Lite";  inputTypes = ["text"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-2.0-flash-lite";  yunwuModel = "gemini-2.0-flash-lite";
      ompName = "Gemini 2.0 Flash Lite";  inputTypes = ["text"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
    { modelName = "gemini-flash-lite-latest";  yunwuModel = "gemini-flash-lite-latest";
      ompName = "Gemini Flash Lite Latest";  inputTypes = ["text"];
      contextWindow = 1048576; maxTokens = 65536;  tiers = ["official" "fast"];
    }
  ];

  # ── Helpers ──

  capTier = tier: {
    official = "Official";
    fast = "Fast";
  }.${tier};

  upperTier = tier: {
    official = "OFFICIAL";
    fast = "FAST";
  }.${tier};

  inputTypesYaml = types:
    let items = builtins.concatStringsSep ", " types;
    in "[${items}]";

  costYaml = cost:
    let f = x: toString (if builtins.isFloat x then x else x);
    in "{ input: ${f (cost.input or 0)}, output: ${f (cost.output or 0)}, cacheRead: ${f (cost.cacheRead or 0)}, cacheWrite: ${f (cost.cacheWrite or 0)} }";

  compatBlock = supports:
    if supports then "\n\n              compat:\n                supportsToolChoice: true" else "";

  # ── OMP model entry generator ──

  mkOmpEntry = m: tier:
    let
      id = m.legacyNames.${tier} or "${m.modelName}-${tier}";
      name = "${m.ompName} (Yunwu ${capTier tier})";
      cost = m.pricing.${tier} or { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; };
      supportsToolChoice = m.supportsToolChoice or false;
    in ''
              # Yunwu ${m.ompName} — ${tier} tier
              - id: ${id}
                name: ${name}
                reasoning: true
                input: ${inputTypesYaml (m.inputTypes or ["text"])}
                cost: ${costYaml cost}
                contextWindow: ${toString m.contextWindow}
                maxTokens: ${toString m.maxTokens}${compatBlock supportsToolChoice}
    '';

  mkOmpEntries = m:
    lib.concatMapStrings (tier:
      let entry = mkOmpEntry m tier;
          hasLegacy = m ? legacyNames && m.legacyNames ? ${tier};
      in entry + (if hasLegacy then mkOmpEntry (m // { legacyNames = {}; }) tier else "")
    ) m.tiers;

  # ── LiteLLM configmap entry generators ──

  mkLitellmEntry = m: tier: name:
    let
      yunwuModel = m.yunwuModel or m.modelName;
    in ''
          - model_name: "${name}"
            litellm_params:
              model: "openai/${yunwuModel}"
              api_key: "os.environ/YUNWU_${upperTier tier}_API_KEY"
              api_base: "https://yunwu.ai/v1"
    '';

  mkLitellmPricedEntry = m: tier:
    let
      yunwuModel = m.yunwuModel or m.modelName;
      price = m.pricing.${tier};
    in ''
          - model_name: "yunwu/${tier}/${m.modelName}"
            litellm_params:
              model: "openai/${yunwuModel}"
              api_key: "os.environ/YUNWU_${upperTier tier}_API_KEY"
              api_base: "https://yunwu.ai/v1"
            model_info:
              max_tokens: ${toString m.maxTokens}
              input_cost_per_token: ${price.inputPerToken}
              output_cost_per_token: ${price.outputPerToken}
              cache_read_input_token_cost: ${price.cacheReadPerToken}
              cache_creation_input_token_cost: ${price.cacheWritePerToken}
    '';

  mkLitellmEntries = m:
    lib.concatMapStrings (tier:
      let
        standard = mkLitellmEntry m tier "${m.modelName}-${tier}";
        legacy = if m ? legacyNames && m.legacyNames ? ${tier}
          then mkLitellmEntry m tier m.legacyNames.${tier}
          else "";
        priced = if m ? pricing && m.pricing ? ${tier}
          then mkLitellmPricedEntry m tier
          else "";
        comment = ''
          # ── ${m.ompName} — ${tier} tier ──
    '';
      in comment + standard + legacy + priced
    ) m.tiers;

in
{
  inherit models;
  toOmpYaml = ms: lib.concatMapStrings mkOmpEntries ms;
  toLitellmYaml = ms: lib.concatMapStrings mkLitellmEntries ms;
}
