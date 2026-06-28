# Ollama module — local model serving, ROCm on office/arch.
#
# Users download models directly with `ollama pull <model>`.
# Models are stored on the root NVMe at /var/lib/ollama/models.
#
# === Usage ===
#
#   ollama list                       # show locally available models
#   ollama rm <model>                 # delete a model
#   ollama run <model>                # interactive chat
#   ollama run <model> "prompt"       # one-shot generation
#   ollama ps                         # show loaded models and VRAM usage
#
# === Browse models ===
#
#   https://ollama.com/library        # full catalogue
#   ollama show <model>               # inspect a model's details
{
  config,
  lib,
  pkgs,
  pkgs-stable,
  ...
}: {

  config = {
    services.ollama = {
      enable = true;
      host = "0.0.0.0";
      openFirewall = true;
    };

    # The stock ollama unit uses DynamicUser, which can't write to paths owned by
    # john (NAS datasets, local state inherited from earlier setups).  Force the
    # service to run as john instead.
    #
    # UMask=0022: the upstream unit sets 0077, which yields mode-0600 manifests
    # and blobs.  Those then break in two places: rsync -a preserves the mode,
    # and the workstation daemon's runner subprocess fails to open them
    # (EPERM) under the unit's ProtectSystem=strict + NoNewPrivileges sandbox,
    # even though john owns the files.  0022 produces 0644 files that traverse
    # cleanly NAS → workstation.
    systemd.services.ollama.serviceConfig = {
      User = lib.mkForce "john";
      Group = lib.mkForce "users";
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      StateDirectory = lib.mkForce "";
      UMask = lib.mkForce "0022";
    };

    # tmpfiles creates the local state directories.  StateDirectory is cleared
    # above because it fails when /var/lib/ollama is a symlink (NAS volume) —
    # the target volume already exists in that case.
    systemd.tmpfiles.rules = [
      "d /var/lib/ollama        0755 john users -"
      "d /var/lib/ollama/models 0755 john users -"
    ];

  };
}
