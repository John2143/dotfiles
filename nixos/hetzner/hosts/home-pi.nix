# Home Pi — Headscale server + Galera #4 + PowerDNS #4
#
# Dedicated Raspberry Pi running Headscale for the Hetzner tailnet.
# Also serves as a MariaDB Galera node (PowerDNS backend) and
# authoritative PowerDNS server (multi-provider tiebreaker).
#
# Permanent node — not part of the Hetzner rolling rotation.
# Provisioned manually at home.
# Must be provisioned FIRST — Hetzner nodes depend on its Headscale.
{
  config,
  lib,
  pkgs,
  sshKeys,
  ...
}: {
  imports = [
    ./home-pi-hardware-configuration.nix
    ../modules/headscale.nix
    ../modules/hetzner-ssh.nix
    ../modules/hetzner-powerdns-bootstrap.nix
    ../modules/hetzner-galera.nix
    ../modules/hetzner-powerdns.nix
    ../modules/tailscale.nix
  ];

  networking.hostName = "home-pi";

  # agenix identity
  age.identityPaths = ["/home/john/.ssh/age"];

  # Bootloader (Pi uses extlinux)
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  system.stateVersion = "26.05";

  # SSH and user
  services.openssh.enable = true;
  users.users.john = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = sshKeys;
 };

  # Connect to the local Headscale instance running on this host
  custom.headscaleServer = "http://localhost:6767";

  # Galera cluster — see hetzner-k3s-server.nix for DNS/identity warnings
  services.mysql.settings.mysqld = {
    # wsrep_cluster_address is set post-bootstrap (see README Galera bootstrap).
    # Default from hetzner-galera.nix is gcomm:// (standalone).
    wsrep_node_name = "home-pi";
    auto_increment_offset = 4;
  };
  security.sudo.wheelNeedsPassword = false;

  # systemd ordering: wait for Tailscale DNS before starting PowerDNS
  systemd.services.pdns = {
    after = ["mysql.service" "tailscaled.service"];
    wants = ["mysql.service" "tailscaled.service"];
  };
}
