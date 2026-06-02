{ pkgs, ... }:
let
  ewwDir = ../../eww;

  tailscale-eww-poll = pkgs.writeShellApplication {
    name = "tailscale-eww-poll";
    runtimeInputs = with pkgs; [ tailscale jq coreutils ];
    text = ''
      output=$(tailscale status --json 2>/dev/null) || {
        echo '{"state_class":"disconnected","state_icon":"","state_label":"Stopped","tailnet":"","self_name":"","self_ip":"","self_online":"false","exit_node_name":"None","exit_node_ip":"","exit_node_active":"false","peers_online":0,"peers_total":0,"peers_exit_count":0,"peers_exit_nodes_text":"","peers_text":""}'
        exit 0
      }

      echo "$output" | jq -c '
      {
        state_class: (
          if .BackendState == "NeedsLogin" or .BackendState == "NeedsMachineAuth" then "needs-login"
          elif .BackendState == "Running" then "connected"
          else "disconnected"
          end
        ),
        state_icon: (
          if .BackendState == "NeedsLogin" or .BackendState == "NeedsMachineAuth" then ""
          elif .BackendState == "Running" then ""
          else ""
          end
        ),
        state_label: (
          if .BackendState == "NeedsLogin" then "Needs Login"
          elif .BackendState == "NeedsMachineAuth" then "Needs Machine Auth"
          elif .BackendState == "Running" then "Connected"
          else .BackendState
          end
        ),
        tailnet: (.CurrentTailnet.Name // ""),
        self_name: (.Self.HostName // ""),
        self_ip: (.Self.TailscaleIPs[0] // ""),
        self_online: (if .Self.Online then "true" else "false" end),
        exit_node_name: (
          if (.Self.ExitNode // "") != "" then
            "Active: \(.Peer[.Self.ExitNode].HostName // "?")"
          else
            "None"
          end
        ),
        exit_node_ip: (
          if (.Self.ExitNode // "") != "" then
            (.Peer[.Self.ExitNode].TailscaleIPs[0] // "")
          else
            ""
          end
        ),
        exit_node_active: (
          if (.Self.ExitNode // "") != "" then
            "true"
          else
            "false"
          end
        ),
        peers_online: ([.Peer[] | select(.Online)] | length),
        peers_total: ([.Peer[]] | length),
        peers_exit_count: ([.Peer[] | select(.ExitNodeOption)] | length),
        peers_exit_nodes_text: (
          [.Peer[] | select(.ExitNodeOption) | .HostName] | sort | join(", ")
        ),
        peers_text: (
          [.Peer | to_entries[] | "\(.value.HostName)\t\(.value.TailscaleIPs[0] // "?")\t\(if .value.Online then "yes" else " no" end)"] | sort | join("\n")
        )
      }
      '
    '';
  };
in {
  programs.eww = {
    enable = true;
    yuckConfig = builtins.readFile "${ewwDir}/eww.yuck";
    scssConfig = builtins.readFile "${ewwDir}/eww.scss";
    systemd.enable = true;
  };

  home.packages = [ tailscale-eww-poll ];
}
