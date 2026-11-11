# screenrec — region capture with wf-recorder, upload through juush, and wait for
# the site's Temporal pipeline to publish the web MP4. One process owns the whole
# lifecycle so no path is ever handed between processes.
#
# shellcheck shell=bash           # no shebang: writeShellApplication prepends one
# shellcheck disable=SC2016  # single-quoted jq programs use $var; no shell expansion intended
#
# state:     $XDG_RUNTIME_DIR/screenrec/{status.json,pid,stop,wf.log,juush.log,start.lock}
# persistent: ~/.local/state/screenrec/{geometry,index.jsonl,notify_id}
# clips:      ~/screenshots/<YYYYy-MMm-DDd_HHh-MMm-SSs>[_<class>]_<WxH>.mkv

state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screenrec"
persist="${XDG_STATE_HOME:-$HOME/.local/state}/screenrec"
clips="$HOME/screenshots"

current_file=""
current_url=""
since=0
supervisor=0

mkdir -p "$state" "$persist" "$clips"

# note <urgency> <timeout> <icon> <summary> [body] [pct]
# Reuses one dunst notification id so the same slot morphs through the stages.
note() {
    local args=(-a screenrec -p -u "$1" -t "$2" -i "$3")
    if [ -s "$persist/notify_id" ]; then
        args+=(-r "$(cat "$persist/notify_id")")
    fi
    if [ -n "${6:-}" ]; then
        args+=(-h "int:value:$6")
    fi
    dunstify "${args[@]}" "$4" "${5:-}" >"$persist/notify_id" 2>/dev/null || true
}

# put_status <phase> <pct> <text> — atomic, single writer (the supervisor).
put_status() {
    jq -cn --arg phase "$1" --argjson pct "$2" --arg text "$3" \
        --arg file "$current_file" --arg url "$current_url" --argjson since "$since" \
        '{phase:$phase,pct:$pct,text:$text,file:$file,url:$url,since:$since}' \
        >"$state/status.json.tmp"
    mv "$state/status.json.tmp" "$state/status.json"
}

render() {
    local phase=idle text="" file="" url=""
    local line
    line=$(jq -r '[.phase,.text,.file,.url]|@tsv' "$state/status.json" 2>/dev/null) || line=""
    if [ -n "$line" ]; then
        IFS=$'\t' read -r phase text file url <<<"$line"
    fi
    case "$phase" in
        recording|starting) jq -cn --arg text "● $text" --arg tip "recording $file
CTRL+SHIFT+6 to stop" '{text:$text,class:"recording",tooltip:$tip}' ;;
        uploading) jq -cn --arg text "⬆ $text" --arg tip "uploading $file" '{text:$text,class:"uploading",tooltip:$tip}' ;;
        processing) jq -cn --arg text "⏳ $text" --arg tip "server is building the web MP4" '{text:$text,class:"processing",tooltip:$tip}' ;;
        done) jq -cn --arg url "$url" '{text:"✔",class:"done",tooltip:$url}' ;;
        error) jq -cn --arg text "$text" '{text:"✖",class:"error",tooltip:$text}' ;;
        *) printf '%s\n' '{"text":"","class":"idle","tooltip":""}' ;;
    esac
}

status_follow() {
    trap 'exit 0' TERM INT
    local last=""
    local out
    while :; do
        out=$(render) || out='{"text":"","class":"idle","tooltip":""}'
        if [ "$out" != "$last" ]; then
            printf '%s\n' "$out"
            last="$out"
        fi
        sleep 1
    done
}

