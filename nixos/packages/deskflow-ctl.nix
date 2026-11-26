# Bar read-out and click target for the Deskflow server (modules/deskflow.nix).
#
# Everything is read from the server side, without root: the listener and each
# client's socket come from `ss`, the path from the route to the client, and the
# latency from the kernel's smoothed RTT for that socket. Deskflow's keepalive
# touches the socket every few seconds, so that RTT stays current while the
# pointer is idle.
#
# The server can serve several clients at once. `status` summarises them for the
# bar pill; `clients` prints one JSON object per client — name, address, route
# class, latency and the raw latency samples the panel graphs; `client N` keeps
# reporting the Nth one on its own, as Waybar-shaped JSON.
{
  lib,
  writeShellApplication,
  avahi,
  coreutils,
  gawk,
  gnugrep,
  iproute2,
  jq,
  libnotify,
  systemd,
  tailscale,
  util-linux,
  # Interfaces carrying the dedicated MacBook wire on this host
  # (services.macbookLink.interfaces). A client routed out of one of them is on
  # the wire; any other route is the LAN, Wi-Fi or the tailnet.
  wireIfaces ? [],
}:
writeShellApplication {
  name = "deskflow-ctl";
  runtimeInputs = [avahi coreutils gawk gnugrep iproute2 jq libnotify systemd tailscale util-linux];
  text = ''
    port=24800
    # History length. Each client keeps its own file. The bar polls every 2 s
    # and a sample is taken only when the last one for that client is at least
    # $gap ms old, so even with one bar per monitor (their polls are not in
    # phase) there is one sample per poll period: 60 samples is two minutes.
    samples=60
    gap=1900
    dir="''${XDG_RUNTIME_DIR:-/tmp}/deskflow-ctl"
    hist_dir="$dir/clients"
    names="$dir/names"
    # The per-client pills the summary rendered on its last poll, one JSON
    # object per line. `client N` reads this instead of re-running ss and the
    # route lookups; a snapshot older than five seconds is ignored.
    slots_file="$dir/slots"
    snapshot_ttl=5
    # A peer's name comes from mDNS (avahi-resolve) or, on the tailnet, from
    # tailscale. Names rarely change and every bar module asks again every 2 s,
    # so a hit is kept for a day.
    name_ttl=86400
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

    mkdir -p "$hist_dir"

    # Only the history and the name cache need the lock, so a slot served from
    # the snapshot never waits for the summary's poll to finish.
    lock() {
      exec 9>"$dir/lock"
      flock 9
    }

    server_line() {
      if [ "$unit" = active ]; then
        printf 'unit active on %s\n' "$host"
      elif [ "$listening" = yes ]; then
        printf 'core running outside the unit on %s (unit %s)\n' "$host" "$unit"
      else
        printf 'unit %s on %s\n' "$unit" "$host"
      fi
    }

    peer_file() {
      printf '%s/%s.log\n' "$hist_dir" "$(printf '%s' "$1" | tr -c '0-9A-Za-z.' '_')"
    }

    peer_name() {
      local ip=$1 now cached name=""
      now=$(date +%s)
      cached=$(awk -F'\t' -v ip="$ip" -v now="$now" -v ttl="$name_ttl" \
        '$1 == ip && now - $2 < ttl { n = $3 } END { if (n != "") print n }' \
        "$names" 2>/dev/null || true)
      if [ -n "$cached" ]; then
        name=$cached
      else
        # The tailnet is 100.64.0.0/10 and mDNS never sees it, so ask the
        # tailscale daemon there; every other peer is answered from avahi's
        # cache, which is what makes the lookup cheap enough to repeat.
        case "$ip" in
          100.6[4-9].* | 100.[7-9][0-9].* | 100.1[01][0-9].* | 100.12[0-7].*)
            name=$(tailscale status --json 2>/dev/null |
              jq -r --arg ip "$ip" '[.Peer[] | select((.TailscaleIPs // []) | index($ip)) | .HostName][0] // empty' 2>/dev/null || true)
            ;;
        esac
        if [ -z "$name" ]; then
          name=$(avahi-resolve -a "$ip" 2>/dev/null | cut -f2 || true)
          name=''${name%.local}
        fi
        if [ -z "$name" ]; then
          name=$ip
        else
          printf '%s\t%s\t%s\n' "$ip" "$now" "$name" >>"$names"
        fi
      fi
      # The name goes into a Pango tooltip and into a pill, so keep it free of
      # markup.
      printf '%s\n' "$name" | tr -d '<>&'
    }

    sample() {
      local file now last
      file=$(peer_file "$1")
      now=$(date +%s%3N)
      last=$(tail -n 1 "$file" 2>/dev/null | cut -d' ' -f1 || true)
      case "$last" in
        "" | *[!0-9]*) last=0 ;;
      esac
      # A lull of ten minutes means the client went away and came back, not a
      # pause: start a new history so the graph never mixes two sessions. The
      # same reset covers a clock that jumped backwards.
      if [ "$last" -gt "$now" ] || [ $((now - last)) -ge 600000 ]; then
        last=0
        : >"$file"
      fi
      if [ $((now - last)) -ge "$gap" ]; then
        printf '%s %s\n' "$now" "$2" >>"$file"
        tail -n "$samples" "$file" >"$file.tmp"
        mv "$file.tmp" "$file"
      fi
    }

    spark() {
      # Prints one line of blocks on a fixed log scale, so the same height means
      # the same latency on the wire and over Wi-Fi — a dot is a sample with no
      # RTT yet — then a min/avg/max line.
      awk '
        BEGIN { split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", g, " "); split("1 2 5 10 20 50 100", t, " ") }
        $2 == "-" { s = s "·"; next }
        { v = $2 + 0; i = 1; while (i <= 7 && v >= t[i]) i++; s = s g[i]
          n++; sum += v; if (n == 1 || v < mn) mn = v; if (n == 1 || v > mx) mx = v }
        END { if (s != "") print s
              if (n) printf "min %.2f  avg %.2f  max %.2f ms\n", mn, sum / n, mx }
      ' "$1"
    }

    clients() {
      # One line per connected client, sorted by peer address so a client keeps
      # its slot in the bar for as long as it stays connected:
      #   name \t rtt \t kind \t where \t ip
      local peer ip rest rtt dev name kind where seen=""
      ss -H -O -tni state established "sport = :$port" 2>/dev/null |
        while read -r _ _ _ peer rest; do
          # The peer address carries the port, and a dual-stack listener reports
          # an IPv4 client as [::ffff:a.b.c.d].
          peer=''${peer%:*}
          peer=''${peer#\[}
          peer=''${peer%\]}
          peer=''${peer#::ffff:}
          [ -n "$peer" ] || continue
          # A client can own more than one socket; the first line is the one
          # that carries the RTT.
          case " $seen " in *" $peer "*) continue ;; esac
          seen="$seen $peer"
          rtt=$(grep -oE '(^| )rtt:[0-9.]+' <<<"$rest" | cut -d: -f2 || true)
          rtt=''${rtt:--}
          dev=$(ip -j route get "$peer" 2>/dev/null | jq -r '.[0].dev // empty' || true)
          if [ -n "$dev" ] && [[ "$wire_ifaces" == *" $dev "* ]]; then
            kind=wire
            where="direct wire ($dev)"
          elif [ "$dev" = tailscale0 ]; then
            kind=lan
            where=tailnet
          else
            kind=lan
            where="LAN or Wi-Fi (''${dev:-unknown})"
          fi
          name=$(peer_name "$peer")
          printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$rtt" "$kind" "$where" "$peer"
        done | sort -t $'\t' -k5,5 -V
    }

    history_json() {
      # $1 = a client's history file. Prints the latency samples as a JSON array
      # of milliseconds, oldest first. A sample taken before the socket had an
      # RTT is a dash, and a graph point needs a number, so those are skipped.
      local file=$1
      if [ ! -f "$file" ]; then
        printf '[]\n'
        return 0
      fi
      awk '
        BEGIN { printf "[" }
        $2 ~ /^[0-9]/ { printf "%s%s", (n++ ? "," : ""), $2 }
        END { print "]" }
      ' "$file"
    }

    object_json() {
      # $1 name, $2 rtt, $3 kind, $4 where, $5 ip — one client as the object
      # `clients` prints, with the samples the panel graphs.
      local name=$1 rtt=$2 kind=$3 where=$4 ip=$5 latency=null
      case "$rtt" in
        "" | -* | *[!0-9.]*) ;;
        *) latency=$rtt ;;
      esac
      jq -nc --arg name "$name" --arg ip "$ip" --arg class "$kind" --arg where "$where" \
        --argjson rtt "$latency" --argjson history "$(history_json "$(peer_file "$ip")")" \
        '{name: $name, ip: $ip, class: $class, where: $where, rtt: $rtt, history: $history}'
    }

    list_clients() {
      # Every connected client as JSON, in the same order as the slots:
      #   [{ name, ip, class, where, rtt, history }, ...]
      # `rtt` is null until the socket has one; `history` is milliseconds.
      local rows name rtt kind where ip objects=""
      lock
      rows=$(clients)
      sample_all "$rows"
      while IFS=$'\t' read -r name rtt kind where ip; do
        [ -n "$ip" ] || continue
        objects+="$(object_json "$name" "$rtt" "$kind" "$where" "$ip")"$'\n'
      done <<<"$rows"
      printf '%s' "$objects" | jq -s '.'
    }

    sample_all() {
      local rows=$1 name rtt kind where ip
      while IFS=$'\t' read -r name rtt kind where ip; do
        [ -n "$ip" ] || continue
        sample "$ip" "$rtt"
      done <<<"$rows"
    }

    client_json() {
      # $1 name, $2 rtt, $3 kind, $4 where, $5 ip — one pill as Waybar JSON.
      local name=$1 rtt=$2 kind=$3 where=$4 ip=$5 label rtt_text tip graph
      label=$name
      if [ "''${#label}" -gt 12 ]; then
        label="''${label:0:12}…"
      fi
      rtt_text=$(awk -v r="$rtt" 'BEGIN {
        if (r == "-") { print "?" } else if (r + 0 < 10) { printf "%.1f\n", r } else { printf "%.0f\n", r }
      }')
      tip="Deskflow client: $name"
      tip+=$'\n'"address: $ip"
      tip+=$'\n'"path: $where"
      if [ "$rtt" != - ]; then
        tip+=$'\n'"latency: $rtt ms"
      fi
      graph=$(spark "$(peer_file "$ip")")
      case "$graph" in
        "") ;;
        *$'\n'*)
          tip+=$'\n'"''${graph%%$'\n'*}"
          tip+=$'\n'"last 2 min: ''${graph#*$'\n'}"
          ;;
        *) tip+=$'\n'"$graph" ;;
      esac
      tip+=$'\n'"server: $(server_line)"

      jq -nc --arg text "$label $rtt_text ms" --arg class "$kind" --arg tooltip "$tip" \
        '{text: $text, class: $class, tooltip: $tooltip}'
    }

    status() {
      local class=stopped headline="stopped (click to start)" count=0
      local name rtt kind where ip body="" tip graph slot slots_text=""
      local rows
      lock
      rows=$(clients)
      sample_all "$rows"

      if [ "$listening" = yes ]; then
        class=idle
        headline="no client connected"
      fi

      while IFS=$'\t' read -r name rtt kind where ip; do
        [ -n "$ip" ] || continue
        count=$((count + 1))
        # The pill's colour is the way in, so it follows the weakest path: one
        # client off the wire keeps the whole summary blue.
        if [ "$kind" = lan ]; then
          class=lan
        elif [ "$class" != lan ]; then
          class=wire
        fi
        body+=$'\n'"• $name — $where"
        if [ "$rtt" != - ]; then
          body+=" — $rtt ms"
        fi
        graph=$(spark "$(peer_file "$ip")")
        case "$graph" in
          "") ;;
          *$'\n'*)
            body+=$'\n'"  ''${graph%%$'\n'*}"
            body+=$'\n'"  last 2 min: ''${graph#*$'\n'}"
            ;;
          *) body+=$'\n'"  $graph" ;;
        esac
        slot=$(client_json "$name" "$rtt" "$kind" "$where" "$ip")
        slots_text+="$slot"$'\n'
      done <<<"$rows"

      # Hand the slots what this poll already rendered. Every poll rewrites the
      # file, so a client that went away loses its pill on the next one.
      printf '%s' "$slots_text" >"$slots_file.tmp"
      mv "$slots_file.tmp" "$slots_file"

      if [ "$count" -eq 1 ]; then
        headline="1 client"
      elif [ "$count" -gt 1 ]; then
        headline="$count clients"
      fi

      # The tooltip is Pango markup: keep it free of ampersands and angle
      # brackets, or GTK drops the whole tooltip.
      tip="Deskflow: $headline"
      if [ -n "$body" ]; then
        tip+=$'\n'"$body"
      fi
      tip+=$'\n'"server: $(server_line)"
      tip=$(printf '%s' "$tip" | head -c 2000 || true)

      jq -nc --arg class "$class" --arg tooltip "$tip" \
        '{text: "DF", class: $class, tooltip: $tooltip}'
    }

    client() {
      local want=$1 index=0 name rtt kind where ip slot age=999
      local rows
      if ! [[ "$want" =~ ^[1-9][0-9]*$ ]]; then
        printf 'deskflow-ctl: client slot must be a positive integer\n' >&2
        exit 2
      fi

      # The summary renders every slot on each of its polls, so reuse that
      # snapshot while it is fresh: a slot then costs a sed instead of another
      # ss, route and name round.
      if [ -f "$slots_file" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$slots_file" 2>/dev/null || echo 0) ))
      fi
      if [ "$age" -le "$snapshot_ttl" ]; then
        slot=$(sed -n "''${want}p" "$slots_file")
        if [ -n "$slot" ]; then
          printf '%s\n' "$slot"
        else
          printf '{"text": "", "class": "", "tooltip": ""}\n'
        fi
        exit 0
      fi

      # No summary (or a stale one): work it out here, and sample like the
      # summary would so a client's history does not pause.
      lock
      rows=$(clients)
      sample_all "$rows"
      while IFS=$'\t' read -r name rtt kind where ip; do
        [ -n "$ip" ] || continue
        index=$((index + 1))
        [ "$index" -eq "$want" ] || continue
        client_json "$name" "$rtt" "$kind" "$where" "$ip"
        exit 0
      done <<<"$rows"

      # Waybar hides a custom module whose label is empty, so a slot with no
      # client leaves no gap in the bar.
      printf '{"text": "", "class": "", "tooltip": ""}\n'
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
      clients) list_clients ;;
      client) client "''${2:-}" ;;
      toggle) toggle ;;
      *)
        printf 'usage: deskflow-ctl {status|clients|client <slot>|toggle}\n' >&2
        exit 2
        ;;
    esac
  '';
}
