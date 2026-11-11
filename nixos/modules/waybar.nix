{
  pkgs,
  compName,
  lib,
  ...
}: let
  media-player-status = pkgs.writeShellApplication {
    name = "media-player-status";
    runtimeInputs = with pkgs; [playerctl jq pulseaudio gnused];
    text = ''
      # Icons: ▶ (playing), ⏸ (paused), ♫ (no player), ■ (stopped in tooltip)
      players=$(playerctl --list-all 2>/dev/null || true)

      # Short player name for display: drop the ".instance<pid>"/".tab<id>"
      # suffix playerctl uses, then capitalise the first letter.
      pretty() {
        printf '%s' "$1" | sed -E 's/\.(instance|tab)[^.]*$//' | sed -E 's/^./\U&/'
      }

      # Firefox publishes one MPRIS player for the whole browser, but every tab
      # that is producing sound owns its own audio stream, named after the page's
      # document title (HTMLMediaElement::UpdateStreamName). Listing those
      # streams is the only way to see the tabs behind that rolled-up player.
      # Generic names are what Firefox falls back to when it cannot speak to
      # PulseAudio directly; showing them would list noise instead of tabs.
      tabs=$(pactl --format=json list sink-inputs 2>/dev/null | jq -r '
        [ .[]
          | . as $si
          | ($si.properties["media.name"] // "") as $n
          | select((((($si.properties["application.name"] // "") + " "
                      + ($si.properties["application.process.binary"] // "") + " "
                      + ($si.properties["application.icon_name"] // ""))
                     | ascii_downcase | test("firefox|librewolf|zen|floorp")))
                   and (($n | length) > 0)
                   and (($n | test("^(alsa playback|audio ?stream|playback ?stream|playback)$"; "i")) | not))
          | "\($n)\t"
            + "\(((.volume // {})
                  | [ .[].value_percent | sub("%"; "") | tonumber ]
                  | if length > 0 then (add / length | floor) else 0 end))"
        ] | .[]' 2>/dev/null || true)

      tab_count=0
      tab_list=""
      if [ -n "$tabs" ]; then
        while IFS=$'\t' read -r tab_title tab_vol; do
          [ -n "$tab_title" ] || continue
          tab_count=$((tab_count + 1))
          tab_list="$tab_list\n  ▶ $tab_title ($tab_vol%)"
        done <<< "$tabs"
      fi

      if [ -z "$players" ]; then
        if [ "$tab_count" -eq 0 ]; then
          echo '{"text": "♫", "class": "stopped", "tooltip": "No media playing"}'
          exit 0
        fi
        first_title=$(printf '%s\n' "$tabs" | head -n 1 | cut -f 1 || true)
        tooltip=$(printf '%b' "Firefox tabs:$tab_list" | head -c 1200 || true)
        jq -nc --arg text "▶  Firefox: $first_title" --arg class playing \
          --arg tooltip "$tooltip" '{text: $text, class: $class, tooltip: $tooltip}'
        exit 0
      fi

      # Check for user-selected player override
      selected=""
      if [ -f /tmp/media-player-selected ]; then
        sel=$(cat /tmp/media-player-selected)
        if printf '%s\n' "$players" | grep -qxF -- "$sel"; then
          selected="$sel"
        else
          # The player was closed since it was picked: drop the dead override,
          # otherwise scrolls and clicks keep targeting a player that is gone.
          rm -f /tmp/media-player-selected
        fi
      fi

      if [ -n "$selected" ]; then
        best="$selected"
        best_status=$(playerctl --player="$best" status 2>/dev/null || true)
      else
        # Find best player: prefer Playing (non-browser first), then Paused
        best=""
        best_status=""
        browser_playing=""
        for p in $players; do
          s=$(playerctl --player="$p" status 2>/dev/null || true)
          case "$p" in
            firefox*|chromium*|chrome*|Floorp*|librewolf*|zen*)
              [ "$s" = "Playing" ] && browser_playing="$p"
              continue
              ;;
          esac
          case "$s" in
            Playing) best="$p"; best_status="$s"; break ;;
            Paused)  [ -z "$best" ] && { best="$p"; best_status="$s"; };;
          esac
        done

        if [ -z "$best" ] && [ -n "$browser_playing" ]; then
          best="$browser_playing"
          best_status="Playing"
        fi

        if [ -z "$best" ]; then
          best=$(printf '%s\n' "$players" | head -n 1 || true)
          best_status=$(playerctl --player="$best" status 2>/dev/null || true)
        fi
      fi

      # Write active player for scroll/volume commands
      printf '%s\n' "$best" > /tmp/media-player-active

      player_name=$(pretty "$best")
      artist=$(playerctl --player="$best" metadata artist 2>/dev/null | head -c 30 || true)
      title=$(playerctl --player="$best" metadata title 2>/dev/null | head -c 50 || true)

      tooltip=""
      for p in $players; do
        s=$(playerctl --player="$p" status 2>/dev/null || true)
        a=$(playerctl --player="$p" metadata artist 2>/dev/null || true)
        t=$(playerctl --player="$p" metadata title 2>/dev/null || true)
        case "$s" in
          Playing) icon_t="▶" ;;
          Paused)  icon_t="⏸" ;;
          *)       icon_t="■" ;;
        esac
        if [ -n "$t" ]; then
          tooltip="$tooltip$icon_t $(pretty "$p"): $a - $t\n"
        fi
      done
      if [ "$tab_count" -gt 0 ]; then
        tooltip="$tooltip""Firefox tabs:$tab_list"
      fi
      tooltip=$(printf '%b' "$tooltip" | head -c 1200 || true)

      case "$best_status" in
        Playing) class="playing"; icon="▶" ;;
        Paused)  class="paused";  icon="⏸" ;;
        *)
          jq -nc --arg text "♫  $player_name" --arg class stopped \
            --arg tooltip "$tooltip" '{text: $text, class: $class, tooltip: $tooltip}'
          exit 0 ;;
      esac

      vol=$(playerctl --player="$best" volume 2>/dev/null || true)
      vol_text=""
      if [ -n "$vol" ]; then
        vol_pct=$(printf '%s' "$vol" | awk '{printf "%.0f", $1 * 100}')
        vol_text=" $vol_pct%"
      fi

      if [ -n "$title" ]; then
        if [ -n "$artist" ]; then
          text="$icon  $player_name: $artist - $title"
        else
          text="$icon  $player_name: $title"
        fi
      else
        text="$icon  $player_name"
      fi
      text="$text$vol_text"

      jq -nc --arg text "$text" --arg class "$class" --arg tooltip "$tooltip" \
        '{text: $text, class: $class, tooltip: $tooltip}'
    '';
  };

  media-player-toggle = pkgs.writeShellApplication {
    name = "media-player-toggle";
    runtimeInputs = with pkgs; [playerctl procps];
    text = ''
      players=$(playerctl --list-all 2>/dev/null)
      if [ -z "$players" ]; then
        exit 0
      fi

      # Respect user-selected player first
      if [ -f /tmp/media-player-selected ]; then
        sel=$(cat /tmp/media-player-selected)
        if printf '%s\n' "$players" | grep -qxF -- "$sel"; then
          playerctl --player="$sel" play-pause
          pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true
          exit 0
        fi
      fi

      # Fall back to active player
      if [ -f /tmp/media-player-active ]; then
        active=$(cat /tmp/media-player-active)
        if printf '%s\n' "$players" | grep -qxF -- "$active"; then
          playerctl --player="$active" play-pause
          pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true
          exit 0
        fi
      fi

      # Final fallback: auto-select
      best=""
      browser_playing=""
      for p in $players; do
        s=$(playerctl --player="$p" status 2>/dev/null)
        case "$p" in
          firefox*|chromium*|chrome*|Floorp*)
            [ "$s" = "Playing" ] && browser_playing="$p"
            continue
            ;;
        esac
        case "$s" in
          Playing) best="$p"; break ;;
          Paused)  [ -z "$best" ] && best="$p" ;;
        esac
      done

      if [ -z "$best" ] && [ -n "$browser_playing" ]; then
        best="$browser_playing"
      fi

      if [ -z "$best" ]; then
        best=$(echo "$players" | head -1)
      fi

      playerctl --player="$best" play-pause
      pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true
    '';
  };

  media-player-focus = pkgs.writeShellApplication {
    name = "media-player-focus";
    runtimeInputs = with pkgs; [playerctl hyprland coreutils];
    text = ''
      players=$(playerctl --list-all 2>/dev/null)
      if [ -z "$players" ]; then
        exit 0
      fi

      # Find best player (same logic as media-player-status)
      best=""
      browser_playing=""
      for p in $players; do
        s=$(playerctl --player="$p" status 2>/dev/null)
        case "$p" in
          firefox*|chromium*|chrome*|Floorp*)
            [ "$s" = "Playing" ] && browser_playing="$p"
            continue
            ;;
        esac
        case "$s" in
          Playing) best="$p"; break ;;
          Paused)  [ -z "$best" ] && best="$p" ;;
        esac
      done

      if [ -z "$best" ] && [ -n "$browser_playing" ]; then
        best="$browser_playing"
      fi

      if [ -z "$best" ]; then
        best=$(echo "$players" | head -1)
      fi

      # Focus the window using Hyprland 0.55 Lua dispatch API
      # Try both lowercase and capitalized first letter
      cap="''${best^}"
      hyprctl dispatch "hl.dsp.focus({ window = 'class:^($best)$' })" 2>/dev/null || \
      hyprctl dispatch "hl.dsp.focus({ window = 'class:^($cap)$' })" 2>/dev/null || \
      hyprctl dispatch "hl.dsp.focus({ window = 'address:($best)' })" 2>/dev/null || true
    '';
  };

  media-player-volume = pkgs.writeShellApplication {
    name = "media-player-volume";
    runtimeInputs = with pkgs; [coreutils playerctl procps];
    text = ''
      players=$(playerctl --list-all 2>/dev/null || true)
      if [ -z "$players" ]; then
        exit 0
      fi

      # A selection that outlived its player (closed since it was picked) must
      # not swallow the event: drop it and fall back to what the bar shows.
      player=""
      if [ -f /tmp/media-player-selected ]; then
        sel=$(cat /tmp/media-player-selected)
        if printf '%s\n' "$players" | grep -qxF -- "$sel"; then
          player="$sel"
        else
          rm -f /tmp/media-player-selected
        fi
      fi
      if [ -z "$player" ] && [ -f /tmp/media-player-active ]; then
        active=$(cat /tmp/media-player-active)
        if printf '%s\n' "$players" | grep -qxF -- "$active"; then
          player="$active"
        fi
      fi
      if [ -z "$player" ]; then
        player=$(printf '%s\n' "$players" | head -n 1 || true)
      fi

      playerctl --player="$player" volume "$1"
      pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true
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
        echo '{"text": "●", "class": "recording", "tooltip": "An application is currently using your microphone."}'
      else
        echo '{"text": "", "class": "", "tooltip": ""}'
      fi
    '';
  };

  autoclicker = "${pkgs.autoclicker}/bin/autoclicker";

  autoclicker-menu = pkgs.writeShellApplication {
    name = "autoclicker-menu";
    runtimeInputs = with pkgs; [wofi coreutils autoclicker];
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
  tailscale-status = pkgs.writeShellApplication {
    name = "tailscale-status";
    runtimeInputs = with pkgs; [tailscale jq coreutils];
    text = ''
      data=$(tailscale status --json 2>/dev/null) || {
        jq -nc '{text: "", class: "disconnected", tooltip: "Tailscale: not running"}'
        exit 0
      }

      state=$(echo "$data" | jq -r '.BackendState // "Stopped"')
      online=$(echo "$data" | jq -r '.Self.Online // false')

      case "$state" in
        Running)
          if [ "$online" = "true" ]; then
            ip=$(echo "$data" | jq -r '.TailscaleIPs[0] // "?"')
            name=$(echo "$data" | jq -r '.Self.DNSName | rtrimstr(".") // "?"')
            # Detect exit node via debug prefs (works without sudo, unlike .Self.ExitNode in JSON)
            exit_id=$(tailscale debug prefs 2>/dev/null | jq -r '.ExitNodeID // ""')
            if [ -n "$exit_id" ] && [ "$exit_id" != "null" ] && [ "$exit_id" != "0" ]; then
              exit_name=$(tailscale exit-node list 2>/dev/null | awk '/selected/{print $2; exit}')
              jq -nc --arg ip "$ip" --arg name "$name" --arg exit_name "$exit_name" \
                '{text: "", class: "connected", tooltip: "Tailscale: Connected (\($name))\nIP: \($ip)\nExit: \($exit_name)"}'
            else
              jq -nc --arg ip "$ip" --arg name "$name" \
                '{text: "", class: "connected", tooltip: "Tailscale: Connected (\($name))\nIP: \($ip)"}'
            fi
          else
            jq -nc '{text: "", class: "disconnected", tooltip: "Tailscale: Connected but offline"}'
          fi
          ;;
        Stopped)
          jq -nc '{text: "", class: "disconnected", tooltip: "Tailscale: Stopped"}'
          ;;
        NeedsLogin)
          jq -nc '{text: "", class: "needs-login", tooltip: "Tailscale: Needs login"}'
          ;;
        *)
          jq -nc --arg state "$state" \
            '{text: "", class: "disconnected", tooltip: "Tailscale: \($state)"}'
          ;;
      esac
    '';
  };
  temporal-status = pkgs.writeShellApplication {
    name = "temporal-status";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if timeout 1 bash -c "exec 3<>/dev/tcp/192.168.6.20/7233" 2>/dev/null; then
        ${pkgs.jq}/bin/jq -nc '{text: "T", class: "connected", tooltip: "Temporal: connected (192.168.6.20:7233)"}'
      else
        ${pkgs.jq}/bin/jq -nc '{text: "T", class: "disconnected", tooltip: "Temporal: unreachable (192.168.6.20:7233)"}'
      fi
    '';
  };

  ws-icons = {
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
              "custom/privacy"
              "custom/screenrec"
              "custom/tailscale"
              "custom/temporal"
              "custom/voxtype"
              "group/hardware"
              "group/clock"
              "custom/updates"
            ]
            ++ (lib.optionals (compName == "arch") [
              "custom/thermostat"
            ])
            ++ [
              "custom/vast"
              "custom/weather"
              "custom/eww-hello"
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
            format = "{icon}";
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
            # Numbered id in 1000-9999, clear of the fixed workspaces 1-15 (home.nix). Hyprland
            # 0.57 rejects a numeric "name:" selector, and Waybar drops named workspaces.
            on-click = "fish -c 'set ID (math (date +%s) % 9000 + 1000); hyprctl dispatch \"hl.dsp.focus({ workspace = \\\"$ID\\\" })\"'";
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
            on-click = "toggle-calendar";
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
                echo '{"text":"♫","class":"stopped","tooltip":""}'
              fi
            ''}";
            return-type = "json";
            interval = 2;
            signal = 12;
            format = "{}";
            on-click = "${media-player-toggle}/bin/media-player-toggle";
            on-click-right = "media-picker-toggle";
            on-click-backward = "playerctl --all-players previous; pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true";
            on-click-forward = "playerctl --all-players next; pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true";
            on-click-middle = "${media-player-focus}/bin/media-player-focus";
            on-scroll-up = "${media-player-volume}/bin/media-player-volume 0.05+";
            on-scroll-down = "${media-player-volume}/bin/media-player-volume 0.05-";
          };

          # ---- Tailscale VPN ----
          "custom/tailscale" = {
            exec = "${tailscale-status}/bin/tailscale-status";
            return-type = "json";
            interval = 20;
            signal = 14;
            format = "{}";
            on-click = "eww open tailscale || eww close tailscale";
            on-click-right = "fish -c '
              set nodes (tailscale status --json | jq -r \".Peer[] | select(.ExitNodeOption == true) | .DNSName | rtrimstr(\\\".\\\")\" 2>/dev/null | string collect)
              if test -z \"$nodes\"
                notify-send \"Tailscale\" \"No exit node candidates found\"
                exit 0
              end
              set choice (printf \"None\n%s\" \"$nodes\" | wofi --dmenu -p \"Exit Node\" -i 2>/dev/null)
              if test \"$choice\" = \"None\"
                sudo tailscale set --exit-node=\"\"
              else if test -n \"$choice\"
                sudo tailscale set --exit-node=\"$choice\" --exit-node-allow-lan-access
              end
              pkill -RTMIN+14 waybar
            '";
            tooltip = true;
          };

          # ---- Temporal ----
          "custom/temporal" = {
            exec = "${temporal-status}/bin/temporal-status";
            return-type = "json";
            interval = 30;
            signal = 16;
            format = "{}";
            tooltip = true;
            on-click = "xdg-open https://temporal.ts.2143.me:8443";
          };

          # ---- Voxtype status ----
          "custom/voxtype" = {
            exec = "voxtype status --follow --format json";
            return-type = "json";
            format = "{}";
            tooltip = true;
          };

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
            on-click = "toggle-btop";
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
            on-click = "toggle-weather";
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

          # ---- Screen recording ----
          "custom/screenrec" = {
            exec = "screenrec status --follow";
            return-type = "json";
            format = "{}";
            tooltip = true;
            on-click = "screenrec toggle";
            on-click-right = "screenrec last";
          };

          # ---- Eww Hello World ----
          "custom/eww-hello" = {
            format = "";
            on-click = "eww open hello-world";
            on-click-right = "eww close hello-world";
            tooltip = true;
            tooltip-format = "Open eww hello-world widget";
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

