{ pkgs, ... }:
let
  ewwDir = ../../eww;

  tailscale-eww-update = pkgs.writeShellApplication {
    name = "tailscale-eww-update";
    runtimeInputs = with pkgs; [ tailscale jq coreutils ];
    text = ''
      output=$(tailscale status --json 2>/dev/null) || {
        eww update \
          ts_state_icon="" \
          ts_state_label="Stopped" \
          ts_tailnet="" \
          ts_self_name="" \
          ts_self_ip="" \
          ts_self_online="○" \
          ts_exit_node_name="None" \
          ts_exit_node_ip="" \
          ts_peers_online="0" \
          ts_peers_total="0" \
          ts_peers_exit_count="0" \
          ts_peers_text=""
        echo "ok"
        exit 0
      }

      # Detect exit node via debug prefs (works without sudo, unlike .Self.ExitNode in JSON)
      exit_id=$(tailscale debug prefs 2>/dev/null | jq -r '.ExitNodeID // ""')
      if [ -n "$exit_id" ] && [ "$exit_id" != "null" ] && [ "$exit_id" != "0" ]; then
        exit_name=$(tailscale exit-node list 2>/dev/null | awk '/selected/{print $2; exit}')
        exit_ip=""
        state_icon=""
        exit_label="Active: ''${exit_name:-?}"
      else
        exit_name=""
        exit_ip=""
        state_icon=""
        exit_label="None"
      fi

      cmd=$(echo "$output" | jq -r \
        --arg state_icon "$state_icon" \
        --arg exit_label "$exit_label" \
        --arg exit_ip "$exit_ip" \
        '
        def state_label:
          if .BackendState == "NeedsLogin" then "Needs Login"
          elif .BackendState == "NeedsMachineAuth" then "Needs Machine Auth"
          elif .BackendState == "Running" then "Connected"
          else .BackendState end;

        "eww update " +
          "ts_state_icon=" + ($state_icon | @sh) + " " +
          "ts_state_label=" + (state_label | @sh) + " " +
          "ts_tailnet=" + ((.CurrentTailnet.Name // "") | @sh) + " " +
          "ts_self_name=" + ((.Self.HostName // "") | @sh) + " " +
          "ts_self_ip=" + ((.Self.TailscaleIPs[0] // "") | @sh) + " " +
          "ts_self_online=" + ((if .Self.Online then "●" else "○" end) | @sh) + " " +
          "ts_exit_node_name=" + ($exit_label | @sh) + " " +
          "ts_exit_node_ip=" + ($exit_ip | @sh) + " " +
          "ts_peers_online=" + (([.Peer[] | select(.Online)] | length | tostring) | @sh) + " " +
          "ts_peers_total=" + (([.Peer[]] | length | tostring) | @sh) + " " +
          "ts_peers_exit_count=" + (([.Peer[] | select(.ExitNodeOption)] | length | tostring) | @sh) + " " +
          "ts_peers_text=" + (
            [.Peer | to_entries[]
             | "\(.value.HostName)\t\(.value.TailscaleIPs[0] // "?")\t\(if .value.Online then "yes" else " no" end)"]
            | sort | join("\n") | @sh
          )
      ')
      eval "$cmd"
      echo "ok"
    '';
  };

  tailscale-eww-toggle = pkgs.writeShellApplication {
    name = "tailscale-eww-toggle";
    runtimeInputs = with pkgs; [ tailscale jq coreutils ];
    text = ''
      running=$(tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null 2>&1 && echo true || echo false)
      if [ "$running" = "true" ]; then
        sudo tailscale down
      else
        sudo tailscale up --login-server=https://net.john2143.com
      fi
      sleep 2
      tailscale-eww-update
    '';
  };

  tailscale-eww-exitnode = pkgs.writeShellApplication {
    name = "tailscale-eww-exitnode";
    runtimeInputs = with pkgs; [ tailscale jq coreutils wofi ];
    text = ''
      nodes=$(tailscale status --json 2>/dev/null | jq -r '.Peer[] | select(.ExitNodeOption) | .DNSName | rtrimstr(".")' | sort)
      if [ -z "$nodes" ]; then
        notify-send "Tailscale" "No exit node candidates found"
        exit 0
      fi
      choice=$(printf "None\n%s" "$nodes" | wofi --dmenu -p "Exit Node" -i 2>/dev/null)
      if [ "$choice" = "None" ]; then
        sudo tailscale set --exit-node=
      elif [ -n "$choice" ]; then
        sudo tailscale set --exit-node="$choice" --exit-node-allow-lan-access
      fi
      sleep 1
      tailscale-eww-update
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
          # Firefox-family predicate kept in step with media-player-status in
          # nixos/modules/waybar.nix, which reports the same tabs for the bar.
          # Change both or the picker and the bar disagree.
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
          pidof -x waybar 2>/dev/null | xargs -r kill -46 2>/dev/null || true
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
          if [ -n "$addr" ]; then
            hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
          elif [ -n "$browser_pid" ]; then
            # Nothing advertises that tab, so raise the browser window instead
            # of pretending the tab can be selected.
            hyprctl dispatch focuswindow "pid:$browser_pid" >/dev/null 2>&1 || true
          fi
          ;;
        *)
          echo "usage: media-picker-action {toggle|pin|player-volume|tab-volume|tab-mute|tab-focus} <id> [up|down]" >&2
          exit 2
          ;;
      esac
      eww poll mp_players mp_tabs >/dev/null 2>&1 || true
    '';
  };

  media-picker-toggle = pkgs.writeShellApplication {
    name = "media-picker-toggle";
    runtimeInputs = with pkgs; [jq coreutils];
    text = ''
      cursor=$(hyprctl cursorpos -j 2>/dev/null || true)
      screen=$(hyprctl monitors -j 2>/dev/null | jq -r --arg c "$cursor" '
        ($c | fromjson? // {x: -1, y: -1}) as $cur
        | map(select(.x <= $cur.x and $cur.x < (.x + .width) and .y <= $cur.y and $cur.y < (.y + .height)))
        | if length > 0 then .[0].name else "" end' 2>/dev/null || true)

      if [ -n "$screen" ]; then
        eww open media-picker --toggle --screen "$screen"
      else
        eww open media-picker --toggle
      fi
      eww poll mp_players mp_tabs >/dev/null 2>&1 || true
    '';
  };
in {
  programs.eww = {
    enable = true;
    yuckConfig = builtins.readFile "${ewwDir}/eww.yuck";
    scssConfig = builtins.readFile "${ewwDir}/eww.scss";
    systemd.enable = true;
  };

  home.packages = [
    tailscale-eww-update
    tailscale-eww-toggle
    tailscale-eww-exitnode
    media-picker-data
    media-picker-action
    media-picker-toggle
  ];
}
