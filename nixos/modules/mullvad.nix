{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.mullvad-vpn.enable = true;

  services.tailscale.useRoutingFeatures = "both";

  networking.firewall = {
    enable = lib.mkForce true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    extraCommands = ''
      iptables -t nat -A POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE
    '';
    extraStopCommands = ''
      iptables -t nat -D POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE || true
    '';
  };

  systemd.services.mullvad-auto-connect = {
    description = "Auto-configure and connect Mullvad VPN";
    after = [
      "mullvad-daemon.service"
      "tailscaled.service"
    ];
    requires = [ "mullvad-daemon.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.services.mullvad-vpn.package
      pkgs.procps
      pkgs.nftables
      pkgs.iproute2
      pkgs.gnugrep
      pkgs.gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mullvad lan set allow
      mullvad auto-connect set on
      mullvad tunnel set ipv6 on
      mullvad tunnel set quantum-resistant on

      TSPID=$(pgrep tailscaled || true)
      if [ -n "$TSPID" ]; then
        mullvad split-tunnel pid add "$TSPID" 2>/dev/null ||
          mullvad split-tunnel add "$TSPID" 2>/dev/null || true
      fi

      # Clean stale ip rules from previous runs so Mullvad doesn't
      # keep leapfrogging them with lower priority numbers.
      while ip rule del to 100.64.0.0/10 lookup 52 2>/dev/null; do :; done
      while ip -6 rule del to fd7a:115c:a1e0::/48 lookup 52 2>/dev/null; do :; done
      ip rule del fwmark 0x40000/0x40000 table 200 2>/dev/null || true
      ip route flush table 200 2>/dev/null || true

      mullvad connect --wait

      # --- Inject Tailscale route into Mullvad's own routing table ---
      # Mullvad's catch-all ip rule sends all non-Mullvad traffic to its
      # routing table (0x6d6f6c65 / 1836018789). By adding a more-specific
      # route for the Tailscale CGNAT range inside that table, packets to
      # Tailscale peers hit our route before Mullvad's default route.
      # This avoids the priority arms-race entirely.
      MULLVAD_RT=$(ip rule show \
        | awk '/0x6d6f6c65/{print $NF; exit}')
      if [ -n "$MULLVAD_RT" ]; then
        ip route replace 100.64.0.0/10 dev tailscale0 table "$MULLVAD_RT"
      fi
      MULLVAD_RT6=$(ip -6 rule show \
        | awk '/0x6d6f6c65/{print $NF; exit}')
      if [ -n "$MULLVAD_RT6" ]; then
        ip -6 route replace fd7a:115c:a1e0::/48 dev tailscale0 table "$MULLVAD_RT6"
      fi

      # --- Tailscale bypass for Mullvad's nftables kill-switch ---
      MULLVAD_TABLE=$(nft list tables inet 2>/dev/null \
        | awk 'tolower($0) ~ /mullvad/{print $3; exit}')
      if [ -n "$MULLVAD_TABLE" ]; then
        for chain in input output forward; do
          nft insert rule inet "$MULLVAD_TABLE" "$chain" \
            oifname "tailscale0" accept 2>/dev/null || true
          nft insert rule inet "$MULLVAD_TABLE" "$chain" \
            iifname "tailscale0" accept 2>/dev/null || true
        done
        # Allow tailscaled's WireGuard packets (fwmark 0x80000) through
        # the kill-switch so direct LAN peer connections work.
        nft insert rule inet "$MULLVAD_TABLE" output \
          meta mark \& 0x80000 == 0x80000 accept 2>/dev/null || true
      fi
    '';
  };

  # Re-apply bypass rules periodically in case Mullvad reconnects
  # and re-creates its nftables chains or flushes its routing table.
  systemd.services.mullvad-tailscale-keepalive = {
    description = "Re-apply Tailscale bypass rules for Mullvad";
    after = [ "mullvad-auto-connect.service" ];
    wants = [ "mullvad-auto-connect.service" ];
    path = [
      pkgs.nftables
      pkgs.iproute2
      pkgs.gnugrep
      pkgs.gawk
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      MULLVAD_RT=$(ip rule show \
        | awk '/0x6d6f6c65/{print $NF; exit}')
      if [ -n "$MULLVAD_RT" ]; then
        ip route replace 100.64.0.0/10 dev tailscale0 table "$MULLVAD_RT"
      fi
      MULLVAD_RT6=$(ip -6 rule show \
        | awk '/0x6d6f6c65/{print $NF; exit}')
      if [ -n "$MULLVAD_RT6" ]; then
        ip -6 route replace fd7a:115c:a1e0::/48 dev tailscale0 table "$MULLVAD_RT6"
      fi

      MULLVAD_TABLE=$(nft list tables inet 2>/dev/null \
        | awk 'tolower($0) ~ /mullvad/{print $3; exit}')
      [ -z "$MULLVAD_TABLE" ] && exit 0

      for chain in input output forward; do
        if ! nft list chain inet "$MULLVAD_TABLE" "$chain" 2>/dev/null \
             | grep -q 'tailscale0'; then
          nft insert rule inet "$MULLVAD_TABLE" "$chain" \
            oifname "tailscale0" accept 2>/dev/null || true
          nft insert rule inet "$MULLVAD_TABLE" "$chain" \
            iifname "tailscale0" accept 2>/dev/null || true
        fi
      done

      if ! nft list chain inet "$MULLVAD_TABLE" output 2>/dev/null \
           | grep -q '0x80000'; then
        nft insert rule inet "$MULLVAD_TABLE" output \
          meta mark \& 0x80000 == 0x80000 accept 2>/dev/null || true
      fi
    '';
  };

  systemd.timers.mullvad-tailscale-keepalive = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
    };
  };

  systemd.services.tailscale-exit-node = {
    description = "Advertise Tailscale exit node";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.tailscale ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      sleep 5
      tailscale set --advertise-exit-node
    '';
  };
}
