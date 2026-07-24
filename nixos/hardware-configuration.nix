# STUB — replace after VM installation.
# Run on the VM: nixos-generate-config --root /mnt
# Then copy the generated file here: scp /mnt/etc/nixos/hardware-configuration.nix office:~/dotfiles/nixos/
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [];
  boot.initrd.availableKernelModules = ["ahci" "xhci_pci" "usbhid" "uas" "sd_mod"];
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
