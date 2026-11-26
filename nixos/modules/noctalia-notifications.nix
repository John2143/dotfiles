# Noctalia, notification layer only.
#
# Noctalia can be a whole desktop shell, but this machine already has an owner
# for every other surface, so the module enables only the notification daemon
# (org.freedesktop.Notifications), its toasts, and the Control Center's
# notifications tab. One owner per subsystem, or the two fight:
#
#   subsystem       owned by                  why noctalia's is off
#   bar             waybar                    a second bar would claim the same layer edges
#   dock            nothing                   an unused extra layer surface on every output
#   wallpaper       hyprpaper (theme.nix)     noctalia would repaint over the themed wallpaper
#   lockscreen      hyprlock (theme.nix)      home.nix locks manually only; noctalia's
#                                             lock_before_suspend would add a second,
#                                             idle-triggered lock path
#   clipboard       cliphist + wofi           noctalia history would duplicate cliphist's store
#   osd             none (pamixer / voxtype)  avoids unrequested volume/media popups
#   weather/system monitor/desktop widgets
#                   waybar + eww              noctalia's copies would duplicate them
#   templates       theme.nix                 theme.nix renders every app config itself and
#                                             hyprland.lua is an HM symlink; letting noctalia
#                                             template would give two writers per file
#
# Hyprland layer rules below cover the only two surfaces that remain.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.noctalia-notifications;

  # Palette JSON role names -> Catppuccin keys from theme.nix (which stores bare
  # hex; noctalia wants CSS strings, hence the '#' in front).
  paletteFor = mode: let
    p = config.myTheme.palettes.${mode};
    c = role: "#${p.${role}}";
  in {
    primary = c "mauve";
    on_primary = c "base";
    secondary = c "teal";
    on_secondary = c "base";
    tertiary = c "green";
    on_tertiary = c "base";
    error = c "red";
    on_error = c "base";
    surface = c "base";
    on_surface = c "text";
    surface_container = c "surface0";
    on_surface_variant = c "subtext0";
    outline_variant = c "surface1";
    shadow = c "crust";
    hover = c "surface0";
    on_hover = c "text";
  };

  baseSettings = {
    # `null` keeps the master key in the Secret Service (gnome-keyring), which
    # is what a logged-in session has. Set it to
    # /run/agenix/noctalia-notifications-key (64 lowercase hex chars, mode 0400)
    # once that secret is provisioned, so history also works when the keyring is
    # locked; see docs/noctalia-notifications.md.
    storage =
      if cfg.storageKeyFile != null
      then {
        key_source = "file";
        key_file = cfg.storageKeyFile;
      }
      else {
        key_source = "secret-service";
      };

    theme = {
      # Starting mode; `theme-switch` moves it at runtime with
      # `noctalia msg theme-mode-set`.
      mode = "dark";
      source = "custom";
      custom_palette = "Catppuccin";
      templates = {
        builtin_ids = [];
        community_ids = [];
        enable_builtin_templates = false;
        enable_community_templates = false;
      };
    };

    bar.default.enabled = false;
    dock.enabled = false;
    desktop_widgets.enabled = false;
    lockscreen = {
      enabled = false;
      lock_before_suspend = false;
    };
    wallpaper.enabled = false;
    weather.enabled = false;
    calendar.enabled = false;
    nightlight.enabled = false;
    hot_corners.enabled = false;
    system.monitor.enabled = false;
    osd.enabled = false;

    plugins = {
      auto_update = "none";
      enabled = [];
    };

    shell = {
      font_family = "JetBrainsMono Nerd Font";
      clipboard_enabled = false; # cliphist owns history
      polkit_agent = false; # lxqt-policykit-agent owns PolicyKit1 (home.nix)
      setup_wizard_enabled = false; # nothing to configure at first run
      telemetry_enabled = false;
      screen_time_enabled = false;
      external_ip_enabled = false;
      offline_mode = true;
      panel = {
        control_center_placement = "floating";
        control_center_position = "center";
        floating_layer = "overlay";
      };
    };

    control_center = {
      sidebar = "compact";
      sidebar_section = "none";
      width = 600;
      show_session_button = false;
      hidden_tabs = [
        "media"
        "audio"
        "monitor"
        "system"
        "network"
        "bluetooth"
        "weather"
        "calendar"
        "screen-time"
        "power"
      ];
    };

    notification = {
      enable_daemon = true;
      show_app_name = true;
      show_actions = true;
      show_progress_bar = true;
      position = "top_right";
      layer = "top";
      width = 360;
      background_opacity = 0.97;
      border = true;
      border_color = "outline_variant";
      border_width = 2;
      follow_focused_output = true;
      offset_x = 10;
      offset_y = 40;
      newest_on_edge = true;
      collapse_on_dismiss = true;
      keep_dismissed_in_history = true;
      group_by_app = true;
      max_visible = 20;
      history_retention_hours = cfg.historyRetentionHours;

      # First matching filter wins, so order is load-bearing:
      #   base-stations        LHB-* standby chatter is dropped to history only;
      #                        it must be first or a catch-all would toast it.
      #   critical-bypass-dnd  before silent-default, otherwise critical alerts
      #                        would fall into the catch-all and stop bypassing DND.
      #   silent-default       catch-all last.
      # Every filter sets play_sound = false because noctalia's per-filter default
      # is true: without it both catch-alls would ping on every notification,
      # which dunst did not do (theme-switch reloads dunstctl-style silence).
      filter_order = [
        "base-stations"
        "critical-bypass-dnd"
        "silent-default"
      ];
      filter = {
        base-stations = {
          enabled = true;
          match = "";
          match_content = "^LHB-";
          show_toast = false;
          save_history = false;
          play_sound = false;
        };
        critical-bypass-dnd = {
          enabled = true;
          match = "";
          match_content = ".*";
          allowed_urgencies = ["critical"];
          show_toast = true;
          save_history = true;
          play_sound = false;
          bypass_dnd = true;
        };
        silent-default = {
          enabled = true;
          match = "";
          match_content = ".*";
          show_toast = true;
          save_history = true;
          play_sound = false;
        };
      };
    };
  };
