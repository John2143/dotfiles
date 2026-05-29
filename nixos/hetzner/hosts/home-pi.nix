# Home Pi — Headscale server
#
# Dedicated Raspberry Pi running Headscale for the Hetzner tailnet.
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
    ../modules/tailscale.nix
    ../../modules/attic-server.nix
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

  security.sudo.wheelNeedsPassword = false;


  # ── deSEC DDNS: update headscale.9s.pics every 5 minutes ──
  systemd.services.desec-ddns = {
    description = "Update deSEC DNS A record for headscale.9s.pics";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.curl];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail
      TOKEN=$(cat ${config.age.secrets."hetzner/desec-token".path})
      API="https://desec.io/api/v1/domains/9s.pics/rrsets"

      IP=$(curl -4sf --connect-timeout 10 ifconfig.me 2>/dev/null || curl -4sf --connect-timeout 10 icanhazip.com 2>/dev/null)
      if [ -z "$IP" ]; then
        echo "ERROR: Could not determine public IP"
        exit 1
      fi

      # Try PATCH (update existing), fall back to POST (create new)
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$API/headscale/A/" \
        -d "{\"records\":[\"$IP\"]}")
      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo "OK: headscale.9s.pics -> $IP (PATCH $HTTP_CODE)"
      else
        curl -sf -X POST \
          -H "Authorization: Token $TOKEN" \
          -H "Content-Type: application/json" \
          "$API/" \
          -d "{\"subname\":\"headscale\",\"type\":\"A\",\"ttl\":300,\"records\":[\"$IP\"]}"
        echo "OK: headscale.9s.pics -> $IP (POST created)"
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
