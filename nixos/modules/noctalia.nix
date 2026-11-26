# Noctalia v5.6.0 — the single Wayland shell: bar, panels, notifications, OSD,
# lock screen, clipboard history, launcher, wallpaper.
#
# Colour authority stays with `theme-switch` (nixos/modules/theme.nix): Noctalia
# paints its own surfaces from the CatppuccinDotfiles palette below and is
# explicitly forbidden from writing GTK/dconf/Alacritty/Hyprland state
# (`sync_color_scheme = false`, both template catalogues switched off), so the
# two pipelines cannot fight over the same files.
#
# Every key here is validated by `noctalia config validate` at build time
# (`checkConfig`), so a key that does not exist in 5.6.0 fails the build instead
# of silently doing nothing. 5.6.0 predates `color-picker` and
# `media.circular_album_art`: do not add them.
{
  config,
  pkgs,
  lib,
  compName,
  osConfig,
  ...
}: let
  isDesk = builtins.elem compName ["arch" "office"];

  # Catppuccin hex without the leading '#': Mocha for dark, Latte for light.
  # Kept byte-identical with nixos/modules/theme.nix so the shell and the rest of
  # the session render the same palette.
  palettes = {
    dark = {
      rosewater = "f5e0dc";
      flamingo = "f2cdcd";
      pink = "f5c2e7";
      mauve = "cba6f7";
      red = "f38ba8";
      maroon = "eba0ac";
      peach = "fab387";
      yellow = "f9e2af";
      green = "a6e3a1";
      teal = "94e2d5";
      sky = "89dceb";
      sapphire = "74c7ec";
      blue = "89b4fa";
      lavender = "b4befe";
      text = "cdd6f4";
      subtext1 = "bac2de";
      subtext0 = "a6adc8";
      overlay2 = "9399b2";
      overlay1 = "7f849c";
      overlay0 = "6c7086";
      surface2 = "585b70";
      surface1 = "45475a";
      surface0 = "313244";
      base = "1e1e2e";
      mantle = "181825";
      crust = "11111b";
    };
    light = {
      rosewater = "dc8a78";
      flamingo = "dd7878";
      pink = "ea76cb";
      mauve = "8839ef";
      red = "d20f39";
      maroon = "e64553";
      peach = "fe640b";
      yellow = "df8e1d";
      green = "40a02b";
      teal = "179299";
      sky = "04a5e5";
      sapphire = "209fb5";
      blue = "1e66f5";
      lavender = "7287fd";
      text = "4c4f69";
      subtext1 = "5c5f77";
      subtext0 = "6c6f85";
      overlay2 = "7c7f93";
      overlay1 = "8c8fa1";
      overlay0 = "9ca0b0";
      surface2 = "acb0be";
      surface1 = "bcc0cc";
      surface0 = "ccd0da";
      base = "eff1f5";
      mantle = "e6e9ef";
      crust = "dce0e8";
    };
  };

  # Noctalia's roles are Material-style names; each points at the Catppuccin
  # colour that plays that part. One mapping for both flavours, so dark and light
  # cannot drift apart.
  roleColours = {
    primary = "mauve";
    on_primary = "crust";
    secondary = "peach";
    on_secondary = "crust";
    tertiary = "teal";
    on_tertiary = "crust";
    error = "red";
    on_error = "crust";
    surface = "base";
    on_surface = "text";
    surface_container = "surface0";
    on_surface_variant = "subtext0";
    outline_variant = "surface2";
    shadow = "crust";
    hover = "teal";
    on_hover = "crust";
  };

  hex = mode: colour: "#${palettes.${mode}.${colour}}";

  paletteMode = mode: let
    c = hex mode;
  in
    (lib.mapAttrs (_role: colour: c colour) roleColours)
    // {
      # `parsePaletteFile` rejects a mode object without a `terminal` block, even
      # though the docs present it as optional. Values are the ones theme.nix
      # renders into alacritty.toml.
      terminal = {
        background = c "base";
        foreground = c "text";
        cursor = c "rosewater";
        cursor_text = c "base";
        selection_bg = c "rosewater";
        selection_fg = c "base";
        normal = {
          black = c "surface1";
          red = c "red";
          green = c "green";
          yellow = c "yellow";
          blue = c "blue";
          magenta = c "pink";
          cyan = c "teal";
          white = c "subtext1";
        };
        bright = {
          black = c "surface2";
          red = c "red";
          green = c "green";
          yellow = c "yellow";
          blue = c "blue";
          magenta = c "pink";
          cyan = c "teal";
          white = c "subtext0";
        };
      };
    };

  palette = {
    version = 2;
    base = "Catppuccin";
    dark = paletteMode "dark";
    light = paletteMode "light";
  };

  settings = {
    shell = {
      font_family = "JetBrainsMono Nerd Font";
      clipboard_enabled = true;
      # Replaces lxqt-policykit-agent; the old agent must be gone or the two race
      # for org.freedesktop.PolicyKit1 and the loser never prompts.
      polkit_agent = true;
      setup_wizard_enabled = false;
      telemetry_enabled = false;
      external_ip_enabled = false;
      screen_time_enabled = false;
    };

    storage.key_source = "secret-service";

    theme = {
      mode = "dark";
      shell_mode = "follow";
      source = "custom";
      custom_palette = "CatppuccinDotfiles";
      # Noctalia writes org.gnome.desktop.interface color-scheme on every theme
      # application unless this is off; theme-switch owns that key.
      sync_color_scheme = false;
      templates = {
        # The built-in templates edit app configs (Alacritty import, gtk.css,
        # kdeglobals, hyprland.lua) and several write dconf. All of that is
        # theme-switch's job here.
        enable_builtin_templates = false;
        enable_community_templates = false;
        builtin_ids = [];
        community_ids = [];
      };
    };

    # Shared sunrise/sunset schedule for night light and theme-auto. Coordinates
    # instead of geocoding: no network round-trip at shell start.
    location = {
      auto_locate = false;
      latitude = 40.7128;
      longitude = -74.006;
    };

    nightlight = {
      enabled = compName != "secu" && compName != "arch";
      temperature_day = 6500;
      temperature_night = 3500;
    };

    weather = {
      enabled = true;
      refresh_minutes = 30;
      unit = "imperial";
    };

    lockscreen = {
      enabled = true;
      # Locking stays manual (CTRL+ALT+L): no idle timer, no lock-on-suspend.
      lock_before_suspend = false;
      dnd = false;
      grace_period_seconds = 0;
      blurred_desktop = false;
    };

    # The image itself is pushed by theme-switch (wallpaper-path asset); only the
    # surface is enabled here.
    wallpaper.enabled = true;

    dock.enabled = false;

    notification = {
      enable_daemon = true;
      position = "top_right";
      # "top" (the default) sits below fullscreen windows, so a toast during a
      # fullscreen game/video is invisible; "overlay" keeps them on top.
      layer = "overlay";
      # Two outputs: put the toast stack on the monitor holding keyboard focus,
      # which is what dunst's follow = keyboard did.
      follow_focused_output = true;
      width = 360;
      keep_dismissed_in_history = true;
      group_by_app = true;
      history_retention_hours = 0;
      # First matching filter wins. Never put `allowed_urgencies` on a catch-all:
      # resolveNotificationFilter() does not fall through on an urgency mismatch,
      # it suppresses with fullySuppress = true, which silently drops every
      # low/normal notification even with DND off. Also note play_sound defaults
      # to true per filter.
      filter_order = ["base_station_connect"];
      # Base-station pairing popups are noise: no toast, no history entry.
      filter.base_station_connect = {
        enabled = true;
        match = "blueman";
        match_content = "^LHB-";
        show_toast = false;
        save_history = false;
        play_sound = false;
      };
    };

    osd = {
      position = "top_center";
      hide_delay_ms = 1400;
    };

    plugins = {
      enabled = [
        "john/deskflow"
        "john/voxtype"
        "john/dotfiles-bar"
      ];
      auto_update = "none";
      source = [
        {
          name = "dotfiles";
          kind = "path";
          location = "${../../noctalia-plugins}";
          enabled = true;
        }
      ];
    };

    bar.default = {
      position = "top";
      enabled = true;
      thickness = 38;
      background_opacity = 0.88;
      radius = 12;
      margin_ends = 12;
      margin_edge = 0;
      padding = 10;
      widget_spacing = 6;
      capsule = true;
      capsule_fill = "surface_container";
      capsule_radius = 8.0;

      start =
        ["workspaces" "newworkspace"]
        ++ (lib.optionals (osConfig.hardware.bluetooth.enable or false) ["bluetooth"])
        ++ ["active_window"];

      center = ["media_custom"];

      end =
        ["privacy" "screenrec"]
        ++ (lib.optionals isDesk ["ipad"])
        ++ ["tailscale"]
        ++ (lib.optionals isDesk ["deskflow"])
        ++ [
          "temporal"
          "voxtype"
          "group:hardware"
          "group:clock"
          "updates"
        ]
        ++ (lib.optionals (compName == "arch") ["thermostat"])
        ++ [
          "vast"
          "weather"
          "theme_toggle"
          "battery"
          "autoclicker"
          "tray"
          "volume"
          "notifications"
          "control-center"
        ];

      capsule_group = [
        {
          id = "hardware";
          members = ["hw_cpu" "hw_ram" "hw_temp"];
          accordion = true;
          accordion_direction = "start";
        }
        {
          id = "clock";
          members = ["clock" "clock_date"];
          accordion = true;
          accordion_direction = "start";
        }
      ];
    };

    widget = {
      workspaces = {
        style = "regular";
        # Every workspace in nixos/home.nix carries a `default_name`, so the name
        # is what identifies a workspace on the bar.
        label_source = "name";
        max_label_chars = 8;
        focused_output_only = true;
      };

      newworkspace = {
        type = "custom_button";
        glyph = "plus";
        tooltip = "New temporary workspace";
        actions.left = ''exec fish -c 'set ID (math (date +%s) % 9000 + 1000); hyprctl dispatch "hl.dsp.focus({workspace="$ID"})"' '';
      };

      bluetooth.show_label = false;

      active_window = {
        max_length = 260;
        display = "icon_and_text";
      };

      media_custom.type = "john/dotfiles-bar:media";

      privacy.hide_inactive = true;

      screenrec.type = "john/dotfiles-bar:screenrec";

      ipad.type = "john/dotfiles-bar:ipad";

      tailscale.type = "john/dotfiles-bar:tailscale";

      deskflow.type = "john/deskflow:bar";

      temporal.type = "john/dotfiles-bar:temporal";

      voxtype.type = "john/voxtype:bar";

      hw_cpu = {
        type = "sysmon";
        stat = "cpu_usage";
        actions.left = "exec toggle-btop";
      };

      hw_ram = {
        type = "sysmon";
        stat = "ram_used";
        actions.left = "exec toggle-btop";
      };

      hw_temp = {
        type = "sysmon";
        stat = "cpu_temp";
        actions.left = "exec toggle-btop";
      };

      clock = {
        format = "{:%H:%M:%S}";
        actions.left = "panel-toggle control-center calendar";
        actions.right = "exec copy-date";
        actions.middle = "exec toggle-calendar";
      };

      clock_date = {
        type = "clock";
        format = "{:%A, %e %B %Y}";
        actions.right = "exec copy-date";
      };

      updates.type = "john/dotfiles-bar:updates";

      thermostat.type = "john/dotfiles-bar:thermostat";

      vast.type = "john/dotfiles-bar:vast";

      weather = {
        type = "weather";
        show_condition = true;
        show_temperature = true;
        actions.right = "exec toggle-weather";
      };

      theme_toggle = {
        type = "theme_mode";
        actions.left = "exec theme-switch toggle";
      };

      battery.hide_when_full = false;

      autoclicker.type = "john/dotfiles-bar:autoclicker";

      tray.hide_passive = true;

      volume = {
        device = "output";
        actions.left = "exec fish ~/.config/polybar/scripts/sinks.fish scarlett";
        actions.middle = "exec fish ~/.config/polybar/scripts/sinks.fish bluetooth";
        actions.right = "panel-toggle control-center audio";
      };

      notifications.hide_when_no_unread = false;
    };
  };
in {
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    checkConfig = true;
    customPalettes.CatppuccinDotfiles = palette;
    inherit settings;
  };

  # Plugins resolve helper binaries (media-player, tailscale-status,
  # nix-update-status, ...) through `runAsync`/`runStream`, which inherit this
  # unit's environment; the default user-unit PATH can miss the system profile.
  systemd.user.services.noctalia = lib.mkIf config.programs.noctalia.systemd.enable {
    Service = {
      # sd-switch blocks home-manager activation on a wedged shell otherwise.
      TimeoutStopSec = 10;
      Environment = ["PATH=/run/current-system/sw/bin:/etc/profiles/per-user/john/bin"];
    };
  };
}
