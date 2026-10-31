# Keep the GL-KVM kiosk signed in.
#
# The GL-KVM web UI authenticates with a *browser-session* cookie, so a Firefox
# restart drops it and the kiosk sits on #/login. The admin password is already
# saved in the Firefox profile and autofilled into #form_item_passwd, so the
# only missing step is pressing "Log In". The script clicks it over Firefox's
# built-in Marionette protocol (127.0.0.1:2828) — DOM lookup, not fixed
# coordinates — and is idempotent: with the session intact it does nothing.
#
# Deliberately a long-running Type=simple service, NOT a oneshot. A oneshot that
# waits for the browser to appear blocks home-manager activation ("timed out
# waiting on channel"), which fails the whole `nixos-rebuild switch`. This
# service starts instantly and simply retries every minute.
#
# See secu-startup.nix, which launches Firefox with --marionette.
{ pkgs, ... }: {
  home-manager.users.john.systemd.user.services.glkvm-autologin = {
    Unit.Description = "Keep the GL-KVM login submitted in the kiosk Firefox";
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "glkvm-autologin.py" (builtins.readFile ./glkvm-autologin.py)}";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
