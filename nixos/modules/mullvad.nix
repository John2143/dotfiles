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
      pkgs.iptables
      pkgs.iproute2
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

      # --- Tailscale bypass for Mullvad's kill-switch & routing ---
      # Insert at the top of OUTPUT/INPUT/FORWARD so tailscale0 traffic is
      # accepted before Mullvad's own chains (which end in DROP) are evaluated.
      iptables -C OUTPUT  -o tailscale0 -j ACCEPT 2>/dev/null || iptables -I OUTPUT  -o tailscale0 -j ACCEPT
      iptables -C INPUT   -i tailscale0 -j ACCEPT 2>/dev/null || iptables -I INPUT   -i tailscale0 -j ACCEPT
      iptables -C FORWARD -i tailscale0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i tailscale0 -j ACCEPT
      iptables -C FORWARD -o tailscale0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -o tailscale0 -j ACCEPT

      # Reverse-path routing: connections that arrive on tailscale0 must have
      # their reply packets routed back through tailscale0, not the Mullvad
      # tunnel. We connmark those connections and policy-route the replies.
      iptables -t mangle -C PREROUTING -i tailscale0 -j CONNMARK --set-mark 0x40000/0x40000 2>/dev/null \
        || iptables -t mangle -A PREROUTING -i tailscale0 -j CONNMARK --set-mark 0x40000/0x40000
      iptables -t mangle -C OUTPUT -m connmark --mark 0x40000/0x40000 -j MARK --set-mark 0x40000/0x40000 2>/dev/null \
        || iptables -t mangle -A OUTPUT -m connmark --mark 0x40000/0x40000 -j MARK --set-mark 0x40000/0x40000

      ip rule  add fwmark 0x40000/0x40000 table 200 priority 100 2>/dev/null || true
      ip route replace default dev tailscale0 table 200
    '';
  };

  # Re-apply the tailscale0 bypass rules periodically in case Mullvad
  # reconnects and re-inserts its chains ahead of ours.
  systemd.services.mullvad-tailscale-keepalive = {
    description = "Re-apply Tailscale bypass rules for Mullvad";
    after = [ "mullvad-auto-connect.service" ];
    wants = [ "mullvad-auto-connect.service" ];
    path = [
      pkgs.iptables
      pkgs.iproute2
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      # Remove then re-insert so our rules are always at position 1.
      for dir in "-o tailscale0" "-i tailscale0"; do
        chain=OUTPUT
        [ "$dir" = "-i tailscale0" ] && chain=INPUT
        iptables -D $chain $dir -j ACCEPT 2>/dev/null || true
        iptables -I $chain $dir -j ACCEPT
      done
      for dir in "-i tailscale0" "-o tailscale0"; do
        iptables -D FORWARD $dir -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD $dir -j ACCEPT
      done

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
