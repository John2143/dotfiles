# Hetzner k3s Server Node
#
# Shared module for all 3 server nodes (ashburn, hillsboro, nuremberg).
# Imports: PowerDNS, MariaDB Galera, Longhorn, Tailscale.
# Provides: k3s single-node cluster + Cilium CNI + split-IP DDoS firewall.
#
# Dependency chain (systemd):
#   MariaDB Galera → PowerDNS → k3s
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hetzner-powerdns.nix
    ./hetzner-galera.nix
    ./longhorn-host.nix
    ./tailscale.nix
  ];

  # agenix secret: k3s cluster token
  age.secrets."hetzner/k3s-token" = {
    file = ../secrets/hetzner/k3s-token.age;
    owner = "root";
    group = "root";
  };

  # k3s — single-node cluster, SQLite backend
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable=traefik"
      "--disable=servicelb"
      "--cluster-cidr=10.42.0.0/16"
      "--service-cidr=10.43.0.0/16"
      "--node-external-ip=${lib.head config.networking.interfaces.eth0.ipv4.addresses}.address"
    ];
  };

  # k3s depends on PowerDNS
  systemd.services.k3s = {
    after = ["pdns.service"];
    wants = ["pdns.service"];
  };

  # ── Cilium kernel requirements ──
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };
  boot.kernelModules = ["xt_socket"];

  # ── DDoS kernel hardening ──
  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_syn_retries" = 2;
    "net.ipv4.tcp_max_syn_backlog" = 4096;
    "net.core.somaxconn" = 4096;
  };

  # ── Split-IP firewall ──
  networking.firewall.extraCommands = ''
    iptables -A INPUT -d @PROTECTED_IP@ -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --set
    iptables -A INPUT -d @PROTECTED_IP@ -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --update --seconds 1 --hitcount 50 -j DROP
    iptables -A INPUT -d @PROTECTED_IP@ -p tcp -m multiport --dports 80,443 -j ACCEPT
    iptables -A INPUT -d @PROTECTED_IP@ -j DROP

    iptables -A INPUT -d @RAW_IP@ -p udp --dport 3478 -j ACCEPT
    iptables -A INPUT -d @RAW_IP@ -p udp --dport 9987 -j ACCEPT
    iptables -A INPUT -d @RAW_IP@ -p tcp -m multiport --dports 80,443,30033 -j ACCEPT
    iptables -A INPUT -d @RAW_IP@ -j DROP
  '';

  networking.firewall.allowedTCPPorts = [6443 80 443 53 3306 4444 4567 4568];
  networking.firewall.allowedUDPPorts = [53 8472];

  environment.systemPackages = with pkgs; [
    k3s
    cilium-cli
    pdnsutil
    mariadb
    htop
    iotop
    tcpdump
  ];
}
