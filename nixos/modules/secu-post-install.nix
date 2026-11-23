# Post-install module for secu.
# Enable this AFTER enrolling the USB keyfile with:
#   sudo cryptsetup luksAddKey /dev/sda3 /dev/disk/by-partlabel/CRYPTKEY --new-keyfile-size 4096
{...}: {
  # USB keyfile unlock for LUKS, falling back to the passphrase when the stick is
  # absent: crypttab's keyfile-timeout is what makes that fallback happen, since
  # the scripted stage 1 (and with it fallbackToPassword) no longer exists.
  # Without a timeout cryptsetup has no point at which to give up on the device
  # and ask for a passphrase, so a stick left in a keyboard hub or a slow hub
  # enumeration becomes a boot that never gets to a prompt.
  boot.initrd.luks.devices."cryptroot" = {
    keyFile = "/dev/disk/by-partlabel/CRYPTKEY";
    keyFileSize = 4096;
    keyFileTimeout = 10;
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
