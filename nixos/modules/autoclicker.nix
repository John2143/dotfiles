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

  # The panel is a Noctalia plugin panel; Noctalia resolves its output from the focus
  # source, so the old "which monitor is the cursor on" probe is gone.
  autoclicker-menu-toggle = pkgs.writeShellApplication {
    name = "autoclicker-menu-toggle";
    runtimeInputs = [pkgs.noctalia];
    text = ''
      noctalia msg panel-toggle john/dotfiles-bar:autoclicker-panel
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
  ];
}
