# Re-open the GL-KVM session in the kiosk Firefox after every start.
#
# The GL-KVM web UI authenticates with a *browser-session* cookie, so Firefox
# drops it on restart and the kiosk lands on #/login every boot. The admin
# password is already stored in the Firefox profile and autofilled into
# #form_item_passwd, so the only manual step left is pressing "Log In".
#
# This service presses it over Firefox's built-in Marionette protocol
# (127.0.0.1:2828) instead of synthetic mouse events at fixed coordinates: it
# finds the button in the DOM, so a layout change cannot break it. See
# secu-startup.nix, which launches Firefox with --marionette.
#
# Failure is visible rather than silent: with no saved password the script logs
# that and exits 1 instead of guessing.
{ pkgs, ... }: {
  home-manager.users.john.systemd.user.services.glkvm-autologin = {
    Unit = {
      Description = "Submit the GL-KVM admin login in the kiosk Firefox";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "glkvm-autologin.py" (builtins.readFile ./glkvm-autologin.py)}";
      # Firefox is launched by the compositor a few seconds after the session
      # target; the script itself waits for the Marionette port to appear.
      TimeoutStartSec = "15min";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
}
