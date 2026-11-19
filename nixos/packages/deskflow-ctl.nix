# Bar read-out and click target for the Deskflow server (modules/deskflow.nix).
#
# Everything is read from the server side, without root: the listener and the
# client's socket come from `ss`, the path from the route to the client, and
# the latency from the kernel's smoothed RTT for that socket. Deskflow's
# keepalive touches the socket every few seconds, so that RTT stays current
# while the pointer is idle.
{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  gnugrep,
  iproute2,
  jq,
  libnotify,
  systemd,
  util-linux,
  # Interfaces carrying the dedicated MacBook wire on this host
  # (services.macbookLink.interfaces). A client routed out of one of them is on
  # the wire; any other route is the LAN, Wi-Fi or the tailnet.
  wireIfaces ? [],
}:
writeShellApplication {
  name = "deskflow-ctl";
  runtimeInputs = [coreutils gawk gnugrep iproute2 jq libnotify systemd util-linux];
  text = ''
    port=24800
    # History length. The bar polls every 2 s and a sample is taken only when
    # the last one is at least $gap ms old, so even with one bar per monitor
    # (their polls are not in phase) there is one sample per poll period:
    # 60 samples is two minutes.
    samples=60
    gap=1900
    dir="''${XDG_RUNTIME_DIR:-/tmp}/deskflow-ctl"
    hist="$dir/rtt.log"
    wire_ifaces=" ${lib.concatStringsSep " " wireIfaces} "

    host=$(uname -n)
    # is-active exits non-zero when the unit is not up, hence the `|| true`.
    unit=$(systemctl --user is-active deskflow.service 2>/dev/null || true)
    unit=''${unit:-unknown}
    # Anything serving the port counts: the Deskflow GUI starts its own core,
    # which serves clients just as well as the unit does (and wins the port).
    listening=no
    if [ -n "$(ss -H -tln "sport = :$port" 2>/dev/null)" ]; then
      listening=yes
    fi

    status() {
      local class=stopped headline="stopped (click to start)"
      local line="" peer="" rest="" rtt="-" dev="" where="" server now last tip
      local -a graph=()

      if [ "$listening" = yes ]; then
        class=idle
        headline="no client connected"
        # -O keeps the TCP info on the socket's own line:
        #   0 0 10.99.0.1:24800 10.99.0.112:55999 cubic ... rtt:0.57/0.33 ...
        line=$(ss -H -O -tni state established "sport = :$port" 2>/dev/null | head -n 1 || true)
      fi

      if [ -n "$line" ]; then
        read -r _ _ _ peer rest <<<"$line"
        peer=''${peer%:*}
        # A dual-stack listener would report an IPv4 client as [::ffff:a.b.c.d].
        peer=''${peer#\[}
        peer=''${peer%\]}
        peer=''${peer#::ffff:}
        rtt=$(grep -oE '(^| )rtt:[0-9.]+' <<<"$rest" | cut -d: -f2 || true)
        rtt=''${rtt:--}
        dev=$(ip -j route get "$peer" 2>/dev/null | jq -r '.[0].dev // empty' || true)
        if [ -n "$dev" ] && [[ "$wire_ifaces" == *" $dev "* ]]; then
          class=wire
          where="direct wire ($dev)"
        elif [ "$dev" = tailscale0 ]; then
          class=lan
          where="tailnet"
        else
          class=lan
          where="LAN or Wi-Fi (''${dev:-unknown})"
        fi
        headline="$peer via $where"
      fi

      # Waybar runs one copy of this per monitor. The lock and the gap keep
      # that to a single sample per poll period.
      mkdir -p "$dir"
      exec 9>"$dir/lock"
      flock 9
      now=$(date +%s%3N)
      last=$(tail -n 1 "$hist" 2>/dev/null | cut -d' ' -f1 || true)
      # A missing, damaged or future-dated last line must not stop sampling.
      case "$last" in
        "" | *[!0-9]*) last=0 ;;
      esac
      if [ "$last" -gt "$now" ] || [ $((now - last)) -ge "$gap" ]; then
        printf '%s %s\n' "$now" "$rtt" >>"$hist"
        tail -n "$samples" "$hist" >"$hist.tmp"
        mv "$hist.tmp" "$hist"
      fi

      # One block per sample on a fixed log scale, so the same height means the
      # same latency on the wire and over Wi-Fi. A dot is a poll with no client.
      mapfile -t graph < <(awk '
        BEGIN { split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", g, " "); split("1 2 5 10 20 50 100", t, " ") }
        $2 == "-" { s = s "·"; next }
        { v = $2 + 0; i = 1; while (i <= 7 && v >= t[i]) i++; s = s g[i]
          n++; sum += v; if (n == 1 || v < mn) mn = v; if (n == 1 || v > mx) mx = v }
        END { print s; if (n) printf "min %.2f  avg %.2f  max %.2f ms\n", mn, sum / n, mx }
      ' "$hist")

      if [ "$unit" = active ]; then
        server="unit active on $host"
      elif [ "$listening" = yes ]; then
        server="core running outside the unit on $host (unit $unit)"
      else
        server="unit $unit on $host"
      fi

      # The tooltip is Pango markup: keep it free of ampersands and angle
      # brackets, or GTK drops the whole tooltip.
      tip="Deskflow: $headline"
      if [ "$rtt" != - ]; then
        tip+=$'\n'"latency: $rtt ms"
      fi
      if [ -n "''${graph[1]:-}" ]; then
        tip+=$'\n'"''${graph[0]}"
        tip+=$'\n'"last 2 min: ''${graph[1]}"
        tip+=$'\n'"scale: ▁ under 1 ms to █ 100 ms and up (log)"
      fi
      tip+=$'\n'"server: $server"

      jq -nc --arg class "$class" --arg tooltip "$tip" \
        '{text: "DF", class: $class, tooltip: $tooltip}'
    }

    toggle() {
      if [ "$unit" = active ]; then
        systemctl --user stop deskflow.service
      elif [ "$listening" = yes ]; then
        notify-send "Deskflow" "A core is serving port $port outside the unit (the Deskflow GUI?). Quit it to stop serving."
      else
        # A unit that hit its start limit refuses to start until it is reset.
        systemctl --user reset-failed deskflow.service 2>/dev/null || true
        systemctl --user start deskflow.service
      fi
    }

    case "''${1:-status}" in
      status) status ;;
      toggle) toggle ;;
      *)
        printf 'usage: deskflow-ctl {status|toggle}\n' >&2
        exit 2
        ;;
    esac
  '';
}
