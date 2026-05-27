{
  pkgs,
  compName,
  lib,
  ...
}: let
  media-player-status = pkgs.writeShellApplication {
    name = "media-player-status";
    runtimeInputs = with pkgs; [playerctl jq];
    text = ''
      # Get all active players
      players=$(playerctl --list-all 2>/dev/null)
      if [ -z "$players" ]; then
        echo '{"text": "♪", "class": "stopped", "tooltip": "No media playing"}'
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
        Playing)  class="playing"; icon="▶" ;;
        Paused)   class="paused";  icon="⏸" ;;
        *)        echo '{"text": "♪", "class": "stopped", "tooltip": "No media playing"}'; exit 0 ;;
      esac

      if [ -n "$title" ]; then
        if [ -n "$artist" ]; then
          text="$icon  $player_name: $artist — $title"
        else
          text="$icon  $player_name: $title"
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
          Playing) icon_t="▶" ;;
          Paused)  icon_t="⏸" ;;
          *)       icon_t="■" ;;
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
    runtimeInputs = with pkgs; [coreutils];
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
    runtimeInputs = with pkgs; [coreutils];
    text = ''
      # Check for active audio capture sources via pactl
      if pactl list sources 2>/dev/null | grep -q "State: RUNNING"; then
        echo '{"text": "", "class": "recording", "tooltip": "Microphone active"}'
      else
        echo '{"text": "", "class": "", "tooltip": ""}'
      fi
    '';
  };

  autoclicker = "${pkgs.autoclicker}/bin/autoclicker";

  # Shell scripts retained as fallback; Rust binary is primary
  autoclicker-daemon = pkgs.writeShellApplication {
    name = "autoclicker-daemon";
    runtimeInputs = with pkgs; [ydotool coreutils gawk];
    text = ''
      CONF_FILE="/tmp/autoclicker.conf"
      PID_FILE="/tmp/autoclicker.pid"
      STATUS_FILE="/tmp/autoclicker.state"

      # Defaults
      INTERVAL="500"
      BUTTON="left"
      DEADMAN="true"
      DEADMAN_THRESHOLD="10"
      MAX_DURATION="300"
      MAX_CLICKS=""

      # Load config if present
      if [ -f "$CONF_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONF_FILE"
      fi

      # Map button name to ydotool key code
      case "$BUTTON" in
        left)   BTN="0xC0" ;;
        middle) BTN="0xC2" ;;
        right)  BTN="0xC1" ;;
        *)      BTN="0xC0" ;;
      esac

      # Validate ydotool daemon is reachable
      if ! ydotool click 0xC0 2>/dev/null; then
        notify-send "Autoclicker" "ydotool daemon not running. Start ydotoold first." -u critical
        rm -f "$PID_FILE"
        exit 1
      fi

      echo $$ > "$PID_FILE"

      # Safety state
      START_TIME=$(date +%s)
      CLICK_COUNT=0
      LAST_X=""
      LAST_Y=""

      while true; do
        # Reload config each iteration
        if [ -f "$CONF_FILE" ]; then
          # shellcheck source=/dev/null
          . "$CONF_FILE"
          case "$BUTTON" in
            left)   BTN="0xC0" ;;
            middle) BTN="0xC2" ;;
            right)  BTN="0xC1" ;;
            *)      BTN="0xC0" ;;
          esac
        fi

        # ---- Max duration check ----
        if [ -n "$MAX_DURATION" ] && [ "$MAX_DURATION" -gt 0 ]; then
          NOW=$(date +%s)
          ELAPSED=$((NOW - START_TIME))
          if [ "$ELAPSED" -ge "$MAX_DURATION" ]; then
            notify-send "Autoclicker" "Auto-stopped: $MAX_DURATION s elapsed"
            rm -f "$PID_FILE"
            pkill -RTMIN+15 waybar 2>/dev/null
            exit 0
          fi
        fi

        # ---- Max click count check ----
        if [ -n "$MAX_CLICKS" ] && [ "$MAX_CLICKS" -gt 0 ] && [ "$CLICK_COUNT" -ge "$MAX_CLICKS" ]; then
          notify-send "Autoclicker" "Auto-stopped: $MAX_CLICKS clicks reached"
          rm -f "$PID_FILE"
          pkill -RTMIN+15 waybar 2>/dev/null
          exit 0
        fi

        # ---- Dead-man switch ----
        if [ "$DEADMAN" = "true" ]; then
          CURSOR=$(hyprctl cursorpos 2>/dev/null || echo "")
          if [ -n "$CURSOR" ]; then
            CX=$(echo "$CURSOR" | cut -d, -f1 | tr -d ' ')
            CY=$(echo "$CURSOR" | cut -d, -f2 | tr -d ' ')
            if [ -n "$LAST_X" ] && [ -n "$LAST_Y" ]; then
              DX=$((CX - LAST_X))
              DY=$((CY - LAST_Y))
              [ "$DX" -lt 0 ] && DX=$(( -DX ))
              [ "$DY" -lt 0 ] && DY=$(( -DY ))
              if [ "$((DX + DY))" -gt "$DEADMAN_THRESHOLD" ]; then
                LAST_X="$CX"
                LAST_Y="$CY"
                SLEEP_S=$(awk "BEGIN {printf \"%.3f\", $INTERVAL/1000}")
                sleep "$SLEEP_S"
                continue
              fi
            fi
            LAST_X="$CX"
            LAST_Y="$CY"
          fi
        fi

        # ---- Perform click ----
        ydotool click "$BTN"
        CLICK_COUNT=$((CLICK_COUNT + 1))

        SLEEP_S=$(awk "BEGIN {printf \"%.3f\", $INTERVAL/1000}")
        sleep "$SLEEP_S"
      done
    '';
  };

  autoclicker-timer = pkgs.writeShellApplication {
    name = "autoclicker-timer";
    runtimeInputs = with pkgs; [coreutils gawk];
    text = ''
      PID_FILE="/tmp/autoclicker.pid"
      CONF_FILE="/tmp/autoclicker.conf"

      # Defaults
      INTERVAL="500"
      BUTTON="left"
      MAX_DURATION="300"
      DEADMAN="true"

      # USR1 handler: re-read config on demand
      trap ":" USR1

      emit_status() {
        local text class pct tooltip

        # Load latest config
        INTERVAL="500"; BUTTON="left"; MAX_DURATION="300"; DEADMAN="true"
        if [ -f "$CONF_FILE" ]; then
          . "$CONF_FILE"
        fi

        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
          # Daemon is running
          class="autoclicker-active"

          if [ -n "$MAX_DURATION" ] && [ "$MAX_DURATION" -gt 0 ]; then
            # Timer mode — compute remaining
            NOW=$(date +%s)
            START_FILE="/tmp/autoclicker.start"
            if [ -f "$START_FILE" ]; then
              START_TS=$(cat "$START_FILE")
            else
              START_TS="$NOW"
              echo "$NOW" > "$START_FILE"
            fi
            ELAPSED=$((NOW - START_TS))
            REMAINING=$((MAX_DURATION - ELAPSED))
            [ "$REMAINING" -lt 0 ] && REMAINING=0

            PCT=100
            if [ "$MAX_DURATION" -gt 0 ]; then
              PCT=$(( ELAPSED * 100 / MAX_DURATION ))
              [ "$PCT" -gt 100 ] && PCT=100
            fi

            MIN=$((REMAINING / 60))
            SEC=$((REMAINING % 60))
            text=$(printf "%d:%02d" "$MIN" "$SEC")

            # Color transitions: green > 60s, yellow 60-10s, red < 10s
            if [ "$REMAINING" -le 10 ]; then
              class="autoclicker-warning"
            elif [ "$REMAINING" -le 60 ]; then
              class="autoclicker-expiring"
            else
              class="autoclicker-active"
            fi

            tooltip=$(printf "Autoclicker: ON\\nButton: %s\\nInterval: %sms\\nRemaining: %dm %ds" \
              "$BUTTON" "$INTERVAL" "$MIN" "$SEC")
          else
            # No duration limit — simple active indicator
            text="󰕰"
            PCT=""
            tooltip=$(printf "Autoclicker: ON\\nButton: %s\\nInterval: %sms" "$BUTTON" "$INTERVAL")
          fi

          if [ "$DEADMAN" = "true" ]; then
            tooltip="$tooltip\\nSafety: dead-man ON"
          fi

          # Emit JSON with class early for reliable CSS application
          if [ -n "$PCT" ]; then
            printf '{"text": "%s", "class": "%s", "percentage": %d, "tooltip": "%s"}' \
              "$text" "$class" "$PCT" "$tooltip"
          else
            printf '{"text": "%s", "class": "%s", "tooltip": "%s"}' \
              "$text" "$class" "$tooltip"
          fi
        else
          # Daemon not running
          rm -f "$PID_FILE" /tmp/autoclicker.start
          printf '{"text": "󰍺", "class": "autoclicker-inactive", "tooltip": "Autoclicker: OFF"}'
        fi
      }

      # Initial emission
      emit_status

      # Continuous loop — update every 500ms
      while true; do
        sleep 0.5
        emit_status
      done
    '';
  };

  autoclicker-menu = pkgs.writeShellApplication {
    name = "autoclicker-menu";
    runtimeInputs = with pkgs; [wofi coreutils ydotool autoclicker];
    text = ''
      PID_FILE="/tmp/autoclicker.pid"
      CONF_FILE="/tmp/autoclicker.conf"

      # Determine current state
      RUNNING=false
      if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        RUNNING=true
      else
        rm -f "$PID_FILE"
      fi

      # Load current config
      INTERVAL="500"
      BUTTON="left"
      if [ -f "$CONF_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONF_FILE"
      fi

      # Build menu
      if $RUNNING; then
        MENU=$(printf "■  Stop\\n⏱  Interval: %sms\\n󰊴  Button: %s" "$INTERVAL" "$BUTTON")
      else
        MENU=$(printf "▶  Start\\n⏱  Interval: %sms\\n󰊴  Button: %s" "$INTERVAL" "$BUTTON")
      fi

      CHOICE=$(printf "%b" "$MENU" | wofi --dmenu -p "Autoclicker" -i 2>/dev/null)

      case "$CHOICE" in
        "▶  Start")
          # Save config and launch daemon
          printf 'INTERVAL=%s\nBUTTON=%s\n' "$INTERVAL" "$BUTTON" > "$CONF_FILE"
          autoclicker daemon &
          pkill -RTMIN+15 waybar 2>/dev/null
          ;;
        "■  Stop")
          if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null
            rm -f "$PID_FILE"
          fi
          rm -f /tmp/autoclicker.sock
          pkill -RTMIN+15 waybar 2>/dev/null
          ;;
        "⏱  Interval: "*)
          # Show interval submenu
          NEW_INT=$(printf "100\n250\n500\n1000\n2000\n5000" | wofi --dmenu -p "Interval (ms)" -i 2>/dev/null)
          if [ -n "$NEW_INT" ]; then
            INTERVAL="$NEW_INT"
            printf 'INTERVAL=%s\nBUTTON=%s\n' "$INTERVAL" "$BUTTON" > "$CONF_FILE"
            # Restart daemon if running
            if $RUNNING; then
              if [ -f "$PID_FILE" ]; then
                kill "$(cat "$PID_FILE")" 2>/dev/null
                rm -f "$PID_FILE"
              fi
              rm -f /tmp/autoclicker.sock
              autoclicker daemon &
            fi
          fi
          pkill -RTMIN+15 waybar 2>/dev/null
          ;;
        "󰊴  Button: "*)
          # Show button submenu
          NEW_BTN=$(printf "left\nmiddle\nright" | wofi --dmenu -p "Mouse button" -i 2>/dev/null)
          if [ -n "$NEW_BTN" ]; then
            BUTTON="$NEW_BTN"
            printf 'INTERVAL=%s\nBUTTON=%s\n' "$INTERVAL" "$BUTTON" > "$CONF_FILE"
            # Restart daemon if running
            if $RUNNING; then
              if [ -f "$PID_FILE" ]; then
                kill "$(cat "$PID_FILE")" 2>/dev/null
                rm -f "$PID_FILE"
              fi
              rm -f /tmp/autoclicker.sock
              autoclicker daemon &
            fi
          fi
          pkill -RTMIN+15 waybar 2>/dev/null
          ;;
      esac
    '';
  };
  stop-autoclicker = pkgs.writeShellApplication {
    name = "stop-autoclicker";
    runtimeInputs = with pkgs; [coreutils];
    text = ''
      PID_FILE="/tmp/autoclicker.pid"
      if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
      fi
      rm -f /tmp/autoclicker.sock
      pkill -RTMIN+15 waybar 2>/dev/null
    '';
  };
  # Workspace icon mappings — common Nerd Font v3 glyphs
  ws-icons = {
    "A1" = "󰮠";
    "A2" = "󰈹";
    "A3" = "";
    "A4" = "󰈙";
    "A5" = "";
    "B1" = "";
    "B2" = "󰈹";
    "B3" = "";
    "B4" = "";
    "B5" = "";
    "ts" = "󰍬";
    "disc" = "";
    "steam" = "";
    "obsidian" = "󰠮";
    "spotify" = "";
  };
