# System-wide light/dark theme.
#
# `theme-switch dark|light|toggle|refresh|status` fills
# `~/.local/state/theme/current/` with the files below and records the mode in
# `~/.local/state/theme/mode`. Nothing here is applied at build time: the module
# renders both palettes into `theme-assets/{dark,light}/<file>` and every app is
# pointed at the runtime copy through an absolute out-of-store link.
#
# To theme a new app:
#   1. add a file to `render` below (use @name@ placeholders for palette colours);
#   2. point the app at `${stateDir}/current/<file>` with
#      `config.lib.file.mkOutOfStoreSymlink "${stateDir}/current/<file>"`
#      (absolute string, never a ../ path — Nix would copy that into the store);
#   3. add the app's reload command to `theme-switch`'s `apply`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stateDir = "${config.xdg.stateHome}/theme";

  # Catppuccin, hex without the leading '#'. Latte for light, Mocha for dark.
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

  wallpapers = {
    dark = "${config.home.homeDirectory}/backgrounds/luna_1.png";
    light = pkgs.fetchurl {
      name = "wallpaper-light.jpg";
      url = "https://images.2143.me/share/8VI7gJvTR9bwcU_CkJP4HyVIkXRYM_JNsgJGiJpXgRMlmsbTejlQXMu_aoD9PxCa_bI";
      hash = "sha256-2llOeOQxrdOz7c3miNMuH3hW+1pQt/a11Ek3wnBd0BI=";
    };
  };

  # @name@ -> hex; writable as "#@name@" where a '#' is needed.
  subst = p: tmpl:
    lib.replaceStrings
    (map (n: "@${n}@") (lib.attrNames p))
    (map (n: p.${n}) (lib.attrNames p))
    tmpl;

  # Upstream catppuccin/alacritty mapping.
  alacrittyToml = ''
    [colors.primary]
    background = "#@base@"
    foreground = "#@text@"
    dim_foreground = "#@overlay1@"
    bright_foreground = "#@text@"

    [colors.cursor]
    text = "#@base@"
    cursor = "#@rosewater@"

    [colors.vi_mode_cursor]
    text = "#@base@"
    cursor = "#@lavender@"

    [colors.search.matches]
    foreground = "#@base@"
    background = "#@subtext0@"

    [colors.search.focused_match]
    foreground = "#@base@"
    background = "#@green@"

    [colors.footer_bar]
    foreground = "#@base@"
    background = "#@subtext0@"

    [colors.hints.start]
    foreground = "#@base@"
    background = "#@yellow@"

    [colors.hints.end]
    foreground = "#@base@"
    background = "#@subtext0@"

    [colors.selection]
    text = "#@base@"
    background = "#@rosewater@"

    [colors.normal]
    black = "#@surface1@"
    red = "#@red@"
    green = "#@green@"
    yellow = "#@yellow@"
    blue = "#@blue@"
    magenta = "#@pink@"
    cyan = "#@teal@"
    white = "#@subtext1@"

    [colors.bright]
    black = "#@surface2@"
    red = "#@red@"
    green = "#@green@"
    yellow = "#@yellow@"
    blue = "#@blue@"
    magenta = "#@pink@"
    cyan = "#@teal@"
    white = "#@subtext0@"

    [[colors.indexed_colors]]
    index = 16
    color = "#@peach@"

    [[colors.indexed_colors]]
    index = 17
    color = "#@rosewater@"
  '';

  wofiCss = ''
    window { background-color: #@base@; border: 2px solid #@mauve@; border-radius: 8px; font-family: "JetBrainsMono Nerd Font"; }
    #input { background-color: #@surface0@; color: #@text@; border: none; margin: 6px; }
    #inner-box, #outer-box, #scroll { background-color: transparent; }
    #entry { padding: 4px 8px; }
    #entry:selected { background-color: #@surface1@; }
    #text { color: #@text@; }
  '';

  fuzzelIni = ''
    [colors]
    background=@base@ee
    text=@text@ff
    message=@subtext0@ff
    prompt=@subtext0@ff
    placeholder=@overlay1@ff
    input=@text@ff
    match=@mauve@ff
    selection=@surface1@ff
    selection-text=@text@ff
    selection-match=@mauve@ff
    counter=@overlay1@ff
    border=@mauve@ff
  '';

  dunstConf = ''
    [global]
        frame_color = "#@mauve@"

    [urgency_low]
        background = "#@mantle@"
        foreground = "#@subtext0@"

    [urgency_normal]
        background = "#@base@"
        foreground = "#@text@"

    [urgency_critical]
        background = "#@peach@"
        foreground = "#@base@"
        frame_color = "#@peach@"
  '';

  # Read by hyprlock via `source`, and by the compositor through extraConfig.
  hyprlockConf = ''
    $lock_bg = rgb(@base@)
    $lock_outer = rgb(@mauve@)
    $lock_inner = rgb(@surface0@)
    $lock_font = rgb(@text@)
    $lock_check = rgb(@peach@)
    $lock_fail = rgb(@red@)
  '';

  hyprlandLua = ''
    -- Written by theme-switch from nixos/modules/theme.nix; dofile'd by hyprland.lua.
    return {
      general = {
        col = {
          active_border = { colors = { "rgba(@teal@ee)", "rgba(@green@ee)" }, angle = 45 },
          inactive_border = "rgba(@overlay0@aa)",
        },
      },
    }
  '';

  render = mode: let
    p = palettes.${mode};
  in {
    "alacritty.toml" = subst p alacrittyToml;
    "wofi.css" = subst p wofiCss;
    "fuzzel.ini" = subst p fuzzelIni;
    "dunst.conf" = subst p dunstConf;
    "hyprlock.conf" = subst p hyprlockConf;
    "hyprland.lua" = subst p hyprlandLua;
    "waybar.css" = lib.concatMapStrings (n: "@define-color ${n} #${p.${n}};\n") (lib.attrNames p);
    "eww.scss" = lib.concatMapStrings (n: "\$${n}: #${p.${n}};\n") (lib.attrNames p);
    "tmux.conf" = "set -g @catppuccin_flavor ${
      if mode == "light"
      then "latte"
      else "mocha"
    }\n";
    "hyprpaper.conf" = ''
      splash = false
      wallpaper {
          monitor =
          path = ${wallpapers.${mode}}
          fit_mode = cover
      }
    '';
  };

  modeDir = mode:
    pkgs.linkFarm "theme-${mode}" (lib.mapAttrsToList (name: text: {
        inherit name;
        path = pkgs.writeText "theme-${mode}-${name}" text;
      })
      (render mode));

  assets = pkgs.linkFarm "theme-assets" [
    {
      name = "dark";
      path = modeDir "dark";
    }
    {
      name = "light";
      path = modeDir "light";
    }
  ];

  theme-switch = pkgs.writeShellApplication {
    name = "theme-switch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux # flock
      pkgs.dconf
      pkgs.jq
      pkgs.gawk
      pkgs.systemd
      pkgs.tmux
      config.wayland.windowManager.hyprland.finalPackage # hyprctl
      config.programs.eww.package
      config.services.dunst.package # dunstctl
    ];
    runtimeEnv = {
      THEME_ASSETS = "${assets}";
    };
    text = builtins.readFile ../theme-switch.sh;
  };
