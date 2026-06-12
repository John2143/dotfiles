# ── DigitalOcean Networking ──────────────────────────────────────────
# DO droplets get network config via DHCP on the public interface.
# No cloud-init metadata service needed — the flake already hardcodes
# SSH authorized_keys and hostname.
#
# The built-in NixOS digital-ocean-config module is known to interfere
# with networking (it sets useDHCP=false and relies on the metadata
# service, which doesn't always work with nixos-anywhere).

{ lib, ... }:

{
  # DHCP provides IP config on DO's public interface
  networking.useDHCP = lib.mkDefault true;
}
