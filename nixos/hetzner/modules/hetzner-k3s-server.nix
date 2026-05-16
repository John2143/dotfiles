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

  # Galera node-specific — uses Tailscale MagicDNS
  services.mysql.settings.mysqld = {
    wsrep_cluster_address = "gcomm://k3s-ashburn.ts.9s.pics,k3s-hillsboro.ts.9s.pics,k3s-nuremberg.ts.9s.pics,home-pi.ts.9s.pics";
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
