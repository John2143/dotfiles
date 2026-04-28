{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mullvad-relay;

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
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.util-linux
    ]}"

    HISTORY="${historyFile}"
    LOCK="${lockFile}"
    RELAYS="/var/cache/mullvad-vpn/relays.json"
    HOME_LAT=${toString cfg.homeLatitude}
    HOME_LON=${toString cfg.homeLongitude}
    MAX_DIST=1000

    exec 9>"$LOCK"
    if ! flock -n 9; then
      echo "Another relay selection is running, skipping" >&2
      exit 10
    fi

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    # 1. Extract cities with coordinates from relays.json
    if [ -f "$RELAYS" ]; then
      jq -r '
        .countries[] | .code as $cc | .cities[] |
        select(.relays | map(select(.hostname | test("wg"))) | length > 0) |
        "\($cc) \(.code) \(.latitude) \(.longitude)"
      ' "$RELAYS" > "$TMPDIR/all_cities.txt" 2>/dev/null || true
    fi

    if [ ! -s "$TMPDIR/all_cities.txt" ]; then
      echo "ERROR: No cities from relays.json" >&2
      exit 1
    fi

    TOTAL=$(wc -l < "$TMPDIR/all_cities.txt")
    echo "Parsed $TOTAL cities from relays.json" >&2

    # 2. Load recent history for exclusion
    RECENT_FILE="$TMPDIR/recent.txt"
    if [ -f "$HISTORY" ]; then
      tail -3 "$HISTORY" > "$RECENT_FILE"
    else
      touch "$RECENT_FILE"
    fi

    # 3. Haversine filter + history exclusion + weighted random pick
    pick_city() {
      local exclude_recent="$1"
      awk -v hlat="$HOME_LAT" -v hlon="$HOME_LON" -v maxd="$MAX_DIST" \
          -v rfile="$RECENT_FILE" -v exclude="$exclude_recent" '
        BEGIN {
          PI=3.14159265358979; D=PI/180; R=3959
          n=0; total_w=0
          srand()
          if (exclude) {
            while ((getline line < rfile) > 0) {
              if (line != "") recent[line] = 1
            }
            close(rfile)
          }
        }
        {
          cc=$1; city=$2; lat=$3; lon=$4
          dlat=(lat-hlat)*D; dlon=(lon-hlon)*D
          a=sin(dlat/2)^2 + cos(hlat*D)*cos(lat*D)*sin(dlon/2)^2
          dist=R*2*atan2(sqrt(a),sqrt(1-a))
          if (dist > maxd) next
          key = cc " " city
          if (exclude && (key in recent)) next
          n++
          w[n] = (dist < 1) ? 1000 : 1/dist
          total_w += w[n]
          cities[n] = key
          dists[n] = dist
        }
        END {
          if (n == 0) { print "NEED_RESET=1"; exit }
          r = rand() * total_w
          for (i=1; i<=n; i++) {
            r -= w[i]
            if (r <= 0 || i == n) {
              split(cities[i], p, " ")
              printf "best_cc=%s best_city=%s best_dist=%.0f\n", p[1], p[2], dists[i]
              exit
            }
          }
        }
      ' "$TMPDIR/all_cities.txt"
    }

    eval "$(pick_city 1)"

    # Fallback: if all nearby cities were recently used, reset pool
    if [ "''${NEED_RESET:-0}" = "1" ]; then
      echo "All nearby cities recently used, resetting pool" >&2
      eval "$(pick_city 0)"
    fi

    if [ -z "''${best_cc:-}" ]; then
      echo "ERROR: Could not determine a relay" >&2
      exit 1
    fi

    # 4. Apply and persist
    echo "Selected: $best_cc $best_city (dist=''${best_dist}mi)" >&2
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
    GUARD_TABLE="watchdog_leak_guard"

    log() { echo "watchdog: $*"; }

    reset_failure() {
      rm -f "$FAIL_FILE"
    }

    enable_leak_guard() {
      log "Enabling forward leak guard (blocking all forwarded traffic)"
      nft add table inet "$GUARD_TABLE" 2>/dev/null || true
      nft 'add chain inet '"$GUARD_TABLE"' forward { type filter hook forward priority -1; policy drop; }' \
        2>/dev/null || true
    }

    disable_leak_guard() {
      log "Disabling forward leak guard"
      nft delete table inet "$GUARD_TABLE" 2>/dev/null || true
    }

    check_reboot_timeout() {
      if [ ! -f "$FAIL_FILE" ]; then
        date +%s > "$FAIL_FILE"
      fi
      ELAPSED=$(( $(date +%s) - $(cat "$FAIL_FILE") ))
      log "Sustained failure for ''${ELAPSED}s (reboot at 600s)"
      if [ "$ELAPSED" -ge 600 ]; then
        log "CRITICAL: 10 minutes of sustained failure -- rebooting"
        disable_leak_guard
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

    trap 'nft delete table inet "$GUARD_TABLE" 2>/dev/null || true' EXIT

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
      ${reapplySplitTunnel} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after mullvad reconnect"
        reset_failure
        exit 0
      fi
    fi

    # Step 2: Mullvad connected but pings fail → bad relay, rotate to new one
    if echo "$MULLVAD_STATUS" | grep -qi "connected"; then
      log "Step 2: Mullvad connected but no internet, rotating relay"
      ${selectRelay} || true
      mullvad reconnect --wait || true
      ${applyBypass} || true
      ${reapplySplitTunnel} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after relay rotation"
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
      ${reapplySplitTunnel} || true
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
      ${reapplySplitTunnel} || true
      sleep 3
      NEW_FAIL=$(quick_ping_check)
      if [ "$NEW_FAIL" -lt 2 ]; then
        log "Recovered after NetworkManager restart"
        reset_failure
        exit 0
      fi
    fi

    # Step 5: Nuclear VPN reset (with 5-minute cooldown to avoid
    # rapid-fire daemon restarts that destabilize everything)
    if [ -f "${nuclearCooldownFile}" ]; then
      NUCLEAR_AGE=$(( $(date +%s) - $(cat "${nuclearCooldownFile}") ))
      if [ "$NUCLEAR_AGE" -lt 300 ]; then
        log "Step 5: Skipping nuclear reset (cooldown ''${NUCLEAR_AGE}s/300s)"
        log "All recovery steps exhausted, waiting for next cycle"
        check_reboot_timeout
        exit 1
      fi
    fi
    date +%s > "${nuclearCooldownFile}"
    log "Step 5: Restarting mullvad-daemon"
    enable_leak_guard
    systemctl restart mullvad-daemon || true
    sleep 10
    mullvad connect --wait || true
    ${applyBypass} || true
    ${reapplySplitTunnel} || true
    disable_leak_guard
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
      ${reapplySplitTunnel} || true
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
      CHAIN_RULES="$(nft list chain inet "$MULLVAD_TABLE" "$chain" 2>/dev/null || true)"
      if ! echo "$CHAIN_RULES" | grep -q 'oifname "tailscale0" accept'; then
        nft insert rule inet "$MULLVAD_TABLE" "$chain" \
          oifname "tailscale0" accept 2>/dev/null || true
      fi
      if ! echo "$CHAIN_RULES" | grep -q 'iifname "tailscale0" accept'; then
        nft insert rule inet "$MULLVAD_TABLE" "$chain" \
          iifname "tailscale0" accept 2>/dev/null || true
      fi
    done

    if ! nft list chain inet "$MULLVAD_TABLE" output 2>/dev/null \
         | grep -q 'meta mark.*0x80000.*== 0x80000 accept'; then
      nft insert rule inet "$MULLVAD_TABLE" output \
        meta mark \& 0x80000 == 0x80000 accept 2>/dev/null || true
    fi
  '';

  reapplySplitTunnel = pkgs.writeShellScript "mullvad-reapply-split-tunnel" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [
      config.services.mullvad-vpn.package
      pkgs.procps
      pkgs.coreutils
    ]}"

    TSPID=$(pgrep -x tailscaled || true)
    if [ -z "$TSPID" ]; then
      echo "tailscaled not running, skipping split tunnel" >&2
      exit 0
    fi

    mullvad split-tunnel pid add "$TSPID" 2>/dev/null ||
      mullvad split-tunnel add "$TSPID" 2>/dev/null || true
    echo "Split tunnel updated for tailscaled PID $TSPID" >&2
  '';

  nuclearCooldownFile = "/run/mullvad-nuclear-cooldown";
