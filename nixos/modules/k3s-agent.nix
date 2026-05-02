{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.k3sNodeTaints = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Node taints to apply when the k3s agent first registers.";
    example = ["seated=true:NoSchedule"];
  };

  config = {
    age.secrets.k3s-local-token = {
      file = ../../secrets/k3s-local-token.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    services.k3s = {
      enable = true;
      role = "agent";
      serverAddr = "https://192.168.5.35:6443";
      tokenFile = config.age.secrets.k3s-local-token.path;
    };

    # === Longhorn host prerequisites ===
    #
    # Longhorn is a CSI driver whose manager pod nsenter()s into the host
    # PID namespace and shells out to fixed-path binaries (iscsiadm, mount,
    # nsenter, findmnt, mkfs.ext4, lsblk). On NixOS those binaries live
    # under /run/current-system/sw/bin, not /usr/bin or /usr/local/sbin
    # where Longhorn looks. Three pieces:
    #   1. enable iscsid (Longhorn uses iSCSI as its block transport),
    #   2. install the host-side packages so they exist in the system PATH,
    #   3. symlink the specific paths Longhorn hardcodes.
    # Reference pattern: github.com/duckfullstop/nixos-longhorn.
    services.openiscsi = {
      enable = true;
      name = "iqn.2026-05.me.2143:${config.networking.hostName}";
    };

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
      "L+ /usr/local/sbin/iscsiadm  - - - - ${pkgs.openiscsi}/bin/iscsiadm"
      "L+ /usr/local/bin/mount      - - - - ${pkgs.util-linux}/bin/mount"
      "L+ /usr/local/bin/umount     - - - - ${pkgs.util-linux}/bin/umount"
      "L+ /usr/local/bin/findmnt    - - - - ${pkgs.util-linux}/bin/findmnt"
      "L+ /usr/local/bin/nsenter    - - - - ${pkgs.util-linux}/bin/nsenter"
      "L+ /usr/local/bin/lsblk      - - - - ${pkgs.util-linux}/bin/lsblk"
      "L+ /usr/local/sbin/mkfs.ext4 - - - - ${pkgs.e2fsprogs}/bin/mkfs.ext4"
    ];
  };
}
