# Notification daemon selection: Quickshell (desktops) or dunst.
#
# `custom.notificationDaemon` is the only switch. This module owns BOTH branches,
# so flipping it from "quickshell" to "dunst" (one line in nixos/home.nix)
# swaps the whole set together: the daemon unit, its config files, the theme
# hook, and the SUPER+SHIFT+N history-panel bind.
#
#   "quickshell" — programs.quickshell with the `notifs` config, a hardened user
#                  unit, a 0700 state dir, and the notification centre bind.
#   "dunst"      — services.dunst with the dotfiles dunstrc, and a 10 s stop
#                  timeout so it cannot hang home-manager activation.
#
# Two daemons cannot both own org.freedesktop.Notifications, so exactly one of
# `services.dunst.enable` / `programs.quickshell` is ever true here.
{
  config,
  lib,
  pkgs,
  ...
}: let
  daemon = config.custom.notificationDaemon;
  isQuickshell = daemon == "quickshell";
  isDunst = daemon == "dunst";

  mkLua = lib.generators.mkLuaInline;
in {
  options.custom.notificationDaemon = lib.mkOption {
    type = lib.types.enum ["quickshell" "dunst"];
    default = "dunst";
    description = "Desktop notification daemon owning org.freedesktop.Notifications.";
  };

  config = lib.mkMerge [
    {
      services.dunst.enable = isDunst;
    }

    (lib.mkIf isDunst {
      # No `configFile:` — `-config` would disable dunst's drop-ins, and the
      # theme lives in dunstrc.d/50-theme.conf (nixos/modules/theme.nix).
      xdg.configFile."dunst/dunstrc".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/.config/dunst/dunstrc";

      # Aggressive stop timeout: user services that block sd-switch hang
      # home-manager activation waiting for them to stop.
      systemd.user.services.dunst.Service.TimeoutStopSec = 10;
    })

    (lib.mkIf isQuickshell {
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

      # Notification history is RAM-only (prefs.json holds just dnd/grouped), so
      # the state dir only has to exist and be private to the user.
      home.activation.quickshellStateDir = lib.hm.dag.entryBefore ["quickshellRestart"] ''
        run ${pkgs.coreutils}/bin/install -d -m 0700 "${config.xdg.stateHome}/quickshell-notifs"
      '';

      # A rebuild only replaces the config symlink; without this the old QML keeps
      # running until the next login. XDG_RUNTIME_DIR is not set when the NixOS
      # module runs activation.
      home.activation.quickshellRestart = lib.hm.dag.entryAfter ["reloadSystemd"] ''
        (
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          run ${pkgs.systemd}/bin/systemctl --user try-restart quickshell.service || true
        )
      '';

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
    })
  ];
}
