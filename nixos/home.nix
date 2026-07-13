{
  config,
  inputs,
  pkgs,
  lib,
  pkgs-stable,
  compName,
  ...
}: let
  primaryPackages = with pkgs; [
    # fonts
    # https://github.com/NixOS/nixpkgs/blob/master/pkgs/data/fonts/nerdfonts/shas.nix
    playerctl
    nerd-fonts.jetbrains-mono # font
    nerd-fonts.roboto-mono # font also, "FiraCode" "DejaVuSansMono" "FiraMono"

    # cli
    ffmpeg

    #@ embedded programming
    #@ gcc-arm-embedded # arm compiler
    #@ openocd # open debugger
    #@ probe-rs # rust <-> stm32
    #@ stlink # stm32 programmer
    #@ stm32cubemx # stm32 ide

    # desktop tools (bars, clipbaords, notifications, etc)
    pulseaudio # pactl (audio)
    wofi # "start menu" / program browser
    kdePackages.dolphin # file browser
    thunar # file browser 2
    wl-clipboard # copy-paste via cli
    jetbrains-mono # font
    alacritty # terminal
    pwvucontrol # volume control
    pkgs-stable.pamixer # volume control
    cliphist # clipboard history
    wl-clipboard-x11 # clipboard compatibility for some apps
    libnotify # notifications cli
    #swaynotificationcenter # DISABLED: gitlab.gnome.org 503 for blueprint-compiler — re-enable when upstream recovers
    fuzzel # dmenu replacement for dunst actions
    gammastep # redshift / f.lux / night light
    #spotifyd # play to spotify device if needed

    hyprlock # screen locker

    # desktop programs (programs you can open)
    firefox # browser
    # floorp # browser
    gthumb # image viewer
    #vesktop # discord
    #discordo # discord
    #equibop # discord
    # discord-canary # discord
    #@ krita
    #@ kdePackages.kdenlive # video editor
    # kdeconnect # phone sync (now in main settings)
    #v4l-utils # video inputs for linux (obs)
    vlc # video player
    wev # wayland event viewer

    # Other / unsorted
    appimage-run
    #@ betaflight-configurator
    lshw
    #@ darktable
    hyprpaper
    # kubernetes-helm

    gparted

    pavucontrol # audio
    qpwgraph

    #plasma5Packages.kdeconnect-kde
    kdePackages.ark
    kdePackages.gwenview
    #warp-terminal # agent terminal

    #wineWowPackages.stable
    ungoogled-chromium # browser backup

    xlsclients
  ];

  # not needed for minimal stuff not on security cam
  extensionPackages = with pkgs; [
    discord # discord
    wineWow64Packages.stable
    #wineWow64Packages.waylandFull
    #wine64

    winetricks
    slurp # use mouse to get a point on screen
    grim # minimal screenshot program
    swappy # screenshot editor
    pkgs-stable.wf-recorder # screen recording
    pkgs-stable.normcap # OCR screen recognition
    hyprpicker # color picker

    temurin-jre-bin-21 # java

    # both these depend on deno, which takes forever to compile on non-gui hosts
    # also clang ICE in rusty-v8 on unstable, so pull from stable
    pkgs-stable.yt-dlp # youtube-dl
    pkgs-stable.mpv # video player
    nicotine-plus # soulseek client

    #mullvad-vpn # vpn  # DISABLED: gitlab.gnome.org 503 for gtk-doc dependency
    #plex-desktop # plex
    #rustdesk
    #spotify # music
    (prismlauncher.override {
      jdks = [
        temurin-bin-21
        temurin-bin-8
        temurin-bin-17
      ];
    })
    r2modman # game modding
    rusty-path-of-building # Path of Exile build planner
    #bitwarden-desktop # password manager
    kind
    mongodb-compass
    doctl # DigitalOcean CLI
    hcloud # Hetzner CLI
    rclone # S3/B2/RustFS sync
    velero # K8s backup/migration
    e1s
    dbeaver-bin # db browser

    # code-cursor # agent terminal: I swapped to omp
    obs-studio # streaming
    easyeffects
    evremap
    imagemagick
    godot # game engine / gdscript
    gdtoolkit_4 # gdscript linter/formatter
    protonup-qt

    openrct2
    #hyprcap # video screenshot tool for hyprland

    #nvtop # unfree
  ];

  # If we are on office computer, then also add the following:
  optionalPackagesOffice = with pkgs; [
    amdgpu_top # gpu stats
    kicad # PCB Hardware Layout
    blender
    openscad # parametric 3D CAD
    #wine-wayland # wine
  ];

  # On my other computer, I want to install these
  optionalPackagesUpstairs = with pkgs; [
    #prusa-slicer # 3d printer slicer
    monero-cli
    monero-gui
    cryptsetup
    woeusb-ng

    #wineWowPackages.stable
    #winetricks
    #wineWowPackages.waylandFull
  ];