cmd_start() {
    local reselect=1 audio=0 cap=120
    while [ $# -gt 0 ]; do
        case "$1" in
            --reuse) reselect=0 ;;
            --audio) audio=1 ;;
            --cap) shift; cap="$1" ;;
            *) printf 'screenrec: unknown option %s\n' "$1" >&2; exit 2 ;;
        esac
        shift
    done

    if [ "$cap" -le 0 ]; then cap=120; fi

    # Guard only the pid/status creation window; the lock is released before the
    # capture starts so stop/status never block on it.
    exec 9>"$state/start.lock"
    if ! flock -n 9; then
        note low 10 media-record "Already starting" "one capture at a time"
        exit 0
    fi
    if [ -s "$state/pid" ] && kill -0 "$(cat "$state/pid")" 2>/dev/null; then
        note low 10 media-record "Already running" "press CTRL+SHIFT+6 to stop"
        exit 0
    fi
    rm -f "$state/stop" "$state/status.json"

    local geom
    if [ "$reselect" -eq 1 ] || [ ! -s "$persist/geometry" ]; then
        geom=$(slurp 2>/dev/null) || geom=""
        if [ -z "$geom" ]; then
            note low 5 media-record "Recording cancelled" "no region selected"
            exit 0
        fi
        printf '%s\n' "$geom" >"$persist/geometry"
    else
        geom=$(cat "$persist/geometry")
    fi

    local ts cls size name mkv
    ts=$(date +%Yy-%mm-%dd_%0Hh-%Mm-%Ss_)
    cls=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""' | tr -c 'A-Za-z0-9._-' '_' | cut -c1-24) || cls=""
    size=$(printf '%s' "${geom#* }" | tr -cd '0-9x')
    if [ -n "$cls" ]; then
        name="${ts}${cls}_${size}"
    else
        name="${ts}${size}"
    fi
    mkv="$clips/$name.mkv"

    current_file="$mkv"
    current_url=""
    since=$(date +%s)
    supervisor=1
    put_status starting 0 "starting"
    note low 0 media-record "Recording" "$name.mkv · $geom"

    local wpid
    if [ "$audio" -eq 1 ]; then
        wf-recorder -y -r 60 -x yuv420p -a -C aac -g "$geom" -f "$mkv" >>"$state/wf.log" 2>&1 &
    else
        wf-recorder -y -r 60 -x yuv420p -g "$geom" -f "$mkv" >>"$state/wf.log" 2>&1 &
    fi
    wpid=$!
    printf '%s\n' "$$" >"$state/pid"
    flock -u 9
    exec 9>&-

    since=$(date +%s)
    put_status recording 0 "0:00"

    local elapsed=0 pct=0
    while kill -0 "$wpid" 2>/dev/null; do
        sleep 1
        elapsed=$(( $(date +%s) - since ))
        pct=$(( elapsed * 100 / cap ))
        if [ "$pct" -gt 100 ]; then pct=100; fi
        put_status recording "$pct" "$(printf '%d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))"
        note low 0 media-record \
            "Recording $(printf '%d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))" \
            "$(du -h "$mkv" 2>/dev/null | cut -f1) · CTRL+SHIFT+6 to stop" "$pct"
        if [ -e "$state/stop" ] || [ "$elapsed" -ge "$cap" ]; then
            kill -INT "$wpid" 2>/dev/null || true
            break
        fi
    done
    wait "$wpid" 2>/dev/null || true

    local bytes
    bytes=$(stat -c %s "$mkv" 2>/dev/null) || bytes=0
    if [ "$bytes" -lt 1024 ]; then
        rm -f "$mkv"
        since=$(date +%s)
        put_status error 0 "recording failed"
        note normal 0 dialog-error "Recording failed" "wf-recorder wrote ${bytes} bytes — see $state/wf.log"
        exit 1
    fi

    since=$(date +%s)
    put_status uploading 0 "$(du -h "$mkv" | cut -f1)"
    note low 0 document-save "Uploading $(du -h "$mkv" | cut -f1)" "$name.mkv"

    local out url
    if ! out=$(JUUSH_QUIET=1 juush "$mkv" 2>>"$state/juush.log"); then
        since=$(date +%s)
        put_status error 0 "upload failed"
        note normal 0 dialog-error "Upload failed" "clip kept at $mkv — see $state/juush.log"
        exit 1
    fi
    url=$(printf '%s\n' "$out" | grep -Eo 'https?://[^[:space:]]+' | grep -v '/uf$' | tail -n1) || url=""
    if [ -z "$url" ]; then
        since=$(date +%s)
        put_status error 0 "upload returned no url"
        note normal 0 dialog-error "Upload returned no URL" \
            "clip kept at $mkv — check 'type -a juush' (a stale copy prints its curl command) and $state/juush.log"
        exit 1
    fi
    current_url="$url"

    # The site's Temporal workflow turns the H.264 mkv into <url>.fast.mp4 and the
    # same URL starts serving video/mp4 once it lands.
    since=$(date +%s)
    put_status processing 0 "0s"
    local i=0 ct ok=0
    while [ "$i" -lt 90 ]; do
        ct=$(curl -sS -o /dev/null -w '%{content_type}' -L --max-time 10 "$url" 2>/dev/null) || ct=""
        case "$ct" in video/mp4*) ok=1; break ;; esac
        i=$(( i + 1 ))
        put_status processing "$(( i * 100 / 90 ))" "$(( i * 2 ))s"
        note low 0 video-x-generic "Processing on server ($(( i * 2 ))s)" "$url" "$(( i * 100 / 90 ))"
        sleep 2
    done

    # The URL is valid and the local clip exists whether or not the conversion finished.
    jq -cn --arg path "$mkv" --arg url "$url" --arg ts "$(date -Is)" --arg geom "$geom" \
        '{path:$path,url:$url,ts:$ts,geom:$geom}' >>"$persist/index.jsonl"
    tail -n 50 "$persist/index.jsonl" >"$persist/index.jsonl.tmp"
    mv "$persist/index.jsonl.tmp" "$persist/index.jsonl"

    since=$(date +%s)
    if [ "$ok" -eq 0 ]; then
        put_status error 0 "not converted yet"
        note normal 0 dialog-warning "Uploaded · not converted yet" "$url"
        sleep 15
        put_status idle 0 ""
        exit 1
    fi

    put_status "done" 100 "$url"
    note normal 0 video-x-generic "Clip ready · $(printf '%d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 )))" "$url"

    sleep 15
    put_status idle 0 ""
}

