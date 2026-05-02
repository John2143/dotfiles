{
  config,
  pkgs,
  ...
}: {
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
    "d /mnt/longhorn 0755 root root - -"
    "L+ /usr/local/sbin/iscsiadm  - - - - ${pkgs.openiscsi}/bin/iscsiadm"
    "L+ /usr/local/bin/mount      - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /usr/local/bin/umount     - - - - ${pkgs.util-linux}/bin/umount"
    "L+ /usr/local/bin/findmnt    - - - - ${pkgs.util-linux}/bin/findmnt"
    "L+ /usr/local/bin/nsenter    - - - - ${pkgs.util-linux}/bin/nsenter"
    "L+ /usr/local/bin/lsblk      - - - - ${pkgs.util-linux}/bin/lsblk"
    "L+ /usr/local/sbin/mkfs.ext4 - - - - ${pkgs.e2fsprogs}/bin/mkfs.ext4"
  ];
}