in {
  home.packages = [
    theme-switch
    # GTK3 theme pair written to gtk-3.0/settings.ini by theme-switch.
    pkgs.adw-gtk3
    # BreezeLight/BreezeDark .colors schemes, picked up through the portal hint.
    pkgs.kdePackages.breeze
  ];

  # Qt apps resolve their colours from the settings portal (theme-switch writes
  # org.gnome.desktop.interface color-scheme, xdg-desktop-portal-gtk serves it).
  systemd.user.sessionVariables.QT_QPA_PLATFORMTHEME = "xdgdesktopportal";

  # Re-apply the saved mode on every rebuild: the runtime files are not store
  # links, so without this a palette edit would wait for the next toggle.
  home.activation.themeRefresh = lib.hm.dag.entryBetween ["onFilesChange"] ["linkGeneration"] ''
    run ${theme-switch}/bin/theme-switch refresh
  '';

  xdg.configFile = {
    "wofi/style.css".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/current/wofi.css";
    "fuzzel/fuzzel.ini".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/current/fuzzel.ini";
    "eww/theme.scss".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/current/eww.scss";
    "dunst/dunstrc.d/50-theme.conf".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/current/dunst.conf";
  };

  # home-manager's services.hyprpaper writes a static ~/.config/hypr/hyprpaper.conf,
  # so the daemon is run here with -c pointing at the theme state instead.
  systemd.user.services.hyprpaper = {
    Unit = {
      Description = "hyprpaper wallpaper daemon (theme-aware)";
      PartOf = [config.wayland.systemd.target];
      After = [config.wayland.systemd.target];
    };
    Service = {
      ExecStart = "${pkgs.hyprpaper}/bin/hyprpaper -c ${stateDir}/current/hyprpaper.conf";
      Restart = "on-failure";
    };
    Install.WantedBy = [config.wayland.systemd.target];
  };

  # Border colours cannot come from `settings` (they are static), and hyprctl
  # reload re-runs this file, so the colours survive a reload.
  wayland.windowManager.hyprland.extraConfig = ''
    -- theme-switch: border colours live in ~/.local/state/theme/current/hyprland.lua
    do
      local ok, theme = pcall(dofile, "${stateDir}/current/hyprland.lua")
      if ok and type(theme) == "table" then hl.config(theme) end
    end
  '';
}
