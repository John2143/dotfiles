{
  config,
  lib,
  pkgs,
  ...
}: {
  # greetd instead of lemurs on the Hyprland desktops. lemurs 0.4.0 opens the PAM
  # session inside its own long-lived process, so every login after the first one in
  # a boot gets no logind session and lemurs falls back to XDG_SESSION_ID=1 — the
  # user manager's session. Noctalia's polkit agent then fails to register ("Passed
  # session and the session the caller is in differs") and the lock monitor watches
  # the wrong session (arch, 2026-11-26). greetd forks a session worker per login,
  # so each login gets its own session.
  #
  # No autologin: the login password is what unlocks gnome-keyring. greetd's PAM
  # service includes `login`, which services.gnome.gnome-keyring already wires.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = lib.concatStringsSep " " [
      (lib.getExe pkgs.tuigreet)
      "--time"
      "--remember"
      "--asterisks"
      "--cmd"
      (lib.getExe' config.programs.hyprland.package "start-hyprland")
    ];
  };

  # Hyprland reaches the DRM/input devices through seatd today (seatd logs it as a
  # client); keep that path unchanged. The lemurs module used to enable this for office.
  services.seatd.enable = true;
}
