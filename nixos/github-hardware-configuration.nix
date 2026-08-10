# Hardware configuration for the github VM (Proxmox VM, OVMF/UEFI, virtio).
#
# fileSystems and swapDevices are managed by disko (see modules/disko_github.nix).
# Virtio initrd modules come from the qemu-guest profile imported in
# github-configuration.nix.
{
  config,
  lib,
  pkgs,
  ...
}: {
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
