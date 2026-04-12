# Post-install module for secu.
# Enable this AFTER enrolling TPM2 with:
#   sudo systemd-cryptenroll --tpm2-device=auto /dev/sda3
{ ... }:
{
  boot.initrd.systemd.enable = true;
  security.tpm2.enable = true;

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
