# Hardware configuration for the steam VM (Proxmox VM, SeaBIOS / GRUB, virtio).
#
# fileSystems and swapDevices are managed by disko (see modules/disko_steam.nix).
# Virtio initrd modules come from the qemu-guest profile imported in
# steam-configuration.nix.
{
  config,
  lib,
  pkgs,
  ...
}: {
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
