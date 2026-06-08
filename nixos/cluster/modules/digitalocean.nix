# ── DigitalOcean Cloud-Init Configuration ────────────────────────────
# DO droplets bootstrap via cloud-init metadata service (169.254.169.254).
# Without this, the NixOS system has no network config after kexec/install,
# causing SSH "Connection reset by peer" during nixos-anywhere.
#
# Import this module for DO hosts only via extraModules.
#
# Sources:
#   - nixpkgs: nixos/modules/virtualisation/digital-ocean-config.nix
#   - srvos:   nixos/common/digital-ocean.nix
#   - nixos-anywhere-examples: issue #5

{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  # Cloud-init reads the DO metadata service for network configuration.
  # Disable DHCP since cloud-init handles it.
  services.cloud-init = {
    enable = true;
    settings = {
      datasource_list = [ "ConfigDrive" "DigitalOcean" ];
    };
  };

  networking.useDHCP = lib.mkForce false;
}
