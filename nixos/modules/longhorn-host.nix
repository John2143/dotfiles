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
    # Reduce kernel SCSI replacement_timeout from 120s to 15s — Longhorn handles
    # replication at the app level, so slow SCSI error recovery just adds
    # needless delays on reboot (5 minutes compounding across ~30 LUNs).
    # This used to be boot.iscsi-initiator.extraConfig, which nixpkgs removed.
    extraConfig = ''
      node.session.timeo.replacement_timeout = 15
    '';
  };
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
  # Sockets left in /var/lib/longhorn/unix-domain-socket by processes that did not
  # survive the shutdown make the first replica start on each volume fail with
  # EADDRINUSE and retry ~5.8 s later (16 of ~26 first starts, 2026-11-26). Only
  # sockets are removed, and only while k3s is down: nixos-rebuild switch starts
  # a newly added unit immediately, and deleting sockets under a running
  # instance-manager would break the engine<->replica IPC it is serving.
  systemd.services.longhorn-clear-stale-sockets = {
    description = "Remove stale Longhorn engine sockets before k3s starts";
    wantedBy = ["multi-user.target"];
    before = ["k3s.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ${config.systemd.package}/bin/systemctl is-active --quiet k3s.service; then
        echo "k3s is running; leaving Longhorn sockets alone"
        exit 0
      fi
      ${pkgs.findutils}/bin/find /var/lib/longhorn/unix-domain-socket \
        -maxdepth 1 -type s -name '*.sock' -delete 2>/dev/null || true
    '';
  };
}
