# Hetzner k3s Agent Node
#
# Shared module for all 3 agent nodes (ashburn, hillsboro, nuremberg).
# Imports: Longhorn, Tailscale. No PowerDNS, no Galera.
# Provides: k3s agent joining the server's cluster + Cilium CNI + split-IP DDoS firewall.
#
# Agent nodes are the HA toggle — provisioned/destroyed via scripts.
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./longhorn-host.nix
    ./tailscale.nix
  ];

  # agenix secret: k3s join token
  age.secrets."hetzner/k3s-token" = {
    file = ../secrets/hetzner/k3s-token.age;
    owner = "root";
    group = "root";
  };

  # k3s agent — serverAddr set in host config
  services.k3s = {
    enable = true;
    role = "agent";
    extraFlags = toString [
      "--flannel-backend=none"
    ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };
  boot.kernelModules = ["xt_socket"];

  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_syn_retries" = 2;
  };

  networking.firewall.allowedTCPPorts = [80 443 6443];
  networking.firewall.allowedUDPPorts = [8472];

  environment.systemPackages = with pkgs; [
    k3s
    htop
    tcpdump
  ];
}
