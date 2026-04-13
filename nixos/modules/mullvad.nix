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

      mullvad connect --wait

      # --- Tailscale bypass for Mullvad's nftables kill-switch ---
      # Mullvad uses nftables (not iptables). Insert accept rules for
      # tailscale0 into Mullvad's own chains so traffic is accepted
      # before the kill-switch DROP rules.
      MULLVAD_TABLE=$(nft list tables inet 2>/dev/null \
        | awk 'tolower($0) ~ /mullvad/{print $3; exit}')
      if [ -n "$MULLVAD_TABLE" ]; then
        for chain in input output forward; do
          nft insert rule inet "$MULLVAD_TABLE" "$chain" \
            oifname "tailscale0" accept 2>/dev/null || true
          nft insert rule inet "$MULLVAD_TABLE" "$chain" \
            iifname "tailscale0" accept 2>/dev/null || true
        done
      fi

      # --- Reverse-path routing via conntrack marks ---
      # Connections arriving on tailscale0 get a ct mark. On output the
      # mark is copied to the packet fwmark so policy routing sends
      # replies back through tailscale0 instead of the Mullvad tunnel.
      nft delete table inet tailscale-rpf 2>/dev/null || true
      nft -f - <<'NFT_RULES'
      table inet tailscale-rpf {
        chain prerouting {
          type filter hook prerouting priority mangle; policy accept;
          iifname "tailscale0" ct mark set ct mark | 0x40000
        }
        chain output {
          type route hook output priority mangle; policy accept;
          ct mark & 0x40000 == 0x40000 meta mark set meta mark | 0x40000
        }
      }
      NFT_RULES

      # --- Policy routing for Tailscale traffic ---
      # Send Tailscale-destined traffic to Tailscale's table (52) at a
      # priority above Mullvad's catch-all rule (5209).
      ip rule  add to 100.64.0.0/10      lookup 52  priority 99 2>/dev/null || true
      ip -6 rule add to fd7a:115c:a1e0::/48 lookup 52  priority 99 2>/dev/null || true
      # Route connmark-tagged reply packets through tailscale0.
      ip rule  add fwmark 0x40000/0x40000 table 200 priority 100 2>/dev/null || true
      ip route replace default dev tailscale0 table 200
    '';
  };

  # Re-apply the tailscale0 bypass rules periodically in case Mullvad
  # reconnects and re-creates its nftables chains.
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

      # Recreate tailscale-rpf if it was lost.
      if ! nft list table inet tailscale-rpf >/dev/null 2>&1; then
        nft -f - <<'NFT_RULES'
        table inet tailscale-rpf {
          chain prerouting {
            type filter hook prerouting priority mangle; policy accept;
            iifname "tailscale0" ct mark set ct mark | 0x40000
          }
          chain output {
            type route hook output priority mangle; policy accept;
            ct mark & 0x40000 == 0x40000 meta mark set meta mark | 0x40000
          }
        }
      NFT_RULES
      fi

      ip rule  add to 100.64.0.0/10      lookup 52  priority 99 2>/dev/null || true
      ip -6 rule add to fd7a:115c:a1e0::/48 lookup 52  priority 99 2>/dev/null || true
      ip rule  add fwmark 0x40000/0x40000 table 200 priority 100 2>/dev/null || true
      ip route replace default dev tailscale0 table 200
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
