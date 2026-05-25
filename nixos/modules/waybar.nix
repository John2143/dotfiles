{pkgs, compName, lib, ...}:
let
  media-player-status = pkgs.writeShellApplication {
    name = "media-player-status";
    runtimeInputs = with pkgs; [ playerctl jq ];
    text = ''
      # Get all active players
      players=$(playerctl --list-all 2>/dev/null)
      if [ -z "$players" ]; then
        echo '{"text": "", "class": "stopped"}'
        exit 0
      fi

      # Find best player: prefer Playing (non-browser first), then Paused
      best=""
      best_status=""
      for p in $players; do
        s=$(playerctl --player="$p" status 2>/dev/null)
        # Skip browser players unless they are the only ones
        case "$p" in
          firefox*|chromium*|chrome*|Floorp*)
            [ "$s" = "Playing" ] && browser_playing="$p"
            continue
            ;;
        esac
        case "$s" in
          Playing) best="$p"; best_status="$s"; break ;;
          Paused)  [ -z "$best" ] && { best="$p"; best_status="$s"; };;
        esac
      done

      # Fall back to browser if nothing else is playing
      if [ -z "$best" ] && [ -n "$browser_playing" ]; then
        best="$browser_playing"
        best_status="Playing"
      fi

      # Fall back to any player
      if [ -z "$best" ]; then
        best=$(echo "$players" | head -1)
        best_status=$(playerctl --player="$best" status 2>/dev/null)
      fi

      artist=$(playerctl --player="$best" metadata artist 2>/dev/null | head -c 30)
      title=$(playerctl --player="$best" metadata title 2>/dev/null | head -c 50)
      player_name="$best"

      case "$best_status" in
        Playing)  class="playing"; icon="" ;;
        Paused)   class="paused";  icon="" ;;
        *)        echo '{"text": "", "class": "stopped"}'; exit 0 ;;
      esac

      if [ -n "$title" ]; then
        if [ -n "$artist" ]; then
          text="$icon  $artist — $title"
        else
          text="$icon  $title"
        fi
      else
        text="$icon  $player_name"
      fi

      # Build tooltip with all active players
      tooltip=""
      for p in $players; do
        s=$(playerctl --player="$p" status 2>/dev/null)
        a=$(playerctl --player="$p" metadata artist 2>/dev/null)
        t=$(playerctl --player="$p" metadata title 2>/dev/null)
        icon_t=""
        case "$s" in
          Playing) icon_t="" ;;
          Paused)  icon_t="" ;;
          *)       icon_t="" ;;
        esac
        if [ -n "$t" ]; then
          tooltip="$tooltip$icon_t $p: $a — $t\n"
        fi
      done
      tooltip=$(echo -e "$tooltip" | head -c 500)  # convert \n, truncate

      jq -n --arg text "$text" --arg class "$class" --arg tooltip "$tooltip" \
        '{text: $text, class: $class, tooltip: $tooltip}'
    '';
  };

  nix-update-status = pkgs.writeShellApplication {
    name = "nix-update-status";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      LOCK_FILE="$HOME/dotfiles/flake.lock"
      if [ -f "$LOCK_FILE" ]; then
        AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
        if [ "$AGE" -gt 86400 ]; then
          echo '{"text": "󰚰", "class": "pending-updates", "tooltip": "flake.lock >24h old — consider updating"}'
        else
          echo '{"text": "", "class": "updated", "tooltip": "flake.lock is current"}'
        fi
      else
        echo '{"text": "", "class": ""}'
      fi
    '';
  };

  privacy-status = pkgs.writeShellApplication {
    name = "privacy-status";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      # Check for active audio capture sources via pactl
      if pactl list sources 2>/dev/null | grep -q "State: RUNNING"; then
        echo '{"text": "", "class": "recording", "tooltip": "Microphone active"}'
      else
        echo '{"text": "", "class": "", "tooltip": ""}'
      fi
    '';
  };

  # Workspace icon mappings — common Nerd Font v3 glyphs
  ws-icons = {
    "A1" = "󰮠"; "A2" = "󰈹"; "A3" = ""; "A4" = "󰈙"; "A5" = "";
    "B1" = ""; "B2" = "󰈹"; "B3" = ""; "B4" = ""; "B5" = "";
    "ts" = "󰍬"; "disc" = ""; "steam" = ""; "obsidian" = "󰠮"; "spotify" = "";
  };
