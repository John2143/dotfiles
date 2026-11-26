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
#                                             suspend-triggered lock path
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
  paletteName = "Catppuccin";

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

  # Rewrites ~/.local/state/noctalia/settings.toml before noctalia starts so it
  # boots directly in the mode recorded by `theme-switch` (solving the first-boot
  # light-mode race) and strips any accidental GUI/CLI drift in settings.toml
  # (including security pins like lockscreen.* or plugins.*) on every restart.
  noctalia-sync-settings = pkgs.writeShellApplication {
    name = "noctalia-sync-settings";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      state_root="''${XDG_STATE_HOME:-${config.xdg.stateHome}}"
      mode_file="$state_root/theme/mode"
      state_dir="$state_root/noctalia"
      settings_file="$state_dir/settings.toml"
      mode="dark"
      if [ -r "$mode_file" ] && [ "$(head -n1 "$mode_file")" = "light" ]; then
        mode="light"
      fi
      install -d -m 0700 "$state_dir"
      tmp="$(mktemp "$state_dir/.settings.toml.XXXXXX")"
      chmod 0600 "$tmp"
      printf '[theme]\nmode = "%s"\n' "$mode" > "$tmp"
      mv -f "$tmp" "$settings_file"
    '';
  };

  # Single ordered list so `filter_order` and `filter` cannot drift.
  # First matching filter wins, so order is load-bearing:
  #   base-stations   LHB-* standby chatter is dropped completely (no toast,
  #                   no history); must come before the catch-all.
  #   ups             nut-ups.nix power/battery alerts bypass DND and stay
  #                   sticky (override_duration = 0).
  #   babysit         babysit skill blocking alerts bypass DND and stay sticky.
  #   silent-default  catch-all last.
  # Never set `allowed_urgencies` on a catch-all filter: in Noctalia 5.6.0,
  # resolveNotificationFilter() does not fall through on urgency mismatch — it
  # sets fullySuppress = true and drops non-matching urgencies even with DND off.
  # Every filter sets play_sound = false because Noctalia's per-filter default
  # is true.
  filterDefs = [
    {
      name = "base-stations";
      enabled = true;
      match = "";
      match_content = "^LHB-";
      show_toast = false;
      save_history = false;
      play_sound = false;
    }
    {
      name = "ups";
      enabled = true;
      match = "";
      match_content = "^UPS$";
      show_toast = true;
      save_history = true;
      play_sound = false;
      bypass_dnd = true;
      override_duration = 0;
    }
    {
      name = "babysit";
      enabled = true;
      match = "";
      match_content = "^BABYSIT:";
      show_toast = true;
      save_history = true;
      play_sound = false;
      bypass_dnd = true;
      override_duration = 0;
    }
    {
      name = "silent-default";
      enabled = true;
      match = "";
      match_content = ".*";
      show_toast = true;
      save_history = true;
      play_sound = false;
    }
  ];

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
      # Default fallback mode; `noctalia-sync-settings` seeds settings.toml from
      # `~/.local/state/theme/mode` on startup and `theme-switch` updates it
      # live with `noctalia msg theme-mode-set`.
      mode = "dark";
      source = "custom";
      custom_palette = paletteName;
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
      source = [];
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
      layer = "overlay";
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

      filter_order = map (f: f.name) filterDefs;
      filter = builtins.listToAttrs (map (f: lib.nameValuePair f.name (removeAttrs f ["name"])) filterDefs);
    };
  };
in {
  imports = [./theme.nix];

  options.services.noctalia-notifications = {
    enable = lib.mkEnableOption "Noctalia as the Wayland notification daemon (toasts + Control Center notifications tab only)";

    storageKeyFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/.+");
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
      description = "Delete stored notification history older than this many hours; 0 keeps notification bodies (potentially including OTPs/reset links) indefinitely up to Noctalia's 100-entry hard cap.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.dunst.enable;
        message = "services.noctalia-notifications cannot be enabled while services.dunst.enable is true: only one process may own org.freedesktop.Notifications on Wayland.";
      }
      {
        assertion = !config.services.swaync.enable;
        message = "services.noctalia-notifications cannot be enabled alongside services.swaync (both claim org.freedesktop.Notifications)";
      }
    ];

    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      # checkConfig defaults to true upstream (validates TOML syntax at build time).

      # Palette JSON format 2: role names as keys, plus `base` so the picker
      # groups custom and built-in Catppuccin together. No `terminal` block —
      # alacritty is themed by theme.nix and templates are disabled.
      customPalettes.${paletteName} = {
        version = 2;
        base = paletteName;
        dark = paletteFor "dark";
        light = paletteFor "light";
      };

      # Rendered to ~/.config/noctalia/config.toml. Assigned directly (never via
      # lib.mkDefault, which would drop the whole attrset under types.oneOf) so
      # additional keys merge cleanly while overriding pinned security keys
      # requires an explicit lib.mkForce.
      # `theme-switch` calls `noctalia msg theme-mode-set`, persisting `[theme].mode`
      # into settings.toml at runtime; `noctalia-sync-settings` resets settings.toml
      # to just `[theme].mode` on every daemon start.
      settings = baseSettings;
    };

    systemd.user.services.noctalia.Service = {
      ExecStartPre = ["${lib.getExe noctalia-sync-settings}"];
      TimeoutStopSec = 10;
    };

    wayland.windowManager.hyprland.settings.layer_rule = [
      {
        name = "noctalia-notification";
        match.namespace = "^noctalia-(notification|panel)$";
        no_anim = true;
        blur = true;
        blur_popups = true;
        ignore_alpha = 0.5;
      }
    ];
  };
}
