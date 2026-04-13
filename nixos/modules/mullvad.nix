{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.mullvad-vpn.enable = true;

  services.tailscale.useRoutingFeatures = "server";

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

  #systemd.services.mullvad-auto-connect = {
  #  description = "Auto-configure and connect Mullvad VPN";
  #  after = [ "mullvad-daemon.service" ];
  #  requires = [ "mullvad-daemon.service" ];
  #  wantedBy = [ "multi-user.target" ];
  #  path = [ config.services.mullvad-vpn.package ];
  #  serviceConfig = {
  #    Type = "oneshot";
  #    RemainAfterExit = true;
  #  };
  #  script = ''
  #    mullvad lan set allow
  #    mullvad auto-connect set on
  #    mullvad connect --wait
  #  '';
  #};

  #systemd.services.tailscale-exit-node = {
  #  description = "Advertise Tailscale exit node";
  #  after = [ "tailscaled.service" ];
  #  wants = [ "tailscaled.service" ];
  #  wantedBy = [ "multi-user.target" ];
  #  path = [ pkgs.tailscale ];
  #  serviceConfig = {
  #    Type = "oneshot";
  #    RemainAfterExit = true;
  #  };
  #  script = ''
  #    sleep 5
  #    tailscale set --advertise-exit-node
  #  '';
  #};
}
