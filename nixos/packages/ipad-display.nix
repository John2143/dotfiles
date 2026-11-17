# iPad second display helper: owns Hyprland's headless "MOONLIGHT" output.
#
# Sunshine runs `prep` before every stream (global_prep_cmd) to create and place
# the output at the client's resolution; `watch` is a user service that removes
# it once no stream is running; `status` feeds the waybar widget, and `recover`
# is the widget's repair click. Packaged separately from the module because the
# home-manager waybar module needs the same binary.
#
# Sunshine's unit runs with `environment.PATH = mkForce null`, so every command
# in `prep` resolves through this derivation's own PATH, and `undo` in the
# config must be an absolute store path.
{
  writeShellApplication,
  hyprland,
  jq,
  coreutils,
  procps,
  systemd,
}:

writeShellApplication {
  name = "ipad-display";
  runtimeInputs = [
    hyprland
    jq
    coreutils
    procps
    systemd
  ];
  text = ''
    readonly OUTPUT=MOONLIGHT
    readonly FALLBACK_W=2360
    readonly FALLBACK_H=1640
    readonly FALLBACK_FPS=60
    readonly IDLE_SECONDS=20
    STATE_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ipad-display"

    log() { printf 'ipad-display: %s\n' "$*" >&2; }

    # Home Manager exports HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY into the
    # systemd user environment, so this normally succeeds untouched. The discovery
    # below is what makes prep work when Sunshine's hook inherits neither. Crashed
    # sessions leave their socket files behind, so every candidate is probed
    # rather than trusting the first one found.
    hypr_env() {
      if hyprctl monitors >/dev/null 2>&1; then return 0; fi
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      local pid sig dir
      pid=$(pgrep -x Hyprland | head -n1 || true)
      if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        sig=$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -n1)
        if [ -n "$sig" ] && HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors >/dev/null 2>&1; then
          export HYPRLAND_INSTANCE_SIGNATURE="$sig"
          return 0
        fi
      fi
      while IFS= read -r dir; do
        sig=$(basename "$dir")
        if HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors >/dev/null 2>&1; then
          export HYPRLAND_INSTANCE_SIGNATURE="$sig"
          return 0
        fi
      done < <(printf '%s\n' "$XDG_RUNTIME_DIR"/hypr/*/ 2>/dev/null | sort -r)
      return 1
    }

    # `monitors all` includes disabled outputs, so this also sees an output that
    # is present but switched off.
    output_exists() {
      hyprctl monitors all -j 2>/dev/null | jq -e --arg o "$OUTPUT" 'any(.[]; .name == $o)' >/dev/null 2>&1
    }

    # Sunshine spawns these worker threads per stream and tears them down at the
    # end; CLIENT DISCONNECTED is not logged on an unclean drop, so thread state
    # is the only reliable liveness signal. The process has to be found by
    # command line: nixpkgs' `bin/sunshine` execs `.sunshine-wrapped` with the
    # original argv, so comm reads `.sunshine-wrapp` and `pgrep -x sunshine`
    # matches nothing.
    session_active() {
      local pid t
      while IFS= read -r pid; do
        for t in /proc/"$pid"/task/*/comm; do
          case "$(cat "$t" 2>/dev/null)" in
            session::video | session::audio | video::capture) return 0 ;;
          esac
        done
      done < <(pgrep -f sunshine 2>/dev/null || true)
      return 1
    }

    geometry() {
      hyprctl monitors all -j 2>/dev/null | jq -r --arg o "$OUTPUT" '
        [ .[] | select(.name == $o) ] as $m
        | if ($m | length) == 0 then ""
          else $m[0] | "\(.width)x\(.height)@\(.refreshRate) at \(.x)x\(.y) scale \(.scale)"
          end'
    }

    # Bottom-left anchor of the existing desktop, in layout pixels (a monitor
    # occupies width/scale along x). Keeps the iPad below everything else.
    position() {
      hyprctl monitors -j | jq -r --arg o "$OUTPUT" '
        [ .[] | select(.name != $o and .disabled == false) ] as $m
        | if ($m | length) == 0 then "0 0"
          else (($m | map(.x) | min | tostring) + " "
               + (($m | map(.y + ((.height / .scale) | floor)) | max | tostring)))
          end'
    }

    # hl.monitor replaces the whole rule, so all four fields are always passed.
    # The position separator is x, not a comma.
    apply_mode() {
      local w=$1 h=$2 fps=$3 x y scale
      read -r x y <<<"$(position)"
      scale=1
      if [ $((w * 5 % 8)) -eq 0 ] && [ $((h * 5 % 8)) -eq 0 ]; then scale=1.6; fi
      hyprctl eval "hl.monitor({output=\"$OUTPUT\", mode=\"''${w}x''${h}@''${fps}\", position=\"''${x}x''${y}\", scale=$scale})" >/dev/null
      log "applied ''${w}x''${h}@''${fps} at ''${x}x''${y} scale $scale"
    }

    ensure_output() {
      local w=$1 h=$2 fps=$3 out _
      if ! output_exists; then
        out=$(hyprctl output create headless "$OUTPUT" 2>&1 || true)
        # hyprctl prints exactly `ok` on success.
        case "$out" in
          ok | *already*) ;;
          *)
            log "output create failed: $out"
            return 1
            ;;
        esac
        for _ in $(seq 20); do
          if output_exists; then break; fi
          sleep 0.1
        done
        if ! output_exists; then
          log "output $OUTPUT did not appear"
          return 1
        fi
        log "created output $OUTPUT"
      fi
      apply_mode "$w" "$h" "$fps"
    }

    cmd_prep() {
      if ! hypr_env; then
        log "cannot reach Hyprland"
        return 1
      fi
      local w=''${SUNSHINE_CLIENT_WIDTH:-$FALLBACK_W}
      local h=''${SUNSHINE_CLIENT_HEIGHT:-$FALLBACK_H}
      local fps=''${SUNSHINE_CLIENT_FPS:-$FALLBACK_FPS}
      fps=''${fps%%.*}
      ensure_output "$w" "$h" "$fps"
    }

    cmd_watch() {
      local stamp="$STATE_DIR/idle" now
      mkdir -p "$STATE_DIR"
      while :; do
        if hypr_env; then
          if session_active; then
            rm -f "$stamp"
          elif [ ! -e "$stamp" ]; then
            date +%s >"$stamp"
          else
            now=$(date +%s)
            if [ $((now - $(cat "$stamp"))) -ge $IDLE_SECONDS ]; then
              # Only restart Sunshine when it was streaming into our output:
              # a reconnect skips global_prep_cmd and would clone the laptop panel.
              if output_exists; then
                if hyprctl output remove "$OUTPUT" >/dev/null 2>&1; then
                  log "removed $OUTPUT after idle"
                else
                  log "failed to remove $OUTPUT"
                fi
                systemctl --user restart sunshine.service || log "sunshine restart failed"
              fi
              rm -f "$stamp"
            fi
          fi
        fi
        sleep 2
      done
    }

    cmd_status() {
      local mode="''${1:-}" have=no stream=no geo=""
      if ! hypr_env; then
        if [ "$mode" = "--waybar" ]; then
          jq -nc '{text: "iPad ?", class: "off", tooltip: "hyprctl unreachable"}'
        else
          printf 'hyprland: unreachable\n'
        fi
        return 0
      fi
      if output_exists; then
        have=yes
        geo=$(geometry)
      fi
      if session_active; then stream=yes; fi
      if [ "$mode" != "--waybar" ]; then
        if [ "$have" = yes ]; then
          printf 'output: %s %s\n' "$OUTPUT" "$geo"
        else
          printf 'output: none\n'
        fi
        printf 'sunshine: %s\n' "$(systemctl --user is-active sunshine.service 2>/dev/null || true)"
        printf 'session: %s\n' "$stream"
        return 0
      fi
      # waybar drops a module that exits non-zero, so this always prints one
      # object and returns 0.
      if [ "$have" = yes ]; then
        jq -nc --arg geo "$geo" --arg stream "$stream" \
          '{text: "iPad", class: "connected", tooltip: ("MOONLIGHT " + $geo + "\nstream: " + $stream)}'
      elif [ "$stream" = yes ]; then
        jq -nc '{text: "iPad!", class: "clone", tooltip: "streaming without MOONLIGHT: this is a clone of the laptop panel"}'
      else
        jq -nc '{text: "iPad off", class: "off", tooltip: "no virtual output"}'
      fi
    }

    cmd_recover() {
      if ! hypr_env; then
        log "cannot reach Hyprland"
        return 1
      fi
      if output_exists; then
        if hyprctl output remove "$OUTPUT" >/dev/null 2>&1; then
          log "removed $OUTPUT"
        else
          log "failed to remove $OUTPUT"
        fi
      fi
      systemctl --user restart sunshine.service || log "sunshine restart failed"
    }

    cmd_create() {
      if ! hypr_env; then
        log "cannot reach Hyprland"
        return 1
      fi
      ensure_output "$FALLBACK_W" "$FALLBACK_H" "$FALLBACK_FPS"
    }

    case "''${1:-}" in
      prep) cmd_prep ;;
      watch) cmd_watch ;;
      status)
        shift
        cmd_status "''${1:-}"
        ;;
      recover) cmd_recover ;;
      create) cmd_create ;;
      *)
        printf 'usage: ipad-display {prep|watch|status [--waybar]|recover|create}\n' >&2
        exit 2
        ;;
    esac
  '';
}
