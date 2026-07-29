# Hardware configuration for the big machine (Proxmox VM).
#
# Regenerate on the actual hardware with:
#   nixos-generate-config --root /mnt --no-filesystems
# then merge the output into this file, keeping the virtio module list.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "sd_mod"
    "ext4"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  # fileSystems and swapDevices are managed by disko (see modules/disko_big.nix)

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
