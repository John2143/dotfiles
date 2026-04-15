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

  watchdogFailFile = "/run/mullvad-watchdog-first-failure";

  connectivityWatchdog = pkgs.writeShellScript "mullvad-connectivity-watchdog" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [
      config.services.mullvad-vpn.package
      pkgs.iputils
      pkgs.tailscale
      pkgs.jq
      pkgs.iproute2
      pkgs.nftables
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.systemd
      pkgs.networkmanager
      pkgs.util-linux
    ]}"

    FAIL_FILE="${watchdogFailFile}"

    log() { echo "watchdog: $*"; }

    reset_failure() {
      rm -f "$FAIL_FILE"
    }

    check_reboot_timeout() {
      if [ ! -f "$FAIL_FILE" ]; then
        date +%s > "$FAIL_FILE"
      fi
      ELAPSED=$(( $(date +%s) - $(cat "$FAIL_FILE") ))
      log "Sustained failure for ''${ELAPSED}s (reboot at 180s)"
      if [ "$ELAPSED" -ge 180 ]; then
        log "CRITICAL: 3 minutes of sustained failure -- rebooting"
        systemctl reboot
      fi
    }

    quick_ping_check() {
      FAIL=0
      for ip in 1.1.1.1 1.0.0.1 8.8.8.8; do
        ping -c1 -W3 "$ip" &>/dev/null || FAIL=$((FAIL+1))
      done
      echo "$FAIL"
    }

    # Skip if relay rotation is in progress to avoid false positives
    if systemctl is-active --quiet mullvad-rotate-relay.service 2>/dev/null; then
      log "Relay rotation in progress, skipping check"
      exit 0
    fi

    # ── Health check ──────────────────────────────────────────────
    PING_FAIL=$(quick_ping_check)
    TS_ONLINE=$(tailscale status --json 2>/dev/null | jq -r '.Self.Online // false') || TS_ONLINE="false"

    if [ "$PING_FAIL" -lt 2 ] && [ "$TS_ONLINE" = "true" ]; then
      reset_failure
      exit 0
    fi

    log "Unhealthy: $PING_FAIL/3 pings failed, tailscale_online=$TS_ONLINE"

    # ── Diagnostics (all logged for post-mortem) ──────────────────
    MULLVAD_STATUS=$(mullvad status 2>&1) || true
    log "mullvad status: $MULLVAD_STATUS"

    END0_STATE=$(ip -j link show end0 2>/dev/null | jq -r '.[0].operstate // "UNKNOWN"') || END0_STATE="MISSING"
    WLAN0_STATE=$(ip -j link show wlan0 2>/dev/null | jq -r '.[0].operstate // "UNKNOWN"') || WLAN0_STATE="MISSING"
    log "interfaces: end0=$END0_STATE wlan0=$WLAN0_STATE"

    END0_IP=$(ip -j addr show end0 2>/dev/null | jq -r '.[0].addr_info[]? | select(.family=="inet") | .local // empty' | head -1) || END0_IP=""
    WLAN0_IP=$(ip -j addr show wlan0 2>/dev/null | jq -r '.[0].addr_info[]? | select(.family=="inet") | .local // empty' | head -1) || WLAN0_IP=""
    log "IPs: end0=$END0_IP wlan0=$WLAN0_IP"

    GATEWAY=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}') || GATEWAY=""
    GW_IFACE=$(ip route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}') || GW_IFACE=""
    log "gateway=$GATEWAY via $GW_IFACE"

    GW_REACHABLE="false"
    if [ -n "$GATEWAY" ]; then
      ping -c1 -W2 "$GATEWAY" &>/dev/null && GW_REACHABLE="true"
    fi
    log "gateway_reachable=$GW_REACHABLE"

    # ── Recovery ladder ───────────────────────────────────────────

    # Step 1: Mullvad disconnected → reconnect + bypass
    if echo "$MULLVAD_STATUS" | grep -qi "disconnected\|error"; then
      log "Step 1: Mullvad disconnected, reconnecting"
      mullvad connect --wait || true
      ${applyBypass} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after mullvad reconnect"
        reset_failure
        exit 0
      fi
    fi

    # Step 2: Mullvad connected but pings fail → bad relay, force switch
    if echo "$MULLVAD_STATUS" | grep -qi "connected"; then
      log "Step 2: Mullvad connected but no internet, forcing relay switch"
      mullvad reconnect --wait || true
      ${applyBypass} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after relay switch"
        reset_failure
        exit 0
      fi
    fi

    # Step 3: Bring up interfaces if DOWN
    IFACE_FIXED="false"
    if [ "$END0_STATE" != "UP" ]; then
      log "Step 3: end0 is $END0_STATE, attempting to bring up"
      nmcli device connect end0 2>/dev/null || true
      IFACE_FIXED="true"
    fi
    if [ "$WLAN0_STATE" != "UP" ]; then
      log "Step 3: wlan0 is $WLAN0_STATE, attempting to bring up"
      nmcli device connect wlan0 2>/dev/null || true
      IFACE_FIXED="true"
    fi
    if [ "$IFACE_FIXED" = "true" ]; then
      sleep 5
      mullvad connect --wait || true
      ${applyBypass} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after bringing up interfaces"
        reset_failure
        exit 0
      fi
    fi

    # Step 4: Gateway unreachable → restart NetworkManager
    if [ "$GW_REACHABLE" = "false" ]; then
      log "Step 4: Gateway unreachable, restarting NetworkManager"
      systemctl restart NetworkManager || true
      sleep 10
      mullvad connect --wait || true
      ${applyBypass} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after NetworkManager restart"
        reset_failure
        exit 0
      fi
    fi

    # Step 5: Nuclear VPN reset
    log "Step 5: Restarting mullvad-daemon"
    systemctl restart mullvad-daemon || true
    sleep 10
    mullvad connect --wait || true
    ${applyBypass} || true
    sleep 3
    NEW_FAIL=$(quick_ping_check)
    if [ "$NEW_FAIL" -lt 2 ]; then
      log "Recovered after mullvad-daemon restart"
      reset_failure
      exit 0
    fi

    # Step 6: Restart tailscaled
    if [ "$TS_ONLINE" != "true" ]; then
      log "Step 6: Restarting tailscaled"
      systemctl restart tailscaled || true
      sleep 5
      tailscale set --advertise-exit-node || true
    fi

    # Still broken — record failure and check reboot timeout
    log "All recovery steps exhausted, waiting for next cycle"
    check_reboot_timeout
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

  systemd.services.mullvad-connectivity-watchdog = {
    description = "Connectivity watchdog: diagnose and recover internet/VPN failures";
    after = [
      "mullvad-auto-connect.service"
      "tailscaled.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${connectivityWatchdog}
    '';
  };

  systemd.timers.mullvad-connectivity-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "30s";
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
