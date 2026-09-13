# ⚠ PLACEHOLDER — REPLACE BEFORE THE FIRST `nixos-rebuild switch`.
#
# This machine already runs NixOS, so its real hardware configuration
# already exists. Copy it into the repo:
#
#   ssh mirror 'sudo nixos-generate-config --show-hardware-config' \
#     > ~/repos/dotfiles/nixos/mirror-hardware-configuration.nix
#
# (or: sudo nixos-generate-config --root / --show-hardware-config on the box)
#
# The values below are a generic ext4/systemd-boot guess. They will NOT
# match this host — switching to this configuration with them unchanged
# can make the system unbootable.
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

  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usbhid" "uas" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.kernelParams = [];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXROOT";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