cmd_stop() {
    local phase=idle
    phase=$(jq -r '.phase // "idle"' "$state/status.json" 2>/dev/null) || phase=idle
    case "$phase" in
        recording|starting)
            touch "$state/stop"
            note low 5 media-record "Stopping" "finalizing the clip"
            ;;
        *)
            note low 5 media-record "Not recording" "nothing to stop"
            ;;
    esac
}

cmd_toggle() {
    local phase=idle
    phase=$(jq -r '.phase // "idle"' "$state/status.json" 2>/dev/null) || phase=idle
    case "$phase" in
        recording|starting) cmd_stop ;;
        *) cmd_start ;;
    esac
}

cmd_last() {
    local menu sel path url action new newurl
    if [ ! -s "$persist/index.jsonl" ]; then
        note low 5 video-x-generic "No clips yet" "record one with CTRL+SHIFT+9"
        exit 0
    fi
    menu=$(tail -n 20 "$persist/index.jsonl" | jq -r '.path' | tac) || menu=""
    if [ -z "$menu" ]; then
        note low 5 video-x-generic "No clips yet" "index is empty"
        exit 0
    fi
    sel=$(printf '%s\n' "$menu" | fuzzel --dmenu -p "clip: ") || exit 0
    [ -n "$sel" ] || exit 0
    path="$sel"
    url=$(jq -r --arg p "$path" 'select(.path==$p)|.url // ""' "$persist/index.jsonl" | tail -n1) || url=""

    action=$(printf '%s\n' "Open in mpv" "Copy URL" "Open URL" "Upload again" "Move to trash" \
        | fuzzel --dmenu -p "action: ") || exit 0
    case "$action" in
        "Open in mpv")
            mpv --force-window=yes -- "$path" >/dev/null 2>&1 &
            ;;
        "Copy URL")
            printf '%s' "$url" | wl-copy
            ;;
        "Open URL")
            xdg-open "$url" >/dev/null 2>&1 &
            ;;
        "Upload again")
            note low 0 document-save "Uploading again" "$path"
            new=$(JUUSH_QUIET=1 juush "$path" 2>>"$state/juush.log") || new=""
            newurl=$(printf '%s\n' "$new" | grep -Eo 'https?://[^[:space:]]+' | grep -v '/uf$' | tail -n1) || newurl=""
            if [ -n "$newurl" ]; then
                note normal 0 video-x-generic "Clip ready" "$newurl"
            fi
            ;;
        "Move to trash")
            trash-put -- "$path"
            ;;
        *)
            exit 0
            ;;
    esac
}

trap 'if [ "$supervisor" -eq 1 ]; then rm -f "$state/pid" "$state/stop"; fi' EXIT

case "${1:-}" in
    start) shift; cmd_start "$@" ;;
    stop) cmd_stop ;;
    toggle) cmd_toggle ;;
    status) shift; if [ "${1:-}" = "--follow" ]; then status_follow; else render; fi ;;
    last) cmd_last ;;
    *)
        printf 'usage: screenrec {start [--reuse] [--audio] [--cap N]|stop|toggle|status [--follow]|last}\n' >&2
        exit 2
        ;;
esac
