# Hetzner k3s Server Node (with DNS)
#
# Fully self-contained. All 3 servers (ashburn, hillsboro, nuremberg)
# import this module identically. Reads compName from specialArgs.
#
# Imports: k3s-common (k3s/Cilium/ArgoCD/firewall) + PowerDNS + PostgreSQL schema + SSH.
{
  config,
  lib,
  pkgs,
  compName,
  ...
}: {
  imports = [
    ./hetzner-ssh.nix
    ./hetzner-k3s-common.nix
    ./hetzner-powerdns-bootstrap.nix
    ./hetzner-powerdns.nix
    ./hetzner-postgres-schema.nix
  ];

  networking.hostName = compName;

  # WARNING: Never do `tailscale logout; tailscale up` after initial deploy.
  # This creates a new identity with a different DNS name (e.g. k3s-ashburn → k3s-ashburn-XXXX).
  # If tailscale needs reconnection, restart `tailscaled-autoconnect` instead:
  #   systemctl restart tailscaled-autoconnect
  # If identities MUST be regenerated, clean stale nodes from headscale first:
  #   sudo headscale nodes delete --identifier <id> --force

  # PowerDNS starts after PostgreSQL schema import (which waits for CNPG in k3s).
  # k3s no longer depends on pdns — ExternalDNS inside k3s retries until pdns is ready.

  environment.systemPackages = with pkgs; [
    pdns
    postgresql
  ];
}
