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
  # Important: Only update if we have CHANGED. otherwise we get rate-limited by deSEC.
  systemd.services.desec-ddns-headscale-9s-pics = {
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

      # Check if we have changed or not:
      # do direct DNS query without caching to get current DNS record
      # First try 1.1.1.1, then 1.0.0.1, then 8.8.8.8
      CURRENT_IP=$(dig +short headscale.9s.pics @1.1.1.1 +noall +answer || dig +short headscale.9s.pics @1.0.0.1 +noall +answer || dig +short headscale.9s.pics @8.8.8.8)
      if [ "$CURRENT_IP" = "$IP" ]; then
        echo "OK: headscale.9s.pics already points to $IP, no update needed"
        exit 0
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

  systemd.timers.desec-ddns-headscale-9s-pics = {
    description = "Update deSEC DNS every 30 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/30";
      Persistent = true;
    };
  };

  # ── deSEC DDNS: update m.2143.me every 30 minutes ──
  systemd.services.desec-ddns-m-2143-me = {
    description = "Update deSEC DNS A record for m.2143.me";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.curl pkgs.dnsutils];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail
      TOKEN=$(cat ${config.age.secrets."hetzner/desec-token".path})
      API="https://desec.io/api/v1/domains/2143.me/rrsets"
      IP=$(curl -4sf --connect-timeout 10 ifconfig.me 2>/dev/null || curl -4sf --connect-timeout 10 icanhazip.com 2>/dev/null || curl -4sf --connect-timeout 10 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | grep ^ip= | cut -d= -f2)
      if [ -z "$IP" ]; then
        echo "ERROR: Could not determine public IP"
        exit 1
      fi
      CURRENT_IP=$(dig +short m.2143.me @1.1.1.1 +noall +answer || dig +short m.2143.me @1.0.0.1 +noall +answer || dig +short m.2143.me @8.8.8.8)
      if [ "$CURRENT_IP" = "$IP" ]; then
        echo "OK: m.2143.me already points to $IP, no update needed"
        exit 0
      fi
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$API/m/A/" \
        -d "{\"records\":[\"$IP\"]}")
      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo "OK: m.2143.me -> $IP (PATCH $HTTP_CODE)"
      else
        curl -sf -X POST \
          -H "Authorization: Token $TOKEN" \
          -H "Content-Type: application/json" \
          "$API/" \
          -d "{\"subname\":\"m\",\"type\":\"A\",\"ttl\":300,\"records\":[\"$IP\"]}"
        echo "OK: m.2143.me -> $IP (POST created)"
      fi
    '';
  };
  systemd.timers.desec-ddns-m-2143-me = {
    description = "Update m.2143.me DNS every 30 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/30";
      Persistent = true;
    };
  };

  # ── deSEC DDNS: update john2143.com every 30 minutes ──
  systemd.services.desec-ddns-john2143-com = {
    description = "Update deSEC DNS A record for john2143.com";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.curl pkgs.dnsutils];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail
      TOKEN=$(cat ${config.age.secrets."hetzner/desec-token".path})
      API="https://desec.io/api/v1/domains/john2143.com/rrsets"
      IP=$(curl -4sf --connect-timeout 10 ifconfig.me 2>/dev/null || curl -4sf --connect-timeout 10 icanhazip.com 2>/dev/null || curl -4sf --connect-timeout 10 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | grep ^ip= | cut -d= -f2)
      if [ -z "$IP" ]; then
        echo "ERROR: Could not determine public IP"
        exit 1
      fi
      CURRENT_IP=$(dig +short john2143.com @1.1.1.1 +noall +answer || dig +short john2143.com @1.0.0.1 +noall +answer || dig +short john2143.com @8.8.8.8)
      if [ "$CURRENT_IP" = "$IP" ]; then
        echo "OK: john2143.com already points to $IP, no update needed"
        exit 0
      fi
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$API/A/" \
        -d "{\"records\":[\"$IP\"]}")
      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo "OK: john2143.com -> $IP (PATCH $HTTP_CODE)"
      else
        curl -sf -X POST \
          -H "Authorization: Token $TOKEN" \
          -H "Content-Type: application/json" \
          "$API/" \
          -d "{\"subname\":\"\",\"type\":\"A\",\"ttl\":300,\"records\":[\"$IP\"]}"
        echo "OK: john2143.com -> $IP (POST created)"
      fi
    '';
  };
  systemd.timers.desec-ddns-john2143-com = {
    description = "Update john2143.com DNS every 30 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/30";
      Persistent = true;
    };
  };

}
