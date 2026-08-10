# Disko configuration for the github VM (Proxmox VM, OVMF/UEFI, systemd-boot).
#
# Partition layout (matches github-hardware-configuration.nix — fileSystems owned by disko):
#   boot: scsi0-part1: EFI system partition (512M, EF00, vfat, label=BOOT, mount=/boot)
#   root: scsi0-part2: root (rest, ext4, label=NIXROOT, mount=/)
#
# Install:
#   sudo nix --experimental-features "nix-command flakes" \
#     run github:nix-community/disko -- --mode disko ./nixos/modules/disko_github.nix
#   sudo nixos-install --no-root-passwd --flake /tmp/dotfiles#github
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
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                extraArgs = ["-n" "BOOT"];
                mountpoint = "/boot";
              };
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
    };
  };
}
