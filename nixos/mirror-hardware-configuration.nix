# Hardware configuration for `mirror` — Raspberry Pi 4 Model B Rev 1.1 (aarch64).
#
# Captured from the machine itself:
#   ssh mirror 'sudo nixos-generate-config --show-hardware-config'
#
# Three things here are load-bearing:
#
#  1. nixpkgs.hostPlatform is what makes this host build for ARM at all.
#     flake.nix passes `system = "x86_64-linux"` to EVERY host via mkHost, and
#     this mkDefault is what overrides it — the same mechanism pite/aman/vpin
#     rely on. Without the aarch64 value the closure is x86_64 and
#     `nixos-rebuild switch` dies with "Exec format error", because the
#     activation script it tries to run is an x86_64 binary.
#
#  2. / is the SD card (mmcblk0p2, ext4). 44444444-… is the fixed root UUID the
#     NixOS aarch64 SD-image uses, so this is an SD-image-derived install.
#
#  3. /boot/firmware is the 30 MB vfat firmware partition (mmcblk0p1) holding
#     u-boot and config.txt. There is deliberately no /boot mount: the kernel
#     and initrd live in /boot/nixos on the root filesystem, which is what
#     u-boot's distro-boot reads via /boot/extlinux/extlinux.conf.
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

  boot.initrd.availableKernelModules = ["xhci_pci" "usbhid"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
    fsType = "ext4";
  };

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-uuid/2178-694E";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}