in {
  programs.waybar = {
    enable = true;
    style = ../../.config/waybar/style.css;
    settings = {
      mainBar =
        {
          # ---- Global ----
          layer = "top";
          position = "top";
          height = 42;
          spacing = 4;
          margin = "0 12 0 12"; # top right bottom left — flush to top edge
          reload_style_on_change = true;

          # ---- Left zone ----
          modules-left = [
            "hyprland/workspaces"
            "custom/newworkspace"
            "hyprland/window"
          ];

          # ---- Center zone ----
          modules-center = [
            "custom/media"
          ];

          # ---- Right zone ----
          modules-right =
            [
              #"custom/mullvad"  # DISABLED: mullvad-vpn blocked by gitlab.gnome.org 503
              "group/hardware"
              "group/clock"
              "custom/updates"
            ]
            ++ (lib.optionals (compName == "arch") [
              "custom/thermostat"
            ])
            ++ [
              "custom/teamspeak-mic"
              "custom/teamspeak-sound"
              "custom/vast"
              "custom/weather"
              "custom/privacy"
              "battery"
              "custom/autoclicker"
              "tray"
              "pulseaudio"
            ];

          # ======== Module Configurations ========

          # ---- Workspaces ----
          "hyprland/workspaces" = let
            left =
              if compName == "office"
              then "DP-2"
              else "DP-3";
            right =
              if compName == "office"
              then "DP-1"
              else "HDMI-A-2";
          in {
            format = "{icon}  {windows}";
            format-icons = ws-icons;
            tooltip = true;
            tooltip-format = "{name}";
            "workspace-taskbar" = {
              enable = true;
              "update-active-window" = true;
              "format" = "{icon}";
              "icon-size" = 24;
              "on-click-window" = "hyprctl dispatch focuswindow address:{address}";
              "ignore-list" = ["^xwaylandvideobridge$"];
            };
            "persistent_workspaces" = {
              "A1" = [left];
              "A2" = [left];
              "A3" = [left];
              "A4" = [left];
              "A5" = [left];
              "B1" = [right];
              "B2" = [right];
              "B3" = [right];
              "B4" = [right];
              "B5" = [right];
              "ts" = [right];
              "disc" = [right];
              "steam" = [right];
              "obsidian" = [right];
              "spotify" = [right];
            };
          };

          # ---- New Workspace ----
          "custom/newworkspace" = {
            format = "";
            tooltip = true;
            tooltip-format = "New temporary workspace";
            on-click = "fish -c 'set NAME (date +%s | tail -c 5); hyprctl dispatch \"hl.dsp.focus({ workspace = \\\"name:$NAME\\\" })\"'";
          };

          # ---- Clock Group (drawer reveals date on hover) ----
          "group/clock" = {
            orientation = "horizontal";
            drawer = {
              "transition-duration" = 300;
              "children-class" = "hidden-ck";
              "transition-left-to-right" = false;
            };
            modules = [
              "clock"
              "custom/clock-date"
            ];
          };

          # ---- Clock (inside group/clock drawer) ----
          clock = {
            interval = 1;
            format = "{:%H:%M:%S}";
            on-click-right = "fish -c 'date +\"%A, %e %B %Y — %H:%M:%S\" | wl-copy; notify-send \"Copied\" (wl-paste)'";
          };

          # ---- Clock Date (hidden until hover) ----
          "custom/clock-date" = {
            exec = "${pkgs.writeShellScript "waybar-clock-date" ''
              date '+%A, %e %B %Y'
            ''}";
            interval = 10;
            on-click-right = "fish -c 'date +\"%A, %e %B %Y — %H:%M:%S\" | wl-copy; notify-send \"Copied\" (wl-paste)'";
          };

          # ---- Media Player (center) ----
          "custom/media" = {
            exec = "${pkgs.writeShellScript "media-safe" ''
              out=$(${media-player-status}/bin/media-player-status 2>/dev/null)
              if echo "$out" | ${pkgs.jq}/bin/jq empty 2>/dev/null; then
                echo "$out"
              else
                echo '{"text":"♪","class":"stopped","tooltip":""}'
              fi
            ''}";
            return-type = "json";
            interval = 5;
            signal = 12;
            format = "{}";
            on-click = "playerctl --all-players --ignore-player=firefox,chromium,chrome play-pause; pkill -RTMIN+12 waybar";
            on-click-right = "playerctl --all-players --ignore-player=firefox,chromium,chrome next; pkill -RTMIN+12 waybar";
            on-click-middle = "playerctl --all-players --ignore-player=firefox,chromium,chrome previous; pkill -RTMIN+12 waybar";
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
        }
        // (lib.optionalAttrs (compName == "arch") {
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
        })
        // {
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
          "custom/autoclicker" = {
            exec = "${autoclicker} watch";
            return-type = "json";
            signal = 15;
            format = "{}";
            tooltip = true;
            on-click = "${autoclicker-menu}/bin/autoclicker-menu";
          };
        };
    };
  };

  systemd.user.services.waybar = {
    Unit = {
      Description = "Highly customizable Wayland bar for Sway and Wlroots based compositors";
      Documentation = "https://github.com/Alexays/Waybar/wiki/";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
      Requisite = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.waybar}/bin/waybar";
      Environment = [
        "GTK_TOOLTIP_TIMEOUT=0"
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/john/bin"
      ];
      PassEnvironment = "DBUS_SESSION_BUS_ADDRESS DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR";
      ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
      Restart = "on-failure";
      TimeoutStopSec = 10;
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
