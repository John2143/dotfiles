# Hetzner k3s Node — Declarative Disk Layout (disko)
#
# Used by nixos-anywhere to partition Hetzner Cloud VMs.
# Layout follows the NixOS wiki for Hetzner Cloud:
#   BIOS boot (1M, EF02) + EFI System Partition (512M) + ext4 root (rest)
#
# Reference: nixos.wiki/wiki/Install_NixOS_on_Hetzner_Cloud
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # BIOS boot partition — required for GRUB on GPT
          boot = {
            size = "1M";
            type = "EF02";
            priority = 1;
          };
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

  # Boot loader — GRUB on /dev/sda, UEFI supported
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
  };

  # Kernel modules needed for Hetzner Cloud virtio
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
    "ext4"
  ];
}
