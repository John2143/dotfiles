{
  pkgs,
  compName,
  config,
  osConfig,
  lib,
  ...
}: let
  # Waybar re-runs every custom module declared with `signal = n` when it gets
  # real-time signal n (SIGRTMIN plus n). Only the signals sent from this file
  # are named here.
  sig = {
    vast = 9;
    media = 12;
    tailscale = 14;
  };
  # pidof rather than `pkill waybar`: the pattern form also matches
  # vast-waybar-status and waybar-popup, and an unhandled real-time signal
  # terminates them.
  refresh = n: "${pkgs.procps}/bin/pidof -x waybar | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -s RTMIN+${toString n}";
  isDesk = builtins.elem compName ["arch" "office"];
  # Copy the date and time; shared by the clock and the date it reveals.
  copy-date = "fish -c 'date +\"%A, %e %B %Y — %H:%M:%S\" | wl-copy; notify-send \"Copied\" (wl-paste)'";
  media-player = pkgs.writeShellApplication {
    name = "media-player";
    runtimeInputs = with pkgs; [coreutils findutils gawk gnugrep gnused hyprland jq playerctl procps pulseaudio];
    text = ''
      players=$(playerctl --list-all 2>/dev/null || true)

      is_player() {
        printf '%s\n' "$players" | grep -qxF -- "$1"
      }

      # The player pinned in the eww media picker, if it is still running. A pin
      # that outlived its player is dropped, otherwise clicks and scrolls keep
      # targeting something that is gone.
      selected_player() {
        local sel
        [ -f /tmp/media-player-selected ] || return 0
        sel=$(cat /tmp/media-player-selected)
        if is_player "$sel"; then
          printf '%s\n' "$sel"
        else
          rm -f /tmp/media-player-selected
        fi
      }

      # With nothing pinned: a playing non-browser, else a paused non-browser,
      # else a playing browser, else the first player. The browser list is the
      # same Firefox-family set the tab listing below selects on.
      auto_player() {
        local best="" browser="" p s
        for p in $players; do
          s=$(playerctl --player="$p" status 2>/dev/null || true)
          case "$p" in
            firefox*|chromium*|chrome*|Floorp*|librewolf*|zen*)
              if [ "$s" = Playing ]; then browser="$p"; fi
              continue
              ;;
          esac
          if [ "$s" = Playing ]; then
            best="$p"
            break
          elif [ "$s" = Paused ] && [ -z "$best" ]; then
            best="$p"
          fi
        done
        if [ -z "$best" ]; then best="$browser"; fi
        if [ -z "$best" ]; then best=$(printf '%s\n' "$players" | head -n 1 || true); fi
        printf '%s\n' "$best"
      }

      # What a click or scroll acts on: the pin, else the player the bar is
      # showing (written by `status`), else a fresh pick.
      target_player() {
        local p
        p=$(selected_player)
        if [ -z "$p" ] && [ -f /tmp/media-player-active ]; then
          p=$(cat /tmp/media-player-active)
          if ! is_player "$p"; then p=""; fi
        fi
        if [ -z "$p" ]; then p=$(auto_player); fi
        printf '%s\n' "$p"
      }

      refresh_bar() {
        ${refresh sig.media} 2>/dev/null || true
      }

      # hyprctl exits 0 even when the selector matches nothing, so the reply is
      # what tells a hit from a miss.
      focus_class() {
        ! hyprctl dispatch "hl.dsp.focus({ window = 'class:^($1)$' })" 2>&1 | grep -q 'not found'
      }

      status() {
        # Icons: ▶ (playing), ⏸ (paused), ♫ (no player), ■ (stopped in tooltip)

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
        # The same Firefox-family predicate selects rows in the eww media picker
        # (media-picker-data in nixos/modules/eww.nix) - change both together.
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

        best=$(selected_player)
        if [ -z "$best" ]; then best=$(auto_player); fi
        best_status=$(playerctl --player="$best" status 2>/dev/null || true)

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
      }

      case "''${1:-status}" in
        status)
          # Waybar drops a module whose output is not JSON, so a failed run is
          # replaced by a neutral pill instead.
          out=$("$0" raw-status 2>/dev/null || true)
          if jq -e . >/dev/null 2>&1 <<<"$out"; then
            printf '%s\n' "$out"
          else
            echo '{"text":"♫","class":"stopped","tooltip":""}'
          fi
          ;;
        raw-status) status ;;
        toggle)
          [ -n "$players" ] || exit 0
          playerctl --player="$(target_player)" play-pause
          refresh_bar
          ;;
        volume)
          [ -n "$players" ] || exit 0
          playerctl --player="$(target_player)" volume "$2"
          refresh_bar
          ;;
        focus)
          [ -n "$players" ] || exit 0
          player=$(target_player)
          app=''${player%%.*}
          focus_class "$app" || focus_class "''${app^}" || true
          ;;
        *)
          printf 'usage: media-player {status|toggle|volume <delta>|focus}\n' >&2
          exit 2
          ;;
      esac
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
    runtimeInputs = with pkgs; [pulseaudio gnugrep];
    text = ''
      # grep reads the whole list (no -q): under pipefail an early exit would
      # SIGPIPE pactl and turn a match into a failure.
      if pactl list sources 2>/dev/null | grep "State: RUNNING" >/dev/null; then
        echo '{"text": "●", "class": "recording", "tooltip": "An application is currently using your microphone."}'
      else
        echo '{"text": "", "class": "", "tooltip": ""}'
      fi
    '';
  };

  autoclicker = "${pkgs.autoclicker}/bin/autoclicker";

  tailscale-status = pkgs.writeShellApplication {
    name = "tailscale-status";
    runtimeInputs = with pkgs; [tailscale jq coreutils gawk];
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

  tailscale-exit-node = pkgs.writeShellApplication {
    name = "tailscale-exit-node";
    runtimeInputs = with pkgs; [tailscale jq wofi libnotify];
    text = ''
      nodes=$(tailscale status --json | jq -r '.Peer[] | select(.ExitNodeOption == true) | .DNSName | rtrimstr(".")' 2>/dev/null || true)
      if [ -z "$nodes" ]; then
        notify-send "Tailscale" "No exit node candidates found"
        exit 0
      fi
      choice=$(printf 'None\n%s\n' "$nodes" | wofi --dmenu -p "Exit Node" -i 2>/dev/null || true)
      # The setuid wrapper, by path: the bar's PATH only has the plain sudo binary.
      if [ "$choice" = None ]; then
        /run/wrappers/bin/sudo tailscale set --exit-node=
      elif [ -n "$choice" ]; then
        /run/wrappers/bin/sudo tailscale set --exit-node="$choice" --exit-node-allow-lan-access
      fi
      ${refresh sig.tailscale} 2>/dev/null || true
    '';
  };
  # iPad second display helper. Built from the same expression as
  # modules/ipad-display.nix, so no overlay is needed here (this module also
  # loads on hosts that never import shared-configuration.nix).
  ipad-display = pkgs.callPackage ../packages/ipad-display.nix { };
  # Bar read-out and click target for the Deskflow server. The wire interfaces
  # come from the host's macbook-link module; hosts without it have none.
  deskflow-ctl = pkgs.callPackage ../packages/deskflow-ctl.nix {
    wireIfaces = osConfig.services.macbookLink.interfaces or [];
  };
  temporal-status = pkgs.writeShellApplication {
    name = "temporal-status";
    runtimeInputs = with pkgs; [bash coreutils jq];
    text = ''
      addr=192.168.6.20:7233
      if timeout 1 bash -c "exec 3<>/dev/tcp/''${addr%:*}/''${addr#*:}" 2>/dev/null; then
        jq -nc --arg a "$addr" '{text: "T", class: "connected", tooltip: ("Temporal: connected (" + $a + ")")}'
      else
        jq -nc --arg a "$addr" '{text: "T", class: "disconnected", tooltip: ("Temporal: unreachable (" + $a + ")")}'
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
    # The palette lives in ~/.local/state/theme/current/waybar.css (written by
    # theme-switch); style.css keeps the layout rules only.
    style =
      "@import url(\"file://${config.xdg.stateHome}/theme/current/waybar.css\");\n"
      + builtins.readFile ../../.config/waybar/style.css;
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
          modules-left =
            [
              "hyprland/workspaces"
              "custom/newworkspace"
            ]
            # Bluetooth sits ahead of the window title: the title's width
            # changes with every window, so anything after it would drift.
            ++ (lib.optionals (osConfig.hardware.bluetooth.enable or false) [
              "bluetooth"
            ])
            ++ [
              "hyprland/window"
            ];

          # ---- Center zone ----
          modules-center = [
            "custom/media"
          ];

          # ---- Right zone ----
          # The iPad and Deskflow widgets only make sense where those modules
          # are imported (arch, office); elsewhere they would sit there inert.
          modules-right =
            [
              "custom/privacy"
              "custom/screenrec"
            ]
            ++ (lib.optionals isDesk [
              "custom/ipad"
            ])
            ++ [
              "custom/tailscale"
            ]
            ++ (lib.optionals isDesk [
              "custom/deskflow"
            ])
            ++ [
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
              "custom/theme"
              "custom/eww-hello"
              "battery"
              "custom/autoclicker"
              "tray"
              "pulseaudio"
            ];

          # ======== Module Configurations ========

          # ---- Workspaces ----
          "hyprland/workspaces" = let
            # The fixed workspaces and the monitor each belongs to are declared once, as
            # Hyprland workspace rules in nixos/home.nix. Read them from there instead of
            # repeating the table; rules for any other output (the iPad's MOONLIGHT) are
            # left out.
            hypr = config.wayland.windowManager.hyprland.settings;
            outputs = {
              MONITOR_LEFT = hypr.MONITOR_LEFT._var;
              MONITOR_RIGHT = hypr.MONITOR_RIGHT._var;
            };
            fixed = builtins.filter (r: builtins.hasAttr (r.monitor.expr or "") outputs) hypr.workspace_rule;
            label = name: ws-icons.${name} or name;
          in {
            # Taskbar icons on the workspace buttons are off: with {windows} in
            # the format Waybar reads workspace-taskbar, but the icons it draws
            # are empty slots here (no matching icon in the active theme) and
            # they only expand while the button itself is hovered, so the
            # pointer leaves the button as soon as it reaches an icon. The
            # workspace-taskbar block below and the CSS that styles it stay, so
            # turning them back on is one line.
            format = "{icon}";
            # Waybar's stand-in for a workspace that does not exist yet has to be keyed
            # by id: a name key ("A1") is parsed as a named workspace and never merges
            # with the live numbered one, which leaves two buttons. The stand-in then
            # only knows the id, so format-icons carries the label for it.
            format-icons =
              ws-icons
              // lib.listToAttrs (map (r: lib.nameValuePair r.workspace (label r.default_name)) fixed);
            tooltip = true;
            "workspace-taskbar" = {
              enable = true;
              "update-active-window" = true;
              "format" = "{icon}";
              "icon-size" = 24;
              # {address} already carries the 0x prefix. Lua form: the legacy
              # `dispatch focuswindow` syntax is rejected by a Lua-configured Hyprland.
              "on-click-window" = "hyprctl dispatch \"hl.dsp.focus({ window = 'address:{address}' })\"";
              "ignore-list" = ["^xwaylandvideobridge$"];
            };
            "persistent-workspaces" =
              lib.listToAttrs (map (r: lib.nameValuePair r.workspace [outputs.${r.monitor.expr}]) fixed);
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
            on-click-right = copy-date;
            on-click = "toggle-calendar";
          };

          # ---- Clock Date (hidden until hover) ----
          "custom/clock-date" = {
            exec = "${pkgs.coreutils}/bin/date '+%A, %e %B %Y'";
            interval = 10;
            on-click-right = copy-date;
          };

          # ---- Media Player (center) ----
          "custom/media" = {
            exec = "${media-player}/bin/media-player status";
            return-type = "json";
            interval = 2;
            signal = sig.media;
            escape = true;
            format = "{}";
            on-click = "${media-player}/bin/media-player toggle";
            on-click-right = "media-picker-toggle";
            on-click-backward = "playerctl --all-players previous; ${refresh sig.media}";
            on-click-forward = "playerctl --all-players next; ${refresh sig.media}";
            on-click-middle = "${media-player}/bin/media-player focus";
            on-scroll-up = "${media-player}/bin/media-player volume 0.05+";
            on-scroll-down = "${media-player}/bin/media-player volume 0.05-";
          };

          # ---- iPad second display ----
          # The output only exists while streaming (modules/ipad-display.nix).
          # Left-click is the repair path: drop a stale output, restart Sunshine.
          "custom/ipad" = {
            exec = "${ipad-display}/bin/ipad-display status --waybar";
            return-type = "json";
            interval = 5;
            format = "{}";
            tooltip = true;
            on-click = "${ipad-display}/bin/ipad-display recover";
            on-click-right = "${ipad-display}/bin/ipad-display create";
          };

          # ---- Tailscale VPN ----
          "custom/tailscale" = {
            exec = "${tailscale-status}/bin/tailscale-status";
            return-type = "json";
            interval = 20;
            signal = sig.tailscale;
            format = "{}";
            on-click = "eww open tailscale || eww close tailscale";
            on-click-right = "${tailscale-exit-node}/bin/tailscale-exit-node";
            tooltip = true;
          };

          # ---- Deskflow server ----
          "custom/deskflow" = {
            exec = "${deskflow-ctl}/bin/deskflow-ctl status";
            return-type = "json";
            interval = 2;
            escape = true;
            format = "{}";
            tooltip = true;
            on-click = "${deskflow-ctl}/bin/deskflow-ctl toggle";
          };

          # ---- Temporal ----
          "custom/temporal" = {
            exec = "${temporal-status}/bin/temporal-status";
            return-type = "json";
            interval = 30;
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
            # CPU package. thermal_zone indexes differ per board (zone 0 is acpitz on
            # office, the chipset on arch); the coretemp path is the same on both. Where
            # it is missing Waybar falls back to thermal zone 0.
            hwmon-path-abs = "/sys/devices/platform/coretemp.0/hwmon";
            input-filename = "temp1_input";
            critical-threshold = 90;
            interval = 1;
            format = "  {temperatureC}°";
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
            interval = 5;
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

          # ---- Theme toggle ----
          "custom/theme" = {
            exec = "theme-switch status";
            return-type = "json";
            interval = "once";
            format = "{}";
            on-click = "theme-switch toggle";
            tooltip = true;
          };

          "custom/vast" = {
            exec = "vast-waybar-status";
            return-type = "json";
            interval = 60;
            signal = sig.vast;
            format = "{}";
            tooltip = true;
            on-click = "rm -f /tmp/vast-waybar-status.json && ${refresh sig.vast}";
          };
          # `signal` + no `interval` makes Waybar run the command once and wait for it to
          # exit; `autoclicker watch` never exits, so the module never rendered. A long-lived
          # exec must instead be declared with `restart-interval` only.
          "custom/autoclicker" = {
            exec = "${autoclicker} watch";
            return-type = "json";
            restart-interval = 2;
            format = "{}";
            tooltip = true;
            on-click = "${autoclicker} toggle";
            on-click-middle = "${autoclicker} cycle";
            on-click-right = "autoclicker-menu-toggle";
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
            on-click = "fish -c '${config.home.homeDirectory}/.config/polybar/scripts/sinks.fish scarlett'";
            on-click-middle = "fish -c '${config.home.homeDirectory}/.config/polybar/scripts/sinks.fish bluetooth'";
            on-click-right = "pavucontrol";
          };

          # ---- System Tray ----
          tray = {
            "icon-size" = 18;
            spacing = 8;
          };
        }
        // lib.optionalAttrs (osConfig.hardware.bluetooth.enable or false) {
          # ---- Bluetooth ----
          # Built-in module: it watches org.bluez over D-Bus, so the pill updates
          # on property changes instead of polling. Icon only on the bar — the
          # state is the colour (style.css) and the detail is in the tooltip.
          bluetooth =
            {
              format = "{icon}";
              format-icons = {
                on = "󰂯";
                off = "󰂲";
                disabled = "󰂲";
                connected = "󰂱";
              };
              tooltip = true;
              tooltip-format = "{controller_alias}\n{controller_address}\n\nno device connected";
              tooltip-format-connected = "{controller_alias}\n{controller_address}\n\n{device_enumerate}";
              tooltip-format-enumerate-connected = "• {device_alias}\n  {device_address}";
              # blueferry runs bluetoothd with -E, so the iPhone's GATT battery
              # (org.bluez.Battery1) reaches this line.
              tooltip-format-enumerate-connected-battery = "• {device_alias} — {device_battery_percentage}%\n  {device_address}";
              on-click = "blueman-manager";
              # Left-click manages, right-click flips the adapter's power. The
              # state is read first because `bluetoothctl power` takes an
              # argument, not a toggle.
              on-click-right = "bluetoothctl power \"$(bluetoothctl show | grep -q 'Powered: yes' && echo off || echo on)\"";
            }
            // lib.optionalAttrs (compName == "arch") {
              # Two adapters stay powered on arch (hci0 "arch #1", hci1 "arch").
              # Unpinned, Waybar takes whichever controller the ObjectManager
              # lists first (bluetooth.cpp findCurController), and every paired
              # device lives on hci0, so name it.
              controller = "arch #1";
            };
        }
        // lib.optionalAttrs (compName == "arch") {
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

