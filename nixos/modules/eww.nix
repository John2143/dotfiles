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
in {
  programs.eww = {
    enable = true;
    yuckConfig = builtins.readFile "${ewwDir}/eww.yuck";
    scssConfig = builtins.readFile "${ewwDir}/eww.scss";
    systemd.enable = true;
  };

  home.packages = [ tailscale-eww-update tailscale-eww-toggle tailscale-eww-exitnode ];
}
