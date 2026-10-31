# CIFS mounts for the NAS, reached over Tailscale MagicDNS.
# Shares are lazy via x-systemd.automount so a missing NAS never blocks boot.
# Assumes agenix is loaded and secrets/smb-credentials.age is decryptable by this host.
#
# Ordering matters: `_netdev` puts these units after network-online.target, which
# during `nixos-rebuild switch` is reached while NetworkManager and tailscaled are
# being restarted — MagicDNS is not resolvable yet, the CIFS mount fails on
# "could not resolve address for nas.ts.2143.me", and switch-to-configuration
# counts that as a hard failure (exit 4). Ordering on tailscaled.service instead,
# plus `nofail`, makes a transient failure a warning rather than a failed switch.
{
  config,
  pkgs,
  lib,
  ...
}: let
  # Only hosts that actually run Tailscale can order on it.
  tailscaledOrder = lib.optionals config.services.tailscale.enable [
    "x-systemd.requires=tailscaled.service"
    "x-systemd.after=tailscaled.service"
  ];
  mountOpts = [
    "x-systemd.automount"
    "noauto"
    "x-systemd.idle-timeout=60"
    "x-systemd.device-timeout=10s"
    "x-systemd.mount-timeout=10s"
    # No `_netdev`: it orders the mount after network-online.target, which is
    # reached mid-activation while NetworkManager is restarting. The tailscaled
    # ordering below is the dependency that actually matters here.
    "credentials=${config.age.secrets.smb-credentials.path}"
    "uid=1000"
    "gid=1000"
    "forceuid"
    "forcegid"
    "file_mode=0644"
    "dir_mode=0755"
    "nofail"
  ] ++ tailscaledOrder;
in {
  environment.systemPackages = [pkgs.cifs-utils];

  age.secrets.smb-credentials = {
    file = ../../secrets/smb-credentials.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  age.secrets.gocryptfs-passphrase =
    lib.mkIf
    (builtins.elem config.networking.hostName ["arch" "office" "closet"])
    {
      file = ../../secrets/gocryptfs-passphrase.age;
      mode = "0400";
      owner = "john";
      group = "root";
    };

  fileSystems."/mnt/nas/share" = {
    device = "//nas.ts.2143.me/share";
    fsType = "cifs";
    options = mountOpts;
  };

  fileSystems."/mnt/nas/scratch" = {
    device = "//nas.ts.2143.me/scratch";
    fsType = "cifs";
    options = mountOpts;
  };

  fileSystems."/mnt/nas/media" = {
    device = "//nas.ts.2143.me/media";
    fsType = "cifs";
    options = mountOpts;
  };

  fileSystems."/mnt/nas/private" = {
    device = "//nas.ts.2143.me/private";
    fsType = "cifs";
    options = mountOpts;
  };
}