in {
  options.services.mullvad-relay = {
    homeLatitude = lib.mkOption {
      type = lib.types.float;
      default = 38.8977;
      description = "Latitude for nearby-city relay selection (default: White House, DC).";
    };
    homeLongitude = lib.mkOption {
      type = lib.types.float;
      default = -77.0365;
      description = "Longitude for nearby-city relay selection (default: White House, DC).";
    };
  };

  config = {
    services.mullvad-vpn.enable = true;

    services.tailscale.useRoutingFeatures = "both";

    networking.firewall = {
      enable = lib.mkForce true;
      trustedInterfaces = ["tailscale0"];
      allowedUDPPorts = [config.services.tailscale.port];
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
      requires = ["mullvad-daemon.service"];
      wants = ["tailscaled.service"];
      wantedBy = ["multi-user.target"];
      path =
        commonPath
        ++ [
          pkgs.procps
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

        ${reapplySplitTunnel} || true

        # Clean stale ip rules from previous runs so Mullvad doesn't
        # keep leapfrogging them with lower priority numbers.
        while ip rule del to 100.64.0.0/10 lookup 52 2>/dev/null; do :; done
        while ip -6 rule del to fd7a:115c:a1e0::/48 lookup 52 2>/dev/null; do :; done
        ip rule del fwmark 0x40000/0x40000 table 200 2>/dev/null || true
        ip route flush table 200 2>/dev/null || true

        SELECT_RELAY_RC=0
        ${selectRelay} || SELECT_RELAY_RC=$?
        if [ "$SELECT_RELAY_RC" -ne 0 ] && [ "$SELECT_RELAY_RC" -ne 10 ]; then
          exit "$SELECT_RELAY_RC"
        fi

        mullvad connect --wait

        ${applyBypass}
      '';
    };

    systemd.services.mullvad-rotate-relay = {
      description = "Rotate Mullvad relay to a nearby city";
      after = [
        "mullvad-daemon.service"
        "network-online.target"
        "mullvad-auto-connect.service"
      ];
      wants = ["network-online.target"];
      path =
        commonPath
        ++ [
          pkgs.util-linux
        ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        SELECT_RELAY_RC=0
        ${selectRelay} || SELECT_RELAY_RC=$?
        if [ "$SELECT_RELAY_RC" -eq 10 ]; then
          echo "Relay selection skipped due to lock contention; skipping reconnect" >&2
          exit 0
        fi
        if [ "$SELECT_RELAY_RC" -ne 0 ]; then
          exit "$SELECT_RELAY_RC"
        fi

        mullvad reconnect --wait
        ${applyBypass}
      '';
    };

    systemd.timers.mullvad-rotate-relay = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        RandomizedDelaySec = "90min";
        Persistent = true;
      };
    };

    # Safety net: re-apply bypass rules at a low frequency in case
    # something other than rotation disturbs Mullvad's state.
    systemd.services.mullvad-tailscale-keepalive = {
      description = "Re-apply Tailscale bypass rules for Mullvad";
      after = ["mullvad-auto-connect.service"];
      wants = ["mullvad-auto-connect.service"];
      path = commonPath;
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        ${applyBypass}
        ${reapplySplitTunnel}
      '';
    };

    systemd.timers.mullvad-tailscale-keepalive = {
      wantedBy = ["timers.target"];
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
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        ${connectivityWatchdog}
      '';
    };

    systemd.timers.mullvad-connectivity-watchdog = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "60s";
      };
    };

    systemd.services.tailscale-exit-node = {
      description = "Advertise Tailscale exit node";
      after = ["tailscaled.service"];
      wants = ["tailscaled.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.tailscale];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        sleep 5
        tailscale set --advertise-exit-node
      '';
    };
  };
}
