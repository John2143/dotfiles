{
  pkgs,
  lib,
  compName,
  ...
}: let
  # Explicit per-host allowlist, never "anything with a wheel": the office volume knob sits
  # on the AKKO keyboard and must never be grabbed. The daemon additionally requires
  # BTN_LEFT *and* REL_WHEEL on a node, because one VID:PID exposes both a mouse and a
  # keyboard node on each host (grabbing the keyboard node would break typing).
  devices =
    if compName == "office"
    then [ "046d:c547" ]
    else if compName == "arch"
    then [ "046d:c08b" ]
    else [];

  autoclicker-menu-toggle = pkgs.writeShellApplication {
    name = "autoclicker-menu-toggle";
    runtimeInputs = with pkgs; [jq coreutils];
    text = ''
      cursor=$(hyprctl cursorpos -j 2>/dev/null || true)
      screen=$(hyprctl monitors -j 2>/dev/null | jq -r --arg c "$cursor" '
        ($c | fromjson? // {x: -1, y: -1}) as $cur
        | map(select(.x <= $cur.x and $cur.x < (.x + .width) and .y <= $cur.y and $cur.y < (.y + .height)))
        | if length > 0 then .[0].name else "" end' 2>/dev/null || true)

      if [ -n "$screen" ]; then
        eww open autoclicker-menu --toggle --screen "$screen"
      else
        eww open autoclicker-menu --toggle
      fi
      eww poll ac_tick >/dev/null 2>&1 || true
    '';
  };

  autoclicker-target = pkgs.writeShellApplication {
    name = "autoclicker-target";
    runtimeInputs = with pkgs; [jq slurp coreutils autoclicker];
    text = ''
      case "''${1:-}" in
        focused)
          window=$(hyprctl -j activewindow 2>/dev/null || echo '{}')
          addr=$(printf '%s' "$window" | jq -r '.address // ""')
          if [ -z "$addr" ] || [ "$addr" = "null" ]; then
            exit 0
          fi
          label=$(printf '%s' "$window" | jq -r '((.class // "?") + ": " + (.title // ""))[0:40]')
          autoclicker target set "$addr" "$label"
          ;;
        pick)
          # slurp has no "which box did I pick" output, so every client becomes a slurp
          # region and the chosen geometry is matched back against the client list.
          clients=$(hyprctl -j clients 2>/dev/null || echo '[]')
          mapfile -t regions < <(printf '%s' "$clients" | jq -r '
            .[] | select(.mapped == true and .hidden == false)
            | "-r", ((.at[0] | tostring) + "," + (.at[1] | tostring) + " "
                     + (.size[0] | tostring) + "x" + (.size[1] | tostring))')
          [ "''${#regions[@]}" -gt 0 ] || exit 0
          selection=$(slurp -f '%x %y %w %h' "''${regions[@]}" 2>/dev/null) || exit 0
          [ -n "$selection" ] || exit 0
          mapfile -t picked < <(printf '%s' "$clients" | jq -r --arg sel "$selection" '
            ($sel | split(" ") | map(tonumber)) as [$x, $y, $w, $h]
            | [ .[] | select(.mapped == true and .hidden == false)
                | select((.at[0] | tonumber) == $x and (.at[1] | tonumber) == $y
                         and (.size[0] | tonumber) == $w and (.size[1] | tonumber) == $h) ]
            | sort_by(.focusHistoryID) | .[0] // empty
            | .address, ((.class // "?") + ": " + (.title // ""))[0:40]')
          [ "''${#picked[@]}" -gt 0 ] || exit 0
          autoclicker target set "''${picked[0]}" "''${picked[1]:-}"
          ;;
        any)
          autoclicker target any
          ;;
        clear)
          autoclicker target none
          ;;
        *)
          echo "usage: autoclicker-target {focused|pick|any|clear}" >&2
          exit 2
          ;;
      esac
    '';
  };

  autoclicker-eww-sync = pkgs.writeShellApplication {
    name = "autoclicker-eww-sync";
    runtimeInputs = with pkgs; [eww coreutils autoclicker];
    text = ''
      mode=$(autoclicker get mode 2>/dev/null) || mode="off"
      button=$(autoclicker get button 2>/dev/null) || button="left"
      interval=$(autoclicker get interval 2>/dev/null) || interval="500"
      target=$(autoclicker get target 2>/dev/null) || target="any"

      on="◉"
      off="◎"
      m_off=$off m_left=$off m_right=$off m_timer=$off
      case "$mode" in
        off) m_off=$on ;;
        scroll-left) m_left=$on ;;
        scroll-right) m_right=$on ;;
        timer) m_timer=$on ;;
      esac

      i100=$off i250=$off i500=$off i1000=$off
      case "$interval" in
        100) i100=$on ;;
        250) i250=$on ;;
        500) i500=$on ;;
        1000) i1000=$on ;;
      esac

      b_left=$off b_middle=$off b_right=$off
      case "$button" in
        left) b_left=$on ;;
        middle) b_middle=$on ;;
        right) b_right=$on ;;
      esac

      eww update \
        ac_mark_off="$m_off" \
        ac_mark_scroll_left="$m_left" \
        ac_mark_scroll_right="$m_right" \
        ac_mark_timer="$m_timer" \
        ac_iv_100="$i100" \
        ac_iv_250="$i250" \
        ac_iv_500="$i500" \
        ac_iv_1000="$i1000" \
        ac_btn_left="$b_left" \
        ac_btn_middle="$b_middle" \
        ac_btn_right="$b_right" \
        ac_details="Target: $target" >/dev/null 2>&1 || true
    '';
  };
in {
  # The daemon always starts in mode "off": the mode is deliberately not persisted, so a
  # relogin can never leave the wheel converted to clicks.
  systemd.user.services.autoclicker = {
    Unit = {
      Description = "Scroll-to-click autoclicker";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.autoclicker}/bin/autoclicker daemon" + lib.concatMapStrings (d: " --device ${d}") devices;
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  home.packages = [
    autoclicker-menu-toggle
    autoclicker-target
    autoclicker-eww-sync
  ];
}
