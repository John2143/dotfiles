# Shared ollama module — imported by workstations (arch, office) and the NAS.
#
# === Architecture ===
#
#   Models are pulled on the NAS (local ZFS, no CIFS) and synced to workstations
#   over LAN for local NVMe serving.  Per-machine GPU packages and overrides
#   live in each host's own configuration.nix.
#
# === Model management ===
#
#   ssh nas ollama pull <model>       # download a model to the NAS
#   ollama-sync                       # rsync models from NAS to this machine
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
}:

{
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
}
