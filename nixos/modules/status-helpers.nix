# Status and action helpers for the Noctalia bar.
#
# The Waybar modules and the eww widgets each carried their own copy of the
# shell that fed them, so the bar, the popups and the keybinds were three
# implementations of the same job. This module keeps one binary per job on PATH:
# the Luau bar plugins run them through `runAsync`/`runStream`, and the keybinds
# and context menus call them directly.
#
# Conventions:
#   * scripts named `*-status` print a single Waybar-shaped JSON object
#     (`{text, class, tooltip}`); the plugin maps those onto its own fields.
#   * `noctalia msg plugin john/dotfiles-bar:<entry> all refresh` replaces the
#     real-time signals the Waybar helpers used to send (SIGRTMIN+n): a plugin
#     widget only re-runs its command when the shell tells it to.
#   * nothing here depends on eww, waybar or wofi any more. `noctalia` itself is
#     taken from the session PATH rather than from runtimeInputs, so these
#     helpers still evaluate on hosts where the shell package is not wired in,
#     and a missing shell degrades to "no refresh" instead of "command not
#     found" noise in a widget.
{
  pkgs,
  compName,
  osConfig,
  lib,
  ...
}: let
  # Ask one Noctalia plugin entry to re-read whatever command feeds it.
  refreshPlugin = entry: "noctalia msg plugin john/dotfiles-bar:${entry} all refresh >/dev/null 2>&1 || true";

  isDesk = builtins.elem compName ["arch" "office"];

  # Copy the date and time; the clock widget's right-click action runs this.
  copy-date = pkgs.writeShellApplication {
    name = "copy-date";
    runtimeInputs = with pkgs; [coreutils wl-clipboard libnotify];
    text = ''
      date +"%A, %e %B %Y — %H:%M:%S" | wl-copy
      notify-send "Copied" "$(wl-paste)"
    '';
  };

  media-player = pkgs.writeShellApplication {
    name = "media-player";
    runtimeInputs = with pkgs; [coreutils findutils gawk gnugrep gnused hyprland jq playerctl procps pulseaudio];
    text = ''
      players=$(playerctl --list-all 2>/dev/null || true)

      is_player() {
        printf '%s\n' "$players" | grep -qxF -- "$1"
      }

      # The player pinned in the media picker, if it is still running. A pin
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
        ${refreshPlugin "media"}
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
        # The same Firefox-family predicate selects rows in the media picker
        # (media-picker-data below) - change both together.
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
          # A widget that prints non-JSON is worse than a neutral pill, so a
          # failed run is replaced by one instead of an error string.
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

  media-picker-data = pkgs.writeShellApplication {
    name = "media-picker-data";
    runtimeInputs = with pkgs; [playerctl pulseaudio jq coreutils];
    text = ''
      case "''${1:-}" in
        players)
          selected=""
          if [ -f /tmp/media-player-selected ]; then
            selected=$(cat /tmp/media-player-selected || true)
          fi
          if [ -z "$selected" ] && [ -f /tmp/media-player-active ]; then
            selected=$(cat /tmp/media-player-active || true)
          fi
          # Tab-separated: song titles legitimately contain "|", which would
          # otherwise split into extra fields and break the volume column.
          sep=$'\t'
          raw=$(playerctl --all-players metadata \
            --format "{{playerName}}''${sep}{{status}}''${sep}{{artist}}''${sep}{{title}}''${sep}{{volume}}" 2>/dev/null || true)
          printf '%s\n' "$raw" | jq -c -R -s --arg sel "$selected" '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | map({
                id: .[0],
                status: (.[1] // ""),
                name: ((.[0] | split(".") | .[0]) | ((.[0:1] | ascii_upcase) + .[1:])),
                detail: ([.[2], .[3]] | map(select(. != null and . != "")) | join(" — ")),
                volume: (((((.[4] // "0") | (if . == "" then 0 else tonumber end)) * 100) | floor) | tostring),
                icon: (if (.[1] // "") == "Playing" then "▶" else "⏸" end),
                pin: (if .[0] == $sel then "◉" else "◎" end)
              })' 2>/dev/null || echo '[]'
          ;;
        tabs)
          # Firefox-family predicate kept in step with `media-player status`
          # above, which reports the same tabs for the bar. Change both or the
          # picker and the bar disagree.
          raw=$(pactl --format=json list sink-inputs 2>/dev/null || true)
          [ -n "$raw" ] || raw='[]'
          printf '%s' "$raw" | jq -c '
            [ .[]
              | . as $si
              | ($si.properties["media.name"] // "") as $n
              | select(
                  (($n | length) > 0)
                  and (($n | test("^(alsa playback|audio ?stream|playback ?stream|playback)$"; "i")) | not)
                  and (((($si.properties["application.name"] // "") + " "
                          + ($si.properties["application.process.binary"] // "") + " "
                          + ($si.properties["application.icon_name"] // ""))
                        | ascii_downcase | test("firefox|librewolf|zen|floorp")))
                )
              | {
                  index: ($si.index | tostring),
                  pid: ($si.properties["application.process.id"] // ""),
                  title: $n,
                  volume: (($si.volume // {})
                           | [ .[].value_percent | sub("%"; "") | tonumber ]
                           | if length > 0 then ((add / length | floor) | tostring) else "0" end),
                  muted: ($si.mute // false),
                  corked: ($si.corked // false),
                  state: (if ($si.corked // false) then "⏸" else "▶" end),
                  icon: (if ($si.mute // false) then "󰖁" else "󰕾" end)
                }
            ]' 2>/dev/null || echo '[]'
          ;;
        *)
          echo '[]'
          ;;
      esac
    '';
  };

  media-picker-action = pkgs.writeShellApplication {
    name = "media-picker-action";
    runtimeInputs = with pkgs; [playerctl pulseaudio jq coreutils procps];
    text = ''
      verb="''${1:-}"
      case "$verb" in
        toggle)
          playerctl --player="''${2:-}" play-pause
          ;;
        pin)
          if [ -f /tmp/media-player-selected ] && [ "$(cat /tmp/media-player-selected)" = "''${2:-}" ]; then
            rm -f /tmp/media-player-selected
          else
            printf '%s\n' "''${2:-}" > /tmp/media-player-selected
          fi
          ;;
        player-volume)
          case "''${3:-}" in
            up) playerctl --player="''${2:-}" volume 0.05+ ;;
            down) playerctl --player="''${2:-}" volume 0.05- ;;
          esac
          ;;
        tab-volume)
          case "''${3:-}" in
            up) pactl set-sink-input-volume "''${2:-}" +5% ;;
            down) pactl set-sink-input-volume "''${2:-}" -5% ;;
          esac
          ;;
        tab-mute)
          pactl set-sink-input-mute "''${2:-}" toggle
          ;;
        tab-focus)
          # The page title is attacker-controlled - it comes from a web page - so
          # it never travels through the shell command line. The row passes only
          # the numeric sink-input index and the title is looked up here.
          index="''${2:-}"
          meta=$(pactl --format=json list sink-inputs 2>/dev/null | jq -r --arg i "$index" '
            [ .[] | select((.index | tostring) == $i)
              | [ (.properties["media.name"] // ""), (.properties["application.process.id"] // "") ]
              | @tsv ] | first // ""' 2>/dev/null || true)
          title="''${meta%%$'\t'*}"
          browser_pid="''${meta##*$'\t'}"
          # A Hyprland window advertises only its active tab, so a background
          # tab has no window of its own to focus.
          addr=""
          if [ -n "$title" ]; then
            # Window titles are "<active tab title> <dash> Mozilla Firefox", so
            # compare only the prefix to stay clear of the separator.
            addr=$(hyprctl -j clients 2>/dev/null | jq -r --arg t "$title" '
              [ .[] | select(.class == "firefox" and (.title[0:($t | length)] == $t)) | .address ]
              | first // ""' 2>/dev/null || true)
          fi
          # Hyprland 0.57 dropped hyprlang, so "hyprctl dispatch focuswindow X"
          # is a Lua syntax error; focusing goes through hl.dsp.focus and the
          # snippet is evaluated with "hyprctl repl". Address and pid are
          # validated first so nothing else can be spliced into the Lua.
          if [[ "$addr" =~ ^0x[0-9a-fA-F]+$ ]]; then
            focus_lua="for _,w in ipairs(hl.get_windows()) do if w.address == '$addr' then hl.dispatch(hl.dsp.focus({window=w})) return 'ok' end end"
            hyprctl repl "$focus_lua" >/dev/null 2>&1 || true
          elif [[ "$browser_pid" =~ ^[0-9]+$ ]]; then
            # Nothing advertises that tab, so raise the browser window instead
            # of pretending the tab can be selected.
            focus_lua="for _,w in ipairs(hl.get_windows()) do if w.class == 'firefox' and w.pid == $browser_pid then hl.dispatch(hl.dsp.focus({window=w})) return 'ok' end end"
            hyprctl repl "$focus_lua" >/dev/null 2>&1 || true
          fi
          ;;
        *)
          echo "usage: media-picker-action {toggle|pin|player-volume|tab-volume|tab-mute|tab-focus} <id> [up|down]" >&2
          exit 2
          ;;
      esac
      # The panel and the bar both show this state, and a pin changes which
      # player the bar reports, so both are refreshed.
      ${refreshPlugin "media"}
      ${refreshPlugin "media-panel"}
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

  # Data blob behind the tailscale popup. The eww version pushed a dozen
  # `eww update` variables; a plugin cannot be written that way, so everything
  # arrives as one JSON object on stdout. Icons are given as \uXXXX escapes
  # (Nerd Font codepoints) so the script stays ASCII.
  tailscale-panel-data = pkgs.writeShellApplication {
    name = "tailscale-panel-data";
    runtimeInputs = with pkgs; [tailscale jq coreutils gawk];
    text = ''
      output=$(tailscale status --json 2>/dev/null) || {
        jq -nc '{
          tailnet: "", state: "Stopped", icon: "\uf1e6",
          self_name: "", self_ip: "",
          exit_name: "None", exit_ip: "",
          peers_online: 0, peers_total: 0, exit_count: 0,
          peers: []
        }'
        exit 0
      }

      # Detect exit node via debug prefs (works without sudo, unlike
      # .Self.ExitNode in JSON).
      exit_id=$(tailscale debug prefs 2>/dev/null | jq -r '.ExitNodeID // ""')
      exit_name=""
      case "$exit_id" in
        "" | "null" | "0") exit_id="" ;;
        *)
          exit_name=$(tailscale exit-node list 2>/dev/null | awk '/selected/{print $2; exit}' || true)
          ;;
      esac

      printf '%s' "$output" | jq -c --arg eid "$exit_id" --arg exit_name "$exit_name" '
        (.Peer // {}) as $peers
        | (.BackendState // "Stopped") as $bs
        | ([$peers[] | select(.ID == $eid)] | first // {}) as $exit
        | {
            tailnet: (.CurrentTailnet.Name // ""),
            state: (if $bs == "NeedsLogin" then "Needs Login"
                    elif $bs == "NeedsMachineAuth" then "Needs Machine Auth"
                    elif $bs == "Running" then "Connected"
                    else $bs end),
            icon: (if $bs == "NeedsLogin" then "\uf071"
                   elif $bs != "Running" then "\uf1e6"
                   elif $eid != "" then "\uf023"
                   else "\uf127" end),
            self_name: (.Self.HostName // ""),
            self_ip: (.Self.TailscaleIPs[0] // ""),
            exit_name: (if $eid == "" then "None"
                        elif $exit_name != "" then $exit_name
                        else ((($exit.DNSName // "") | rtrimstr(".")) as $n
                              | if $n == "" then "?" else $n end)
                        end),
            exit_ip: (if $eid != "" then ($exit.TailscaleIPs[0] // "") else "" end),
            peers_online: ([$peers[] | select(.Online // false)] | length),
            peers_total: ([$peers[]] | length),
            exit_count: ([$peers[] | select(.ExitNodeOption // false)] | length),
            peers: ([$peers[]
                     | {
                         name: (.HostName // ""),
                         ip: (.TailscaleIPs[0] // ""),
                         online: (.Online // false),
                         os: (.OS // ""),
                         exit_node: (.ExitNodeOption // false),
                         active: ((.Active // false) or (.ID == $eid))
                       }]
                    | sort_by(.name))
          }'
    '';
  };

  tailscale-toggle = pkgs.writeShellApplication {
    name = "tailscale-toggle";
    runtimeInputs = with pkgs; [tailscale jq coreutils];
    text = ''
      running=$(tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null 2>&1 && echo true || echo false)
      # The setuid wrapper, by path: a service or widget session's PATH need not
      # carry it.
      if [ "$running" = "true" ]; then
        /run/wrappers/bin/sudo tailscale down
      else
        /run/wrappers/bin/sudo tailscale up --login-server=https://net.john2143.com
      fi
      sleep 2
      ${refreshPlugin "tailscale"}
      ${refreshPlugin "tailscale-panel"}
    '';
  };

  tailscale-exit-node = pkgs.writeShellApplication {
    name = "tailscale-exit-node";
    # `noctalia` comes from PATH: the dmenu reads stdin lines and prints the
    # picked one, the same contract wofi --dmenu had.
    runtimeInputs = with pkgs; [tailscale jq coreutils libnotify];
    text = ''
      nodes=$(tailscale status --json | jq -r '.Peer[] | select(.ExitNodeOption == true) | .DNSName | rtrimstr(".")' 2>/dev/null | sort || true)
      if [ -z "$nodes" ]; then
        notify-send "Tailscale" "No exit node candidates found"
        exit 0
      fi
      choice=$(printf 'None\n%s\n' "$nodes" | noctalia dmenu -p "Exit Node" 2>/dev/null || true)
      # The setuid wrapper, by path: the bar's PATH only has the plain sudo binary.
      if [ "$choice" = None ]; then
        /run/wrappers/bin/sudo tailscale set --exit-node=
      elif [ -n "$choice" ]; then
        /run/wrappers/bin/sudo tailscale set --exit-node="$choice" --exit-node-allow-lan-access
      fi
      sleep 1
      ${refreshPlugin "tailscale"}
      ${refreshPlugin "tailscale-panel"}
    '';
  };

  # iPad second display helper. Built from the same expression as
  # modules/ipad-display.nix, so no overlay is needed here.
  ipad-display = pkgs.callPackage ../packages/ipad-display.nix {};
  # Read-out and click target for the Deskflow server. The wire interfaces come
  # from the host's macbook-link module; hosts without it have none.
  deskflow-ctl = pkgs.callPackage ../packages/deskflow-ctl.nix {
    wireIfaces = osConfig.services.macbookLink.interfaces or [];
  };
in {
  # The iPad and Deskflow helpers only mean anything where those modules are
  # imported (arch, office); elsewhere they would just sit on PATH inert.
  home.packages =
    [
      media-player
      media-picker-data
      media-picker-action
      nix-update-status
      tailscale-status
      tailscale-panel-data
      tailscale-toggle
      tailscale-exit-node
      copy-date
    ]
    ++ lib.optionals isDesk [
      ipad-display
      deskflow-ctl
    ];
}
