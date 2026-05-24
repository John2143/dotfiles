# Home Pi — Headscale server + PowerDNS
#
# Dedicated Raspberry Pi running Headscale for the Hetzner tailnet.
# Also serves as authoritative PowerDNS server (multi-provider tiebreaker).
# PowerDNS connects to CloudNativePG PostgreSQL on k3s-ashburn via tailnet.
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
    ../modules/hetzner-postgres-schema.nix
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

  # PowerDNS connects to CloudNativePG on k3s-ashburn via tailnet
  # Override gpgsql-host from default 127.0.0.1 to the remote node
  services.powerdns.extraConfig = ''
    launch=gpgsql
    gpgsql-host=k3s-ashburn.ts.9s.pics
    gpgsql-port=30432
    gpgsql-dbname=pdns
    gpgsql-user=pdns
    gpgsql-password=@PDNS_PG_PASSWORD@

    local-address=0.0.0.0
    local-port=53

    dnsupdate=yes
    allow-dnsupdate-from=127.0.0.0/8

    default-ttl=60

    api=yes
    api-key=@PDNS_API_KEY@
    webserver=yes
    webserver-address=127.0.0.1
    webserver-port=8081

    allow-axfr-ips=127.0.0.1
  '';
  security.sudo.wheelNeedsPassword = false;

  # systemd: do NOT auto-start pdns or hetzner-postgres-schema on boot.
  # These depend on k3s-ashburn being provisioned and PostgreSQL reachable.
  # Start them manually in Phase 3 after ashburn is up.
  systemd.services.pdns = {
    wantedBy = lib.mkForce [];
    after = ["hetzner-postgres-schema.service" "tailscaled.service"];
    wants = ["hetzner-postgres-schema.service" "tailscaled.service"];
  };
  systemd.services.hetzner-postgres-schema.wantedBy = lib.mkForce [];
}
