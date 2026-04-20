# Restic backup module — pushes encrypted, deduplicated backups to the NAS
# over SFTP (Tailscale) as the restricted `backup` user. Each host gets its
# own repo under /tank/backups/<hostname>. The backup user is chrooted to
# /tank/backups with ForceCommand internal-sftp — no shell access.
#
# === ONE-TIME SETUP (after first deploy) ===
#
# 1. Generate the NAS age key (on the NAS, if not already done):
#      ssh-keygen -t ed25519 -f ~/.ssh/age -N ""
#    Then paste the public key into secrets/secrets.nix and re-key.
#
# 2. Create the restic-password secret (from the secrets/ directory):
#      nix run github:ryantm/agenix -- -e restic-password.age -i ~/.ssh/age
#    Enter a strong random passphrase (e.g. `openssl rand -base64 32`).
#
# 3. Re-encrypt after adding new machine keys to secrets.nix:
#      nix run github:ryantm/agenix -- -r -i ~/.ssh/age
#
# 4. Set up backup directories on the NAS. ChrootDirectory requires
#    /tank/backups to be root-owned; per-host subdirs are owned by backup:
#      sudo chown root:root /tank/backups && sudo chmod 755 /tank/backups
#      for h in arch office closet secu; do
#        sudo zfs create tank/backups/$h          # or: sudo mkdir /tank/backups/$h
#        sudo chown backup:backup /tank/backups/$h
#      done
#
# 5. Deploy each machine:
#      sudo nixos-rebuild switch --flake ~/dotfiles#<hostname>
#
# The restic NixOS module initializes the repository automatically on the
# first backup run.
#

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.backup;
  hostname = config.networking.hostName;
in
{
  options.custom.backup = {
    enable = lib.mkEnableOption "restic backup to NAS";

    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths to back up beyond /home/john.";
    };

    extraExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional exclude patterns.";
    };

    prepareCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Command to run before backup (e.g. pg_dumpall).";
    };

    timerOnCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:00:00";
      description = "systemd OnCalendar expression for the backup timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.identityPaths = [ "/home/john/.ssh/age" ];

    age.secrets.restic-password = {
      file = ../../secrets/restic-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    services.restic.backups.nas = {
      repository = "sftp:backup@nas.ts.2143.me:/${hostname}";
      passwordFile = config.age.secrets.restic-password.path;

      paths = [ "/home/john" ] ++ cfg.extraPaths;

      exclude = [
        "/home/john/.cache"
        "/home/john/.local/share/Steam"
        "/home/john/.local/share/Trash"
        "/home/john/.local/share/containers"
        "/home/john/.mozilla/firefox/*/cache2"
        "/home/john/.config/Cursor*"
        "/home/john/.config/chromium"
        "/home/john/.config/google-chrome"
        "/home/john/.npm"
        "/home/john/.cargo/registry"
        "/home/john/.rustup/toolchains"
        "/home/john/go/pkg"
        "**/.direnv"
        "**/node_modules"
        "**/target/debug"
        "**/target/release"
        "**/.git/objects"
        "**/result"
        "**/*.qcow2"
        "**/*.img"
        "**/*.iso"
      ] ++ cfg.extraExcludes;

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
        "--keep-yearly 1"
      ];

      timerConfig = {
        OnCalendar = cfg.timerOnCalendar;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };

      initialize = true;

      backupPrepareCommand = cfg.prepareCommand;

      extraOptions = [
        "sftp.command='ssh backup@nas.ts.2143.me -o StrictHostKeyChecking=accept-new -s sftp'"
      ];
    };
  };
}
