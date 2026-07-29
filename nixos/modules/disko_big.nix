# Disko configuration for the big machine (Proxmox VM, SeaBIOS / GRUB).
#
# Stable by-id paths (resistant to /dev/sdX reordering):
#   scsi-0QEMU_QEMU_HARDDISK_drive-scsi0 → boot disk  (100G,  GPT+ext4)
#   scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 → data disk  (2TB,  GPT+ext4)
#
# Partition layout:
#   boot:  scsi0-part1: BIOS boot  (1M,   EF02)
#          scsi0-part2: root       (rest, ext4,  label=NIXROOT,  mount=/)
#   data:  scsi1-part1: longhorn   (rest, ext4,  label=LONGHORN,  mount=/var/lib/longhorn)
#
# Install:
#   sudo nix --experimental-features "nix-command flakes" \
#     run github:nix-community/disko -- --mode disko ./nixos/modules/disko_big.nix
#   sudo mount /dev/disk/by-label/NIXROOT /mnt
#   sudo nixos-install --flake .#big
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
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
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
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