in {
  programs.waybar = {
    enable = true;
    style = ../../.config/waybar/style.css;
    settings = {
      mainBar = {
        # ---- Global ----
        layer = "top";
        position = "top";
        height = 38;
        spacing = 4;
        margin = "0 12 0 12";  # top right bottom left — flush to top edge
        reload_style_on_change = true;

        # ---- Left zone ----
        modules-left = [
          "hyprland/workspaces"
          "custom/newworkspace"
          "hyprland/window"
        ];

        # ---- Center zone ----
        modules-center = [
          "clock"
          "custom/media"
        ];

        # ---- Right zone ----
        modules-right = [
          #"custom/mullvad"  # DISABLED: mullvad-vpn blocked by gitlab.gnome.org 503
          "group/hardware"
          "custom/updates"
        ] ++ (lib.optionals (compName == "arch") [
          "custom/thermostat"
        ]) ++ [
          "custom/teamspeak-mic"
          "custom/teamspeak-sound"
          "custom/vast"
          "custom/weather"
          "custom/privacy"
          "battery"
          "tray"
          "pulseaudio"
        ];

        # ======== Module Configurations ========

        # ---- Workspaces ----
        "hyprland/workspaces" = let
          left = if compName == "office" then "DP-2" else "DP-3";
          right = if compName == "office" then "DP-1" else "HDMI-A-2";
        in {
          format = "{icon}";
          format-icons = ws-icons;
          tooltip = true;
          tooltip-format = "{windows}";
          "workspace-taskbar" = {
            enable = true;
            "update-active-window" = true;
            "format" = "{icon}";
            "icon-size" = 24;
            "on-click-window" = "hyprctl dispatch focuswindow address:{address}";
            "ignore-list" = ["^xwaylandvideobridge$"];
          };
          persistent_workspaces = {
            "A1" = [left]; "A2" = [left]; "A3" = [left]; "A4" = [left]; "A5" = [left];
            "B1" = [right]; "B2" = [right]; "B3" = [right]; "B4" = [right]; "B5" = [right];
            "ts" = [right]; "disc" = [right]; "steam" = [right]; "obsidian" = [right]; "spotify" = [right];
          };
        };

        # ---- New Workspace ----
        "custom/newworkspace" = {
          format = "";
          tooltip = true;
          tooltip-format = "New temporary workspace";
          on-click = "fish -c 'set NAME (date +%s | tail -c 5); hyprctl dispatch workspace name:$NAME'";
        };

        # ---- Clock (center, consolidated) ----
        clock = {
          interval = 1;
          format = "{:%H:%M}";
          tooltip-format = "{:%A, %e %B %Y}";
          tooltip = true;
          on-click-right = "fish -c 'date +\"%A, %e %B %Y — %H:%M\" | wl-copy; notify-send \"Copied\" (wl-paste)'";
        };

        # ---- Media Player (center) ----
        "custom/media" = {
          exec = "${media-player-status}/bin/media-player-status";
          return-type = "json";
          interval = "once";
          signal = 12;
          format = "{}";
          on-click = "playerctl --all-players --ignore-player=firefox,chromium,chrome play-pause";
          on-click-right = "playerctl --all-players --ignore-player=firefox,chromium,chrome next";
          on-click-middle = "playerctl --all-players --ignore-player=firefox,chromium,chrome previous";
          escape = true;
        };

        # ---- Mullvad VPN (DISABLED: mullvad-vpn blocked by gitlab.gnome.org 503) ----
        #"custom/mullvad" = {
        #  interval = 20;
        #  exec = "${pkgs.writeShellScript "waybar-mullvad-status" ''
        #    if ${pkgs.mullvad-vpn}/bin/mullvad status | grep -q "Connected"; then
        #      echo '{"text": "", "class": "connected", "tooltip": "Mullvad connected"}'
        #    else
        #      echo '{"text": "", "class": "disconnected", "tooltip": "Mullvad disconnected"}'
        #    fi
        #  ''}";
        #  return-type = "json";
        #  on-click = "${pkgs.mullvad-vpn}/bin/mullvad connect; sleep 2; pkill -RTMIN+14 waybar";
        #  on-click-right = "${pkgs.mullvad-vpn}/bin/mullvad disconnect; sleep 1; pkill -RTMIN+14 waybar";
        #  on-click-middle = "${pkgs.mullvad-vpn}/bin/mullvad reconnect; sleep 2; pkill -RTMIN+14 waybar";
        #  signal = 14;
        #  format = "{}";
        #};

        # ---- Hardware Group (drawer) ----
        "group/hardware" = {
          orientation = "horizontal";
          drawer = {
            "transition-duration" = 300;
            "children-class" = "hidden-hw";
            "transition-left-to-right" = false;
          };
          modules = [
            "cpu"
            "memory"
            "temperature"
          ];
        };

        # ---- CPU ----
        cpu = {
          interval = 5;
          format = "  {usage}%";
          states = {
            warning = 70;
            critical = 90;
          };
        };

        # ---- Memory ----
        memory = {
          interval = 5;
          format = "  {used}G";
          states = {
            warning = 70;
            critical = 90;
          };
        };

        # ---- Temperature ----
        temperature = {
          criticalThreshold = 80;
          interval = 1;
          format = "  {temperatureC}°";
          thermalZone = "thermal_zone2";
          formatIcons = ["" "" "" "" ""];
          tooltip = true;
        };

        # ---- Updates Indicator ----
        "custom/updates" = {
          exec = "${nix-update-status}/bin/nix-update-status";
          return-type = "json";
          interval = 3600;
          format = "{}";
          on-click = "${pkgs.alacritty}/bin/alacritty -e fish -c 'cd ~/dotfiles && nix flake update'";
        };

        # ---- Weather ----
        "custom/weather" = {
          exec = "weather-status";
          return-type = "json";
          interval = 900;
          format = "{}";
          tooltip = true;
        };

        # ---- Privacy Indicator ----
        "custom/privacy" = {
          exec = "${privacy-status}/bin/privacy-status";
          return-type = "json";
          interval = "once";
          signal = 13;
          format = "{}";
        };

        # ---- Battery ----
        battery = {
          interval = 10;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "  {icon}  {capacity}%";
          format-discharging = "{icon}  {capacity}%";
          format-icons = ["" "" "" "" ""];
          tooltip = true;
        };

        # ---- PulseAudio ----
        pulseaudio = {
          interval = 5;
          scroll-step = 3;
          format = "{icon}  {volume}%";
          format-bluetooth = "{icon}    {volume}%";
          format-muted = "";
          format-icons = {
            headphones = "";
            handsfree = "";
            headset = "󰋎";
            phone = "";
            portable = "";
            car = "";
            default = ["" ""];
          };
          onClickRight = "pavucontrol";
          onClickMiddle = "fish -c '/home/john/.config/polybar/scripts/sinks.fish bluetooth'";
          onClick = "fish -c '/home/john/.config/polybar/scripts/sinks.fish scarlett'";
        };

        # ---- System Tray ----
        tray = {
          iconSize = 18;
          spacing = 8;
        };
      } // (lib.optionalAttrs (compName == "arch") {
        "custom/thermostat" = {
          exec = "hass-thermostat-status";
          return-type = "json";
          interval = 30;
          signal = 8;
          format = "{}";
          on-click-right = "hass-macro ac-toggle";
          on-scroll-up = "hass-macro thermostat-up";
          on-scroll-down = "hass-macro thermostat-down";
          on-click-middle = "hass-macro thermostat-toggle";
          tooltip = true;
        };
      }) // {
        "custom/teamspeak-mic" = {
          exec = "teamspeak-mute-status --mic";
          return-type = "json";
          interval = 2;
          signal = 10;
          format = "{}";
          tooltip = true;
          on-click = "teamspeak-mute-status --toggle && pkill -RTMIN+10 waybar";
        };
        "custom/teamspeak-sound" = {
          exec = "teamspeak-mute-status --sound";
          return-type = "json";
          interval = 2;
          signal = 11;
          format = "{}";
          tooltip = true;
          on-click = "teamspeak-mute-status --toggle-output && pkill -RTMIN+11 waybar";
        };
        "custom/vast" = {
          exec = "vast-waybar-status";
          return-type = "json";
          interval = 60;
          signal = 9;
          format = "{}";
          tooltip = true;
          on-click = "rm -f /tmp/vast-waybar-status.json && pkill -RTMIN+9 waybar";
        };
      };
    };
  };

  systemd.user.services.waybar = {
    Unit = {
      Description = "Highly customizable Wayland bar for Sway and Wlroots based compositors";
      Documentation = "https://github.com/Alexays/Waybar/wiki/";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Requisite = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.waybar}/bin/waybar";
      Environment = "GTK_TOOLTIP_TIMEOUT=0";
      ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
      Restart = "on-failure";
      TimeoutStopSec = 10;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
