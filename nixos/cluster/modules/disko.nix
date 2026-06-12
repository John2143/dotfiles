# Multi-Cloud k3s Node — Declarative Disk Layout (disko)
#
# Used by nixos-anywhere to partition cloud VMs.
# Defaults to /dev/sda (Hetzner). Set diskDevice=/dev/vda for DigitalOcean.
# Set useEFI=false for BIOS-only providers (DigitalOcean).
{
  config,
  lib,
  pkgs,
  modulesPath,
  diskDevice ? "/dev/sda",
  useEFI ? true,
  ...
}: let
  # EFI partition — only needed for UEFI boot
  efiPartition = lib.optionalAttrs useEFI {
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
  };
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  disko.devices = {
    disk.main = {
      device = diskDevice;
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
        }
        # Merge in optional EFI partition
        // efiPartition
        // {
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

  # Boot loader — GRUB (device managed by disko via mirroredBoots)
  boot.loader.grub = {
    enable = true;
    efiSupport = useEFI;
    efiInstallAsRemovable = useEFI;
  };

  # Kernel modules needed for Hetzner/DO Cloud virtio
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
