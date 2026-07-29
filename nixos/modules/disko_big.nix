# Disko configuration for the big machine (Proxmox VM, SeaBIOS / GRUB).
#
# Boot disk (/dev/sda, GPT):
#   sda1: BIOS boot   (1M,   EF02,  no fs — GRUB core image)
#   sda2: root        (rest, ext4,  label=NIXROOT, mount=/)
#
# Data disk (/dev/sdb, passthrough virtio SCSI):
#   sdb1: longhorn    (rest, ext4,  mount=/var/lib/longhorn)
#
# Install:
#   sudo nix --experimental-features "nix-command flakes" \
#     run github:nix-community/disko -- --mode disko ./nixos/modules/disko_big.nix
#   sudo mount /dev/disk/by-label/NIXROOT /mnt
#   sudo nixos-install --flake .#big
#
# Verify disk path after Proxmox disk changes:
#   lsblk -o NAME,SIZE && ls -la /dev/disk/by-id/ | grep scsi
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              type = "EF02";
              size = "1M";
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = ["-L" "NIXROOT"];
                mountpoint = "/";
              };
            };
          };
        };
      };
      data = {
        device = "/dev/sdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions.longhorn = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              extraArgs = ["-L" "LONGHORN"];
              mountpoint = "/var/lib/longhorn";
            };
          };
        };
      };
    };
  };
}
