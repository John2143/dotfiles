# CIFS mounts for the NAS, reached over Tailscale MagicDNS.
# Shares are lazy via x-systemd.automount so a missing NAS never blocks boot.
# Assumes agenix is loaded and secrets/smb-credentials.age is decryptable by this host.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  mountOpts = [
    "x-systemd.automount"
    "noauto"
    "x-systemd.idle-timeout=60"
    "x-systemd.device-timeout=10s"
    "x-systemd.mount-timeout=10s"
    "_netdev"
    "credentials=${config.age.secrets.smb-credentials.path}"
    "uid=1000"
    "gid=1000"
    "forceuid"
    "forcegid"
    "file_mode=0644"
    "dir_mode=0755"
  ];
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];

  age.secrets.smb-credentials = {
    file = ../../secrets/smb-credentials.age;
    mode = "0400";
    owner = "root";
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
}
