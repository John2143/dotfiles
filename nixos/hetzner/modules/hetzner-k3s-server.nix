# Hetzner k3s Server Node (with DNS/DB)
#
# Fully self-contained. All 3 servers (ashburn, hillsboro, nuremberg)
# import this module identically. Reads compName + galeraOffset from specialArgs.
#
# Imports: k3s-common (k3s/Cilium/ArgoCD/firewall) + PowerDNS + Galera + SSH.
{
  config,
  lib,
  pkgs,
  compName,
  galeraOffset ? 1,
  ...
}: {
  imports = [
    ./hetzner-ssh.nix
    ./hetzner-k3s-common.nix
    ./hetzner-powerdns-bootstrap.nix
    ./hetzner-powerdns.nix
    ./hetzner-galera.nix
  ];

  networking.hostName = compName;

  # Galera cluster — uses Tailscale MagicDNS for cross-node discovery.
  # WARNING: Never do `tailscale logout; tailscale up` after initial deploy.
  # This creates a new identity with a different DNS name (e.g. k3s-ashburn → k3s-ashburn-XXXX).
  # If tailscale needs reconnection, restart `tailscaled-autoconnect` instead:
  #   systemctl restart tailscaled-autoconnect
  # If identities MUST be regenerated, clean stale nodes from headscale first:
  #   sudo headscale nodes delete --identifier <id> --force
  services.mysql.settings.mysqld = {
    # wsrep_cluster_address is set post-bootstrap (see README Galera bootstrap).
    # Default from hetzner-galera.nix is gcomm:// (standalone).
    wsrep_node_name = compName;
    auto_increment_offset = galeraOffset;
  };

  # k3s depends on PowerDNS
  systemd.services.k3s = {
    after = ["pdns.service"];
    wants = ["pdns.service"];
  };

  environment.systemPackages = with pkgs; [
    pdns
    mariadb
  ];
}
