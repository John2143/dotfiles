{ pkgs, ... }:
let
  ewwDir = ../../eww;

  tailscale-eww-update = pkgs.writeShellApplication {
    name = "tailscale-eww-update";
    runtimeInputs = with pkgs; [ tailscale jq coreutils ];
    text = ''
      output=$(tailscale status --json 2>/dev/null) || {
        eww update \
          ts_state_icon="" \
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

      cmd=$(echo "$output" | jq -r '
        "eww update " +
          "ts_state_icon=" + (
            if .BackendState == "NeedsLogin" or .BackendState == "NeedsMachineAuth" then ""
            elif .BackendState == "Running" then ""
            else "" end | @sh
          ) + " " +
          "ts_state_label=" + (
            if .BackendState == "NeedsLogin" then "Needs Login"
            elif .BackendState == "NeedsMachineAuth" then "Needs Machine Auth"
            elif .BackendState == "Running" then "Connected"
            else .BackendState end | @sh
          ) + " " +
          "ts_tailnet=" + ((.CurrentTailnet.Name // "") | @sh) + " " +
          "ts_self_name=" + ((.Self.HostName // "") | @sh) + " " +
          "ts_self_ip=" + ((.Self.TailscaleIPs[0] // "") | @sh) + " " +
          "ts_self_online=" + ((if .Self.Online then "●" else "○" end) | @sh) + " " +
          "ts_exit_node_name=" + (
            if (.Self.ExitNode // "") != "" then
              ("Active: " + (.Peer[.Self.ExitNode].HostName // "?"))
            else
              "None"
            end | @sh
          ) + " " +
          "ts_exit_node_ip=" + (
            if (.Self.ExitNode // "") != "" then
              (.Peer[.Self.ExitNode].TailscaleIPs[0] // "")
            else
              ""
            end | @sh
          ) + " " +
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
in {
  programs.eww = {
    enable = true;
    yuckConfig = builtins.readFile "${ewwDir}/eww.yuck";
    scssConfig = builtins.readFile "${ewwDir}/eww.scss";
    systemd.enable = true;
  };

  home.packages = [ tailscale-eww-update ];
}