in {
  imports = [
    ./home-cli.nix
    ./modules/waybar.nix
    ./modules/eww.nix
    #./modules/swaync.nix  # DISABLED: gitlab.gnome.org 503 — re-enable when upstream recovers
  ];

  home.pointerCursor = {
    enable = true;
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
  };

  services.udiskie = {
    enable = true;
    settings.program_options = {};
  };

  # Check hostname to determine what to install
  home.packages =
    if compName == "office"
    then primaryPackages ++ optionalPackagesOffice ++ extensionPackages
    else if compName == "arch"
    then primaryPackages ++ optionalPackagesUpstairs ++ extensionPackages
    else primaryPackages;


  wayland.windowManager.hyprland = let
    mkLua = lib.generators.mkLuaInline;
  in {
    enable = true;
    package = pkgs.hyprland;
    xwayland.enable = true;
    systemd.enable = true;
    configType = "lua";

    settings = {
      # ---- Locals (Lua variables) ----
      terminal = { _var = "alacritty"; };
      fileManager = { _var = "dolphin"; };
      menu = { _var = ''fish -c "mkdir -p ~/drun_logs/ ; wofi --show drun > ~/drun_logs/(date)"''; };
      mainMod = { _var = "SUPER"; };
      MONITOR_LEFT = { _var = if compName == "office" then "DP-2" else "DP-3"; };
      MONITOR_RIGHT = { _var = if compName == "office" then "DP-1" else "HDMI-A-2"; };

      # ---- Monitors ----
      monitor = [
        { output = mkLua "MONITOR_LEFT"; mode = "highrr"; position = "0x0"; scale = 1; bitdepth = 8; }
        { output = mkLua "MONITOR_RIGHT"; mode = "highrr"; position = "2560x0"; scale = 1; }
      ];

      # ---- Environment ----
      env = [
        { _args = ["XCURSOR_SIZE" "24"]; }
        { _args = ["XCURSOR_THEME" "Adwaita"]; }
      ];

      # ---- Curves ----
      curve = [
        { _args = ["myBezier" { type = "bezier"; points = [ [0.05 0.9] [0.1 1.05] ]; }]; }
      ];

      # ---- Animations ----
      animation = [
        { _args = [{ leaf = "windows"; enabled = true; speed = 7; bezier = "myBezier"; }]; }
        { _args = [{ leaf = "windowsOut"; enabled = true; speed = 7; bezier = "default"; style = "popin 80%"; }]; }
        { _args = [{ leaf = "border"; enabled = true; speed = 10; bezier = "default"; }]; }
        { _args = [{ leaf = "borderangle"; enabled = true; speed = 8; bezier = "default"; }]; }
        { _args = [{ leaf = "fade"; enabled = true; speed = 7; bezier = "default"; }]; }
        { _args = [{ leaf = "workspaces"; enabled = true; speed = 6; bezier = "default"; }]; }
      ];

      # ---- Main config (hl.config) ----
      config = {
        debug = {
          disable_logs = false;
        };

        general = {
          gaps_in = 2;
          gaps_out = 5;
          border_size = 2;
          col = {
            active_border = {
              colors = ["rgba(33ccffee)" "rgba(00ff99ee)"];
              angle = 45;
            };
            inactive_border = "rgba(595959aa)";
          };
          layout = "dwindle";
          allow_tearing = true;
        } // (if compName == "secu" then { gaps_in = 0; gaps_out = 0; } else {});

        decoration = {
          rounding = 3;
          blur = {
            enabled = true;
            size = 3;
            passes = 1;
          };
        };

        dwindle = {
          preserve_split = true;
        };

        misc = {
          disable_splash_rendering = true;
          force_default_wallpaper = 0;
        };

        input = {
          kb_layout = "us";
          kb_variant = "";
          kb_model = "";
          kb_options = "ctrl:nocaps,fkeys:basic_13-24";
          kb_rules = "";
          follow_mouse = 0;
          touchpad = {
            natural_scroll = false;
          };
          sensitivity = -0.2;
          accel_profile = "flat";
        };
        layerrule = [
          "blur,waybar"
          "ignorezero,waybar"
        ];
      };

      # ---- Workspace rules ----
      workspace_rule = [
        { workspace = "name:A1"; monitor = mkLua "MONITOR_LEFT"; default = true; }
        { workspace = "name:A2"; monitor = mkLua "MONITOR_LEFT"; default = true; }
        { workspace = "name:A3"; monitor = mkLua "MONITOR_LEFT"; default = true; }
        { workspace = "name:A4"; monitor = mkLua "MONITOR_LEFT"; default = true; }
        { workspace = "name:A5"; monitor = mkLua "MONITOR_LEFT"; default = true; }
        { workspace = "name:B1"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:B2"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:B3"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:B4"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:B5"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:ts"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:disc"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:steam"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:obsidian"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
        { workspace = "name:spotify"; monitor = mkLua "MONITOR_RIGHT"; default = true; }
      ];
      # ---- Window rules ----
      window_rule = [
        # steam
        { match = { class = "^[Ss]team$"; }; workspace = "name:steam"; no_initial_focus = true; }
        # TeamSpeak + qpwgraph
        { match = { class = "TeamSpeak 3"; }; workspace = "name:ts"; }
        { match = { class = "org.rncbc.qpwgraph"; }; workspace = "name:ts"; }
        # discord / vesktop
        { match = { class = "^[Vv]esktop$"; }; workspace = "name:disc"; no_initial_focus = true; }
        { match = { class = "^[Dd]iscord$"; }; workspace = "name:disc"; no_initial_focus = true; }
        # obsidian
        { match = { class = "^[Oo]bsidian$"; }; workspace = "name:obsidian"; no_initial_focus = true; }
        # spotify
        { match = { class = "^[Ss]potify$"; }; workspace = "name:spotify"; no_initial_focus = true; }
        # xwaylandvideobridge (hide)
        { match = { class = "^xwaylandvideobridge$"; }; opacity = "0.0 override 0.0 override"; no_anim = true; no_focus = true; no_initial_focus = true; }
        # awakened-poe-trade (hide)
        { match = { class = "^awakened-poe-trade$"; }; no_anim = true; no_focus = true; no_blur = true; no_initial_focus = true; }
        # polkit auth dialogs
        { match = { title = "^(Authentication required|Authentication Required).*"; }; float = true; center = true; }
      ];
      # ---- Binds ----
      bind = [
        # App launchers
        { _args = [(mkLua ''mainMod .. " + Return"'') (mkLua "hl.dsp.exec_cmd(terminal)")]; }
        { _args = [(mkLua ''mainMod .. " + Space"'') (mkLua "hl.dsp.exec_cmd(menu)")]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + Space"'') (mkLua "hl.dsp.exec_cmd(fileManager)")]; }
        { _args = [(mkLua ''mainMod .. " + E"'') (mkLua "hl.dsp.exec_cmd(fileManager)")]; }
        { _args = [(mkLua ''mainMod .. " + Q"'') (mkLua "hl.dsp.window.close()")]; }

        # bspwm-like
        { _args = [(mkLua ''mainMod .. " + D"'') (mkLua "hl.dsp.window.pseudo()")]; }
        { _args = [(mkLua ''mainMod .. " + F"'') (mkLua "hl.dsp.window.fullscreen()")]; }
        { _args = [(mkLua ''mainMod .. " + S"'') (mkLua ''hl.dsp.window.float({ action = "toggle" })'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + S"'') (mkLua ''hl.dsp.layout("togglesplit")'')]; }

        # Clipboard
        { _args = ["SUPER + V" (mkLua ''hl.dsp.exec_cmd([[cliphist list | wofi --dmenu | cliphist decode | wl-copy]])'')]; }

        # Screenshots
        { _args = ["CTRL + SHIFT + 1" (mkLua ''hl.dsp.exec_cmd([[fish -c 'grim -g (slurp) - | wl-copy']])'')]; }
        { _args = ["CTRL + SHIFT + ALT + 1" (mkLua ''hl.dsp.exec_cmd([[fish -c 'grim -g (slurp) - | wl-copy']])'')]; }
        { _args = ["CTRL + SHIFT + 2" (mkLua ''hl.dsp.exec_cmd([[fish -c 'set loc (screenshot_location); grim -g (slurp) - | swappy -f - -o "$loc"; juush $loc']])'')]; }
        { _args = ["CTRL + SHIFT + 3" (mkLua ''hl.dsp.exec_cmd([[fish -c 'set loc (screenshot_location); set ll (slurp) ; sleep 1 ; grim -g $ll $loc; juush $loc']])'')]; }
        { _args = ["CTRL + SHIFT + ALT + 4" (mkLua ''hl.dsp.exec_cmd([[fish -c 'set loc (screenshot_location); grim -g (slurp) $loc; juush $loc']])'')]; }
        { _args = ["CTRL + SHIFT + 4" (mkLua ''hl.dsp.exec_cmd([[fish -c 'set loc (screenshot_location); grim -g (slurp) $loc; juush $loc']])'')]; }
        { _args = ["CTRL + SHIFT + 5" (mkLua ''hl.dsp.exec_cmd([[fish -c 'wl-paste > ~/screenshots/clipboard.txt; juush ~/screenshots/clipboard.txt']])'')]; }
        { _args = ["CTRL + SHIFT + 9" (mkLua ''hl.dsp.exec_cmd([[fish -c 'set loc (string replace "png" "mkv" (screenshot_location)); notify-send "Starting recording "(loc); wf-recorder -g (slurp) -f $loc; set -Ux LAST_VID $loc']])'')]; }
        { _args = ["CTRL + SHIFT + 6" (mkLua ''hl.dsp.exec_cmd([[fish -c 'killall -s SIGINT wf-recorder; notify-send "Finished Recording, starting transcode"; ffmpeg -i $LAST_VID -c:v libx264 $LAST_VID.mp4; notify-send "Finished Transcode, starting upload"; juush $LAST_VID.mp4']])'')]; }
        { _args = ["CTRL + SHIFT + 7" (mkLua ''hl.dsp.exec_cmd([[fish -c 'hyprpicker | wl-copy']])'')]; }

        # Move focus (vim keys)
        { _args = [(mkLua ''mainMod .. " + H"'') (mkLua ''hl.dsp.focus({ direction = "left" })'')]; }
        { _args = [(mkLua ''mainMod .. " + J"'') (mkLua ''hl.dsp.focus({ direction = "down" })'')]; }
        { _args = [(mkLua ''mainMod .. " + K"'') (mkLua ''hl.dsp.focus({ direction = "up" })'')]; }
        { _args = [(mkLua ''mainMod .. " + L"'') (mkLua ''hl.dsp.focus({ direction = "right" })'')]; }

        # Workspace switching (left monitor A1-A5)
        { _args = [(mkLua ''mainMod .. " + 1"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_LEFT })) hl.dispatch(hl.dsp.focus({ workspace = "name:A1" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + 2"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_LEFT })) hl.dispatch(hl.dsp.focus({ workspace = "name:A2" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + 3"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_LEFT })) hl.dispatch(hl.dsp.focus({ workspace = "name:A3" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + 4"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_LEFT })) hl.dispatch(hl.dsp.focus({ workspace = "name:A4" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + 5"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_LEFT })) hl.dispatch(hl.dsp.focus({ workspace = "name:A5" })) end'')]; }

        # Workspace switching (right monitor B1-B5, named)
        { _args = [(mkLua ''mainMod .. " + SHIFT + 1"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:B1" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + 2"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:B2" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + 3"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:B3" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + 4"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:B4" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + 5"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:B5" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + Q"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:ts" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + W"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:disc" })) end'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + E"'') (mkLua ''function() hl.dispatch(hl.dsp.focus({ monitor = MONITOR_RIGHT })) hl.dispatch(hl.dsp.focus({ workspace = "name:obsidian" })) end'')]; }

        # Workspace scroll
        { _args = [(mkLua ''mainMod .. " + bracketright"'') (mkLua ''hl.dsp.focus({ workspace = "e-1" })'')]; }
        { _args = [(mkLua ''mainMod .. " + bracketleft"'') (mkLua ''hl.dsp.focus({ workspace = "e+1" })'')]; }

        # Move workspace to monitor
        { _args = [(mkLua ''mainMod .. " + CTRL + bracketright"'') (mkLua ''hl.dsp.exec_cmd("hyprctl dispatch movecurrentworkspacetomonitor r")'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + bracketleft"'') (mkLua ''hl.dsp.exec_cmd("hyprctl dispatch movecurrentworkspacetomonitor l")'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + period"'') (mkLua ''hl.dsp.exec_cmd("hyprctl dispatch movecurrentworkspacetomonitor 0")'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + comma"'') (mkLua ''hl.dsp.exec_cmd("hyprctl dispatch movecurrentworkspacetomonitor 1")'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + slash"'') (mkLua ''hl.dsp.exec_cmd("hyprctl dispatch movecurrentworkspacetomonitor 2")'')]; }

        # Move window to workspace
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 1"'') (mkLua ''hl.dsp.window.move({ workspace = "name:A1" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 2"'') (mkLua ''hl.dsp.window.move({ workspace = "name:A2" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 3"'') (mkLua ''hl.dsp.window.move({ workspace = "name:A3" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 4"'') (mkLua ''hl.dsp.window.move({ workspace = "name:A4" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 5"'') (mkLua ''hl.dsp.window.move({ workspace = "name:A5" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 6"'') (mkLua ''hl.dsp.window.move({ workspace = "name:B1" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 7"'') (mkLua ''hl.dsp.window.move({ workspace = "name:B2" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 8"'') (mkLua ''hl.dsp.window.move({ workspace = "name:B3" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 9"'') (mkLua ''hl.dsp.window.move({ workspace = "name:B4" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + 0"'') (mkLua ''hl.dsp.window.move({ workspace = "name:B5" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + Q"'') (mkLua ''hl.dsp.window.move({ workspace = "name:ts" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + W"'') (mkLua ''hl.dsp.window.move({ workspace = "name:disc" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + SHIFT + E"'') (mkLua ''hl.dsp.window.move({ workspace = "name:obsidian" })'')]; }

        # Sleep / wake / quit
        { _args = ["CTRL + ALT + L" (mkLua ''function() hl.dsp.exec_cmd("hyprlock &") hl.timer(function() hl.dsp.dpms({ action = "disable" }) end, {timeout = 1000, type = "oneshot"}) end'')]; }
        { _args = ["Print" (mkLua ''hl.dsp.dpms({ action = "enable" })'')]; }
        { _args = [(mkLua ''mainMod .. " + SHIFT + M"'') (mkLua "hl.dsp.exit()")]; }

        # Voxtype voice-to-text (push-to-talk on SUPER+A)
        { _args = [(mkLua ''mainMod .. " + A"'') (mkLua ''hl.dsp.exec_cmd([[voxtype record start]])'')]; }
        { _args = [(mkLua ''mainMod .. " + A"'') (mkLua ''hl.dsp.exec_cmd([[voxtype record stop]])'') { release = true; }]; }

        # Media keys
        { _args = ["XF86AudioRaiseVolume" (mkLua ''hl.dsp.exec_cmd([[fish -c "pamixer -i 5"]])'')]; }
        { _args = ["XF86AudioLowerVolume" (mkLua ''hl.dsp.exec_cmd([[fish -c "pamixer -d 5"]])'')]; }
        { _args = [(mkLua ''mainMod .. " + XF86AudioRaiseVolume"'') (mkLua ''hl.dsp.exec_cmd([[fish -c "~/.config/focussed-vol-adjust.sh 0.05+"]])'')]; }
        { _args = [(mkLua ''mainMod .. " + XF86AudioLowerVolume"'') (mkLua ''hl.dsp.exec_cmd([[fish -c "~/.config/focussed-vol-adjust.sh 0.05-"]])'')]; }
        { _args = [(mkLua ''mainMod .. " + XF86AudioMute"'') (mkLua ''hl.dsp.exec_cmd([[fish -c "~/.config/focussed-vol-adjust.sh toggle"]])'')]; }

        # Macro pad F18 group — lights
        { _args = ["F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-lamp")'')]; }
        { _args = ["CTRL + F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-dresser")'')]; }
        { _args = ["ALT + F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-ac")'')]; }
        { _args = ["SUPER + F18" (mkLua ''hl.dsp.exec_cmd("hass-macro light-bedroom")'')]; }

        # Macro pad F19 group — climate
        { _args = ["F19" (mkLua ''hl.dsp.exec_cmd("hass-macro thermostat-toggle")'')]; }
        { _args = ["CTRL + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro thermostat-down")'')]; }
        { _args = ["ALT + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro thermostat-up")'')]; }
        { _args = ["SUPER + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro ac-toggle")'')]; }
        { _args = ["CTRL + ALT + F19" (mkLua ''hl.dsp.exec_cmd("hass-macro fan-toggle")'')]; }

        # Macro pad F20 group — display
        { _args = ["F20" (mkLua ''hl.dsp.dpms({ action = "enable" })'')]; }
        { _args = ["CTRL + F20" (mkLua ''hl.dsp.dpms({ action = "disable" })'')]; }
        # Macro pad F21 group — Home Assistant toggles
        { _args = ["F21" (mkLua ''hl.dsp.exec_cmd("hass-macro dyson-fan")'')]; }
        { _args = ["CTRL + F21" (mkLua ''hl.dsp.exec_cmd("hass-macro desk-light")'')]; }
        #
        # ── Adding a new macropad bind? ──────────────────────────────────
        # 1. Add the keyd mapping in arch-configuration.nix (services.keyd).
        # 2. If it controls Home Assistant, add a `hass-macro` case there too.
        # 3. Add the Hyprland bind here (same F-key + modifier as in keyd).
        #    F-key syntax: "F18" / "CTRL + F18" / "ALT + F18" / "SUPER + F18"
        #    Command syntax: hl.dsp.exec_cmd("hass-macro <name>")
        # ─────────────────────────────────────────────────────────────────

        # TeamSpeak mute: Prior mutes mic, Next mutes sound
        { _args = ["Prior" (mkLua ''hl.dsp.exec_cmd("teamspeak-mute-status --toggle && pkill -RTMIN+10 waybar")'')]; }
        { _args = ["Next" (mkLua ''hl.dsp.exec_cmd("teamspeak-mute-status --toggle-output && pkill -RTMIN+11 waybar")'')]; }
        { _args = ["KP_Subtract" (mkLua ''hl.dsp.pass({ window = "class:^(discord)$" })'')]; }
        { _args = ["XF86AudioPrev" (mkLua ''hl.dsp.pass({ window = "class:^(discord)$" })'')]; }

        # Pass CTRL+ALT+D to awakened-poe-trade
        { _args = ["CTRL + ALT + D" (mkLua ''hl.dsp.pass({ window = "class:^(awakened-poe-trade)$" })'')]; }
        { _args = [(mkLua ''mainMod .. " + CTRL + ALT + D"'') (mkLua "hl.dsp.exec_cmd(terminal)")]; }

        # PoE shortcuts
        { _args = [(mkLua ''mainMod .. " + Z"'') (mkLua ''hl.dsp.exec_cmd([[fish -c 'ydotool key 28:1 28:0; ydotool type "/hideout"; ydotool key 28:1 28:0;']])'')]; }
        { _args = [(mkLua ''mainMod .. " + X"'') (mkLua ''hl.dsp.exec_cmd([[fish -c 'ydotool key 28:1 28:0; ydotool type "/menagerie"; ydotool key 28:1 28:0;']])'')]; }

        # Autoclicker stop hotkey
        { _args = [(mkLua ''mainMod .. " + Escape"'') (mkLua ''hl.dsp.exec_cmd([[fish -c 'stop-autoclicker']])'')]; }
        # Notify slurp result
        { _args = [(mkLua ''mainMod .. " + N"'') (mkLua ''hl.dsp.exec_cmd([[fish -c "notify-send (slurp -p)"]])'')]; }

        # Rename workspace to active window class
        { _args = [(mkLua ''mainMod .. " + R"'') (mkLua ''hl.dsp.exec_cmd([[fish -c 'hyprctl dispatch renameworkspace $(hyprctl activeworkspace -j | jq -r ".id") $(hyprctl activewindow -j | jq -r ".class")']])'')]; }

        # Scroll workspaces
        { _args = [(mkLua ''mainMod .. " + mouse_down"'') (mkLua ''hl.dsp.focus({ workspace = "e+1" })'')]; }
        { _args = [(mkLua ''mainMod .. " + mouse_up"'') (mkLua ''hl.dsp.focus({ workspace = "e-1" })'')]; }

        # Mouse binds for move/resize
        { _args = [(mkLua ''mainMod .. " + mouse:272"'') (mkLua "hl.dsp.window.drag()") { mouse = true; }]; }
        { _args = [(mkLua ''mainMod .. " + mouse:273"'') (mkLua "hl.dsp.window.resize()") { mouse = true; }]; }
      ];

      # ---- Startup hook (runs after compositor is ready) ----
      on = [
        { _args = ["hyprland.start" (mkLua (''
          function()
            hl.exec_cmd("tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE " .. os.getenv("HYPRLAND_INSTANCE_SIGNATURE"))
            hl.exec_cmd("lxqt-policykit-agent")
        '' + (if compName == "secu" then ''
            hl.exec_cmd("fish ~/dotfiles/.config/startup-secu.fish")
        '' else ''
            hl.exec_cmd("fish -c \"tmux new-session -d ; sleep 1; fish ~/dotfiles/.config/startup.fish\"")
        '') + ''
            hl.exec_cmd("fish ~/.xprofile.fish")
            hl.exec_cmd("wl-paste --type text --watch cliphist store")
            hl.exec_cmd("wl-paste --type image --watch cliphist store")
            hl.exec_cmd("voxtype daemon")
          end
        ''))]; }
      ];
    };
  };

  services.gammastep = lib.mkIf (compName != "secu" && compName != "arch") {
    enable = true;
    # New york
    longitude = -74.0060;
    latitude = 40.7128;
    temperature = {
      day = 6500;
      night = 3500;
    };
  };

  home.activation.flatpakOverrides = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.flatpak}/bin/flatpak override --user \
      --talk-name=org.kde.StatusNotifierWatcher \
      com.teamspeak.TeamSpeak3 || true
  '';

  xdg.configFile = {
    "alacritty/alacritty.toml".source = config.lib.file.mkOutOfStoreSymlink ../.config/alacritty/alacritty.toml;
    "dunst/dunstrc".source = config.lib.file.mkOutOfStoreSymlink ../.config/dunst/dunstrc;
    "hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink ../.config/hypr/hyprlock.conf;
    "hypr/hyprpaper.conf".text = "
      preload = /home/john/backgrounds/luna_1.png
      wallpaper = , /home/john/backgrounds/luna_1.png
    ";
    # "waybar".source = config.lib.file.mkOutOfStoreSymlink ../.config/waybar;

    #"get_sunset.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_sunset.fish;
    #"get_mullvad.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_mullvad.fish;

    "focussed-vol-adjust.sh".source =
      builtins.fetchGit {
        url = "https://github.com/Orbsa/hyprland-pipewire-focused-volume-adjust";
        ref = "master";
        rev = "c268b0269617c5109585044ef6eac8623090891f";
      }
      + "/hpfva.sh";
  };

  services.dunst = {
    enable = true;
    configFile = "${config.home.homeDirectory}/dotfiles/.config/dunst/dunstrc";
  };

  # Aggressive stop timeouts for user services that block home-manager
  # activation (sd-switch hangs waiting for them to stop).
  systemd.user.services.dunst.Service.TimeoutStopSec = 10;
  systemd.user.services.udiskie.Service.TimeoutStopSec = 10;
  # Fix eww systemd service: clean stale sockets on startup
  systemd.user.services.eww.Service.ExecStartPre = [
    "${pkgs.coreutils}/bin/rm -f /run/user/%U/eww-server_*"
  ];
}
