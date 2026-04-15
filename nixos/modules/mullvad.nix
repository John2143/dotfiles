{
  config,
  lib,
  pkgs,
  ...
}:
let
  historyFile = "/var/lib/mullvad-relay-history";
  lockFile = "/run/mullvad-relay-select.lock";

  commonPath = [
    config.services.mullvad-vpn.package
    pkgs.nftables
    pkgs.iproute2
    pkgs.gnugrep
    pkgs.gawk
    pkgs.coreutils
  ];

  selectRelay = pkgs.writeShellScript "mullvad-select-relay" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [
      config.services.mullvad-vpn.package
      pkgs.fping
      pkgs.gawk
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.util-linux
    ]}"

    HISTORY="${historyFile}"
    LOCK="${lockFile}"

    exec 9>"$LOCK"
    if ! flock -n 9; then
      echo "Another relay selection is running, skipping" >&2
      exit 0
    fi

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    # 1. Parse mullvad relay list -> one line per city: "cc city ip"
    mullvad relay list | awk '
      /^[A-Z].*\(/ {
        match($0, /\(([a-z]+)\)/, m)
        cc = m[1]
      }
      /^[[:space:]]+[A-Z].*\(.*\) @/ {
        match($0, /\(([a-z]+)\)/, m)
        city = m[1]
        seen = 0
      }
      /^[[:space:]]+[a-z]+-[a-z]+-wg-/ && !seen {
        match($0, /\(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, m)
        if (m[1] != "") { print cc, city, m[1]; seen = 1 }
      }
    ' > "$TMPDIR/cities.txt"

    TOTAL=$(wc -l < "$TMPDIR/cities.txt")
    if [ "$TOTAL" -eq 0 ]; then
      echo "ERROR: No cities parsed from relay list" >&2
      exit 1
    fi
    echo "Parsed $TOTAL cities" >&2

    # 2. Exclude last 5 used cities
    RECENT=""
    if [ -f "$HISTORY" ]; then
      RECENT=$(tail -5 "$HISTORY")
    fi

    while IFS=' ' read -r cc city ip; do
      if [ -z "$RECENT" ] || ! echo "$RECENT" | grep -qx "$cc $city"; then
        echo "$cc $city $ip"
      fi
    done < "$TMPDIR/cities.txt" > "$TMPDIR/candidates.txt"

    if [ ! -s "$TMPDIR/candidates.txt" ]; then
      echo "All cities recently used, resetting pool" >&2
      cp "$TMPDIR/cities.txt" "$TMPDIR/candidates.txt"
    fi

    # 3. Ping one IP per candidate city
    awk '{print $3}' "$TMPDIR/candidates.txt" \
      | fping -c1 -t1000 -q 2>&1 \
      | awk -F'[/ ]' '/min\/avg\/max/ {
          ip = $1; avg = $(NF-1)
          print ip, avg
        }' > "$TMPDIR/ping.txt" || true

    # 4. Join ping results with city data, sort by latency, pick best
    best_cc="" best_city="" best_lat=""
    if [ -s "$TMPDIR/ping.txt" ]; then
      eval "$(awk '
        NR==FNR { lat[$1]=$2; next }
        ($3 in lat) { print lat[$3], $1, $2 }
      ' "$TMPDIR/ping.txt" "$TMPDIR/candidates.txt" \
        | sort -n \
        | head -1 \
        | awk '{ printf "best_lat=%s best_cc=%s best_city=%s\n", $1, $2, $3 }'
      )"
    fi

    # Soft fallback: if no pings succeeded, pick the first candidate
    if [ -z "$best_cc" ]; then
      echo "No ping responses, falling back to first candidate" >&2
      eval "$(head -1 "$TMPDIR/candidates.txt" \
        | awk '{ printf "best_cc=%s best_city=%s\n", $1, $2 }')"
      best_lat="n/a"
    fi

    if [ -z "$best_cc" ]; then
      echo "ERROR: Could not determine a relay" >&2
      exit 1
    fi

    # 5. Apply and persist
    echo "Selected: $best_cc $best_city (rtt=$best_lat ms)" >&2
    mullvad relay set location "$best_cc" "$best_city"

    echo "$best_cc $best_city" >> "$HISTORY"
    tail -20 "$HISTORY" > "$TMPDIR/hist_trim"
    mv "$TMPDIR/hist_trim" "$HISTORY"
  '';

  applyBypass = pkgs.writeShellScript "mullvad-apply-bypass" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [
      pkgs.nftables
      pkgs.iproute2
      pkgs.gawk
      pkgs.gnugrep
    ]}"

    # --- Inject Tailscale route into Mullvad's own routing table ---
    MULLVAD_RT=$(ip rule show \
      | awk '/0x6d6f6c65/{print $NF; exit}')
    if [ -n "$MULLVAD_RT" ]; then
      ip route replace 100.64.0.0/10 dev tailscale0 table "$MULLVAD_RT"
    fi
    MULLVAD_RT6=$(ip -6 rule show \
      | awk '/0x6d6f6c65/{print $NF; exit}')
    if [ -n "$MULLVAD_RT6" ]; then
      ip -6 route replace fd7a:115c:a1e0::/48 dev tailscale0 table "$MULLVAD_RT6"
    fi

    # --- Tailscale bypass for Mullvad's nftables kill-switch ---
    MULLVAD_TABLE=$(nft list tables inet 2>/dev/null \
      | awk 'tolower($0) ~ /mullvad/{print $3; exit}')
    [ -z "$MULLVAD_TABLE" ] && exit 0

    for chain in input output forward; do
      if ! nft list chain inet "$MULLVAD_TABLE" "$chain" 2>/dev/null \
           | grep -q 'tailscale0'; then
        nft insert rule inet "$MULLVAD_TABLE" "$chain" \
          oifname "tailscale0" accept 2>/dev/null || true
        nft insert rule inet "$MULLVAD_TABLE" "$chain" \
          iifname "tailscale0" accept 2>/dev/null || true
      fi
    done

    if ! nft list chain inet "$MULLVAD_TABLE" output 2>/dev/null \
         | grep -q '0x80000'; then
      nft insert rule inet "$MULLVAD_TABLE" output \
        meta mark \& 0x80000 == 0x80000 accept 2>/dev/null || true
    fi
  '';
