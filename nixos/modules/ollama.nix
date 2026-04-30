# Shared ollama module — imported by workstations (arch, office) and the NAS.
#
# === Architecture ===
#
#   The model list is declared in Nix (services.ollama.modelNames).  On the NAS,
#   a systemd oneshot pulls any missing models after each rebuild.  Workstations
#   rsync from the NAS for local NVMe serving.  Per-machine GPU packages and
#   overrides live in each host's own configuration.nix.
#
# === Model management ===
#
#   1. Add the model name to services.ollama.modelNames in nas-configuration.nix
#   2. Rebuild the NAS — the ollama-model-pull service pulls it automatically
#   3. Run `ollama-sync` on each workstation to rsync from the NAS
#
#   ollama list                       # show locally available models
#   ollama rm <model>                 # delete a local model
#
# === Running models ===
#
#   ollama run <model>                # interactive chat (e.g. ollama run gemma4)
#   ollama run <model> "prompt"       # one-shot generation
#   ollama ps                         # show loaded models and VRAM usage
#
# === Browse models ===
#
#   https://ollama.com/library        # full catalogue
#   ollama show <model>               # inspect a model's details
#
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  ...
}: let
  cfg = config.services.ollama;
in {
  options.services.ollama.modelNames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "List of ollama model names to pull automatically (e.g. [\"gemma4\" \"qwen3.6\"]).";
  };

  config = {
    services.ollama = {
      enable = true;
      host = "0.0.0.0";
      openFirewall = true;
    };

    # The stock ollama unit uses DynamicUser, which can't write to paths owned by
    # john (NAS datasets, local state inherited from earlier setups).  Force the
    # service to run as john instead.
    systemd.services.ollama.serviceConfig = {
      User = lib.mkForce "john";
      Group = lib.mkForce "users";
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
    };

    systemd.services.ollama-model-pull = lib.mkIf (cfg.modelNames != []) {
      description = "Pull declared ollama models";
      after = ["ollama.service"];
      requires = ["ollama.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "john";
        Group = "users";
      };
      script = ''
        ${lib.concatMapStringsSep "\n" (m: ''
            echo "Ensuring model: ${m}"
            ${cfg.package}/bin/ollama pull ${m}
          '')
          cfg.modelNames}
      '';
    };
  };
}
