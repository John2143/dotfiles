# Hillsboro Server — CPX31, US West
# k3s server (no PowerDNS, no Galera — runs on Ashburn + Nuremberg + Home Pi)
{
  config,
  lib,
  pkgs,
  inputs,
  compName,
  sshKeys,
  ...
}: {
  imports = [
    ../modules/hetzner-disko.nix
    # NOTE: Does NOT import PowerDNS or Galera modules.
    # Hillsboro runs k3s + apps only. DNS is handled by Ashburn, Nuremberg, Home Pi.
  ];

  networking.hostName = "k3s-hillsboro";

  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  # k3s single-node cluster (imported inline — no shared module needed without DNS/DB)
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

  environment.systemPackages = with pkgs; [k3s cilium-cli htop tcpdump];
}
