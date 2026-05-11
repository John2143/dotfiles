# Hetzner k3s Node — Declarative Disk Layout (disko)
#
# Used by nixos-anywhere to partition Hetzner Cloud VMs.
# Layout: EFI System Partition (512MB) + LUKS2-encrypted root (rest of disk).
# SeaweedFS and Longhorn use directories on the root filesystem.
# SeaweedFS encrypts at the application layer (encryptVolumeData).
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
              type = "luks";
              name = "cryptroot";
              settings = {
                allowDiscards = true;
              };
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
  };
}
