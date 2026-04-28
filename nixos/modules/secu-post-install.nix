# Post-install module for secu.
# Enable this AFTER enrolling the USB keyfile with:
#   sudo cryptsetup luksAddKey /dev/sda3 /dev/disk/by-partlabel/CRYPTKEY --new-keyfile-size 4096
{...}: {
  # USB keyfile unlock for LUKS (falls back to passphrase if USB is absent)
  boot.initrd.luks.devices."cryptroot" = {
    keyFile = "/dev/disk/by-partlabel/CRYPTKEY";
    keyFileSize = 4096;
  };

  services.btrbk.instances."home" = {
    onCalendar = "hourly";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "14d";
      volume."/home/john" = {
        snapshot_dir = "/home/john/.snapshots";
        subvolume = ".";
      };
    };
  };
}
