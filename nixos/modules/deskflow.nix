# Deskflow server: drive the MacBook's pointer and keyboard from this desktop.
#
# Server-only on Hyprland, and deliberately so: xdg-desktop-portal-hyprland
# implements the InputCapture portal (what a server needs) but not
# RemoteDesktop (what a client needs), so arch and office cannot share with each
# other — the MacBook is the client. Clipboard sync needs the Clipboard portal,
# which the Hyprland portal does not expose either; that is expected, not a bug.
#
# Nothing here is enabled at login: the server is started by hand on whichever
# machine you are sitting at (`systemctl --user start deskflow`, or the waybar
# widget's click).
{
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.deskflow];

  networking.firewall.allowedTCPPorts = [24800];

  # No uinput, udev or setuid wrapper: Deskflow 1.27.0 injects and captures
  # through libei and the XDG portal only. Do not manage ~/.config/Deskflow
  # declaratively either — the GUI writes that state, and a read-only store
  # symlink would break saving it.
  systemd.user.services.deskflow = {
    description = "Deskflow core server (start manually: systemctl --user start deskflow)";
    after = ["graphical-session.target" "xdg-desktop-portal.service"];
    partOf = ["graphical-session.target"];
    serviceConfig = {
      ExecStart = "${pkgs.deskflow}/bin/deskflow-core server";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
