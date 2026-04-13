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

      # Best-effort: exclude tailscaled from Mullvad tunnel so its WireGuard
      # traffic bypasses the kill switch. Syntax varies across Mullvad versions.
      TSPID=$(pgrep tailscaled || true)
      if [ -n "$TSPID" ]; then
        mullvad split-tunnel pid add "$TSPID" 2>/dev/null ||
          mullvad split-tunnel add "$TSPID" 2>/dev/null || true
      fi

      mullvad connect --wait
    '';
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
