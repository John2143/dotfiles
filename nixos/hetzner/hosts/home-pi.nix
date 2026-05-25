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

  # agenix identity + secrets
  age.identityPaths = ["/home/john/.ssh/age"];
  age.secrets."hetzner/desec-token" = {
    file = ../secrets/hetzner/desec-token.age;
    owner = "root";
    group = "root";
  };

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

  # ── deSEC DDNS: update headscale.9s.pics every 5 minutes ──
  systemd.services.desec-ddns = {
    description = "Update deSEC DNS A record for headscale.9s.pics";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.curl pkgs.python3];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "desec-ddns";
      ReadOnlyPaths = [config.age.secrets."hetzner/desec-token".path];
    };
    script = ''
      set -euo pipefail
      TOKEN=$(cat ${config.age.secrets."hetzner/desec-token".path})
      API="https://desec.io/api/v1/domains/9s.pics/rrsets"

      IP=$(curl -sf --connect-timeout 10 ifconfig.me 2>/dev/null || curl -sf --connect-timeout 10 icanhazip.com 2>/dev/null)
      if [ -z "$IP" ]; then
        echo "ERROR: Could not determine public IP"
        exit 1
      fi

      CURRENT=$(curl -sf -H "Authorization: Token $TOKEN" "$API/headscale/A/" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['records'][0])" 2>/dev/null || echo "")

      if [ "$IP" = "$CURRENT" ]; then
        echo "IP unchanged: $IP"
        exit 0
      fi

      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$API/headscale/A/" \
        -d "{\"records\":[\"$IP\"]}")
      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo "Updated headscale.9s.pics: $CURRENT -> $IP"
      else
        curl -sf -X POST \
          -H "Authorization: Token $TOKEN" \
          -H "Content-Type: application/json" \
          "$API/" \
          -d "{\"subname\":\"headscale\",\"type\":\"A\",\"ttl\":300,\"records\":[\"$IP\"]}"
        echo "Created headscale.9s.pics: $IP"
      fi
    '';
  };

  systemd.timers.desec-ddns = {
    description = "Update deSEC DNS every 5 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };
}
