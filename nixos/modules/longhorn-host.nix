{
  config,
  pkgs,
  ...
}: {
  # === Longhorn host prerequisites ===
  #
  # Longhorn's manager pod nsenter()s into the host PID namespace and shells
  # out to fixed-path binaries (iscsiadm, mount, nsenter, findmnt, mkfs.ext4,
  # lsblk). On NixOS those binaries live under /run/current-system/sw/bin,
  # not /usr/bin or /usr/local/sbin where Longhorn looks. Three pieces:
  #   1. enable iscsid (Longhorn uses iSCSI as its block transport),
  #   2. install the host-side packages so they exist in the system PATH,
  #   3. symlink the specific paths Longhorn hardcodes.
  # Reference pattern: github.com/duckfullstop/nixos-longhorn.
  #
  # This module is imported both from k3s-agent.nix (for office/arch/pite)
  # and directly from flake.nix for closet, which runs k3s but doesn't pull
  # in k3s-agent.nix. NixOS module imports are deduplicated, so importing
  # this twice on the same host is safe.
  services.openiscsi = {
    enable = true;
    name = "iqn.2026-05.me.2143:${config.networking.hostName}";
  };
  # Reduce kernel SCSI replacement_timeout from 120s to 15s — Longhorn handles
  # replication at the app level, so slow SCSI error recovery just adds
  # needless delays on reboot (5 minutes compounding across ~30 LUNs).
  boot.iscsi-initiator.extraConfig = ''
    node.session.timeo.replacement_timeout = 15
  '';
  # Give iscsid enough time for clean iSCSI logout before SIGKILL
  systemd.services.iscsid.serviceConfig.TimeoutStopSec = "60s";

  environment.systemPackages = with pkgs; [
    openiscsi
    nfs-utils
    util-linux
    e2fsprogs
    xfsprogs
    cryptsetup
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/longhorn 0755 root root - -"
    "d /mnt/longhorn 0755 root root - -"
    "d /var/lib/longhorn-2 0755 root root - -"
    "L+ /usr/local/sbin/iscsiadm  - - - - ${pkgs.openiscsi}/bin/iscsiadm"
    "L+ /usr/local/bin/mount      - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /usr/local/bin/umount     - - - - ${pkgs.util-linux}/bin/umount"
    "L+ /usr/local/bin/findmnt    - - - - ${pkgs.util-linux}/bin/findmnt"
    "L+ /usr/local/bin/nsenter    - - - - ${pkgs.util-linux}/bin/nsenter"
    "L+ /usr/local/bin/lsblk      - - - - ${pkgs.util-linux}/bin/lsblk"
    "L+ /usr/local/sbin/mkfs.ext4 - - - - ${pkgs.e2fsprogs}/bin/mkfs.ext4"
  ];
  # Cleanly logout all iSCSI sessions before shutdown — prevents kernel SCSI
  # from timing out each orphaned LUN sequentially (which causes ~5min delay).
  systemd.services.iscsi-logout-shutdown = {
    description = "Logout all iSCSI sessions before shutdown";
    wantedBy = ["shutdown.target"];
    before = ["shutdown.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = "${pkgs.openiscsi}/bin/iscsiadm -m node --logoutall=all";
    };
  };
}
