# Hetzner k3s Agent Node
#
# Fully self-contained. Imported by all 3 agent flake configs identically.
# Reads compName from specialArgs to set hostname and derive k3s serverAddr.
# Imports: Longhorn, Tailscale, SSH. No PowerDNS, no Galera.
{
  config,
  lib,
  pkgs,
  compName,
  ...
}: {
  imports = [
    ./hetzner-ssh.nix
    ./longhorn-host.nix
    ./tailscale.nix
  ];

  networking.hostName = compName;

  # agenix secret: k3s join token
  age.secrets."hetzner/k3s-token" = {
    file = ../secrets/hetzner/k3s-token.age;
    owner = "root";
    group = "root";
  };

  # k3s agent — joins the server whose hostname matches (strip "-agent" suffix)
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.age.secrets."hetzner/k3s-token".path;
    serverAddr = "https://${lib.removeSuffix "-agent" compName}:6443";
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