in
{
  services.mullvad-vpn.enable = true;

  services.tailscale.useRoutingFeatures = "both";

  networking.firewall = {
    enable = lib.mkForce true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    extraCommands = ''
      iptables -t nat -A POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE
    '';
    extraStopCommands = ''
      iptables -t nat -D POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE || true
    '';
  };

  systemd.services.mullvad-auto-connect = {
    description = "Auto-configure and connect Mullvad VPN";
    after = [
      "mullvad-daemon.service"
      "tailscaled.service"
    ];
    requires = [ "mullvad-daemon.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = commonPath ++ [
      pkgs.procps
      pkgs.fping
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mullvad lan set allow
      mullvad auto-connect set on
      mullvad tunnel set ipv6 on
      mullvad tunnel set quantum-resistant on

      TSPID=$(pgrep tailscaled || true)
      if [ -n "$TSPID" ]; then
        mullvad split-tunnel pid add "$TSPID" 2>/dev/null ||
          mullvad split-tunnel add "$TSPID" 2>/dev/null || true
      fi

      # Clean stale ip rules from previous runs so Mullvad doesn't
      # keep leapfrogging them with lower priority numbers.
      while ip rule del to 100.64.0.0/10 lookup 52 2>/dev/null; do :; done
      while ip -6 rule del to fd7a:115c:a1e0::/48 lookup 52 2>/dev/null; do :; done
      ip rule del fwmark 0x40000/0x40000 table 200 2>/dev/null || true
      ip route flush table 200 2>/dev/null || true

      ${selectRelay}

      mullvad connect --wait

      ${applyBypass}
    '';
  };

  systemd.services.mullvad-rotate-relay = {
    description = "Rotate Mullvad relay to a low-latency city";
    after = [
      "mullvad-daemon.service"
      "network-online.target"
      "mullvad-auto-connect.service"
    ];
    wants = [ "network-online.target" ];
    path = commonPath ++ [
      pkgs.fping
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${selectRelay}
      mullvad reconnect --wait
      ${applyBypass}
    '';
  };

  systemd.timers.mullvad-rotate-relay = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "15min";
      RandomizedDelaySec = "90s";
      Persistent = true;
    };
  };

  # Safety net: re-apply bypass rules at a low frequency in case
  # something other than rotation disturbs Mullvad's state.
  systemd.services.mullvad-tailscale-keepalive = {
    description = "Re-apply Tailscale bypass rules for Mullvad";
    after = [ "mullvad-auto-connect.service" ];
    wants = [ "mullvad-auto-connect.service" ];
    path = commonPath;
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${applyBypass}
    '';
  };

  systemd.timers.mullvad-tailscale-keepalive = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "10min";
    };
  };

  systemd.services.tailscale-exit-node = {
    description = "Advertise Tailscale exit node";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.tailscale ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      sleep 5
      tailscale set --advertise-exit-node
    '';
  };
}
