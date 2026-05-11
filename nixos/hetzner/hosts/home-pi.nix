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
  custom.headscaleServer = "http://localhost:8080";

  # Galera node-specific — fourth multi-master node (permanent)
  services.mysql.settings.mysqld = {
    wsrep_cluster_address = "gcomm://k3s-ashburn.9s.pics,k3s-hillsboro.9s.pics,k3s-nuremberg.9s.pics,home-pi.9s.pics";
    wsrep_node_name = "home-pi";
    auto_increment_offset = 4;
  };

  # systemd ordering: wait for Tailscale DNS before starting PowerDNS
  systemd.services.pdns = {
    after = ["mysql.service" "tailscaled.service"];
    wants = ["mysql.service" "tailscaled.service"];
  };
}
