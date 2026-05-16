# Hetzner k3s Node — Declarative Disk Layout (disko)
#
# Used by nixos-anywhere to partition Hetzner Cloud VMs.
# Layout: EFI System Partition (512MB) + ext4 root (rest of disk).
# LUKS encryption removed — requires interactive password entry at boot
# which isn't viable for cloud VMs. Encryption is handled at the
# application layer (SeaweedFS encryptVolumeData, etc).
#
# Reference: nixos.wiki/wiki/Install_NixOS_on_Hetzner_Cloud
{
  ...
}: {
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };

  # Boot loader — UEFI only (Hetzner Cloud uses EFI)
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
