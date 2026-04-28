# Hardware configuration template for the NAS (i7-3770K / Z77X-UD3H).
#
# Regenerate on the actual hardware with:
#   nixos-generate-config --root /mnt --no-filesystems
# then merge the output into this file, keeping the ZFS and SATA settings.
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
    "ahci"
    "xhci_pci"
    "usb_storage"
    "sd_mod"
    "usbhid"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  boot.supportedFilesystems = ["zfs"];
  boot.zfs.extraPools = ["tank" "neo"];

  # fileSystems and swapDevices are managed by disko (see modules/disko_nas.nix)

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
