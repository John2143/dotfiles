# Quickshell notification daemon + notification centre (replaces dunst).
#
# `local.quickshellNotifs.enable` is the only switch: it turns on
# programs.quickshell with the `notifs` config, hardens the user unit, claims
# org.freedesktop.Notifications by forcing services.dunst off, and binds
# SUPER+SHIFT+N to the history panel. Flipping it back to false restores dunst
# unchanged — nixos/home.nix gates every dunst-only file on
# `config.services.dunst.enable`, and its `services.dunst.enable` is only a
# default so this module's mkForce wins.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.quickshellNotifs;

  mkLua = lib.generators.mkLuaInline;
in {
  options.local.quickshellNotifs.enable = lib.mkEnableOption "Quickshell notification daemon and centre";

  config = lib.mkIf cfg.enable {
    programs.quickshell = {
      enable = true;
      configs.notifs = ../../.config/quickshell/notifs;
      # Named config: quickshell resolves `~/.config/quickshell/notifs` (the HM
      # symlink) and `qs ipc -c notifs` then reaches this instance.
      activeConfig = "notifs";
      systemd.enable = true;
    };

    # programs.quickshell only writes ExecStart/Restart (and its own
    # After=session target). PartOf ties the unit's lifetime to the session,
    # and the restart limits stop a config that throws on load from
    # restarting forever.
    systemd.user.services.quickshell = {
      Unit = {
        PartOf = [config.wayland.systemd.target];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };
      Service = {
        RestartSec = 3;
        TimeoutStopSec = 10;
        # The reload popup would sit on top of the toasts after every switch.
        Environment = ["QS_NO_RELOAD_POPUP=1"];
      };
    };

    # A rebuild only replaces the config symlink; without this the old QML keeps
    # running until the next login. XDG_RUNTIME_DIR is not set when the NixOS
    # module runs activation.
    home.activation.quickshellRestart = lib.hm.dag.entryAfter ["reloadSystemd"] ''
      (
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        run ${pkgs.systemd}/bin/systemctl --user try-restart quickshell.service || true
      )
    '';

    # Two servers cannot both own org.freedesktop.Notifications; the second one
    # to start fails silently and its clients get no notifications at all.
    services.dunst.enable = lib.mkForce false;

    wayland.windowManager.hyprland.settings = {
      # Notification centre. Toasts are click-through, so they need no bind.
      bind = [
        {_args = [(mkLua ''mainMod .. " + SHIFT + N"'') (mkLua ''hl.dsp.exec_cmd([[qs ipc -c notifs call notifs toggle]])'')];}
      ];
      # Both are layer surfaces: blur them like waybar, and ignorezero keeps
      # Hyprland from dropping the whole layer while the panel is unmapped.
      # Lives under `config.layerrule` (inside hl.config({...})) to match home.nix.
      config.layerrule = [
        "blur,qs-notifs-panel"
        "ignorezero,qs-notifs-panel"
        "blur,qs-notifs-toasts"
        "ignorezero,qs-notifs-toasts"
      ];
    };
  };
}