in {
  options.services.noctalia-notifications = {
    enable = lib.mkEnableOption "Noctalia as the Wayland notification daemon (toasts + Control Center notifications tab only)";

    package = lib.mkPackageOption pkgs "noctalia" {};

    storageKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/agenix/noctalia-notifications-key";
      description = ''
        Absolute path to a user-readable file holding the 64-character lowercase
        hex storage master key. When null, the key comes from the Secret Service
        (`storage.key_source = "secret-service"`); when set, it is read from this
        file instead. See docs/noctalia-notifications.md for the agenix secret.
      '';
    };

    historyRetentionHours = lib.mkOption {
      type = lib.types.ints.between 0 8760;
      default = 0;
      description = "Delete stored notification history older than this many hours; 0 keeps it indefinitely.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Extra noctalia `config.toml` settings, recursively merged on top of this
        module's notification-layer baseline (later wins per key).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.dunst.enable;
        message = "services.noctalia-notifications cannot be enabled while services.dunst.enable is true: only one process may own org.freedesktop.Notifications on Wayland.";
      }
    ];

    programs.noctalia = {
      enable = true;
      package = cfg.package;
      systemd.enable = true;
      checkConfig = true;

      # Palette JSON format 2: role names as keys, plus `base` so the picker
      # groups custom and built-in Catppuccin together. No `terminal` block —
      # alacritty is themed by theme.nix and templates are disabled.
      customPalettes.Catppuccin = {
        version = 2;
        base = "Catppuccin";
        dark = paletteFor "dark";
        light = paletteFor "light";
      };

      # Rendered to ~/.config/noctalia/config.toml. `theme-switch` calls
      # `noctalia msg theme-mode-set`, which persists `[theme].mode` into
      # `settings.toml` at runtime — so never point that file at /dev/null: the
      # mode toggle would have nowhere to write and the two would disagree about
      # the current mode. If the shell rewrites config.toml in place, the next
      # home-manager activation restores the declarative copy.
      settings = lib.recursiveUpdate baseSettings cfg.extraSettings;
    };

    systemd.user.services.noctalia.Service.TimeoutStopSec = 10;

    wayland.windowManager.hyprland.settings.layer_rule = [
      {
        name = "noctalia-notification-no-anim";
        match = {
          namespace = "^noctalia-(notification|panel)$";
        };
        no_anim = true;
      }
      {
        name = "noctalia-notification-blur";
        match = {
          namespace = "^noctalia-(notification|panel)$";
        };
        ignore_alpha = 0.5;
        blur = true;
        blur_popups = true;
      }
    ];
  };
}
