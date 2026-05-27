# Waybar Popup Windows via Hyprland Special Workspaces
#
# This module provides a pattern for opening small floating windows
# when clicking Waybar widgets. Uses Hyprland's special workspaces
# (scratchpads) so each popup is a toggle: click to open, click again
# to close.
#
# Prerequisites: alacritty (or your preferred terminal), btop, cal/coreutils
{
  pkgs,
  ...
}: let
  # ── Generic popup launcher ────────────────────────────────────────
  # Usage: waybar-popup <name> <terminal-command>
  # Opens <terminal-command> in a floating 80x24 alacritty window on
  # a special workspace named <name>.  Toggles the workspace on repeat
  # invocations.
  waybar-popup = pkgs.writeShellScriptBin "waybar-popup" ''
    set -euo pipefail
    NAME="$1"
    shift
    CMD="$*"

    # Check if this special workspace already has windows
    COUNT=$(hyprctl workspaces -j 2>/dev/null \
      | ${pkgs.jq}/bin/jq "[.[] | select(.name == \"special:$NAME\")] | length" 2>/dev/null || echo 0)

    if [ "$COUNT" -gt 0 ]; then
      # Toggle it closed
      hyprctl dispatch togglespecialworkspace "$NAME"
    else
      # Launch the app, move it to the special workspace, then show it
      alacritty \
        --class "$NAME-popup,$NAME-popup" \
        --title "$NAME" \
        -o "window.dimensions.columns=80" \
        -o "window.dimensions.lines=24" \
        -e fish -c "$CMD" &
      # Give the window time to appear
      sleep 0.3
      hyprctl dispatch movetoworkspace "special:$NAME"
      hyprctl dispatch togglespecialworkspace "$NAME"
    fi
  '';

  # ── App-specific wrappers ─────────────────────────────────────────
  toggle-btop = pkgs.writeShellScriptBin "toggle-btop" ''
    exec waybar-popup btop "btop"
  '';

  toggle-calendar = pkgs.writeShellScriptBin "toggle-calendar" ''
    exec waybar-popup calendar "cal -3 && echo && read -n1 -p 'Press any key...'"
  '';

  toggle-weather = pkgs.writeShellScriptBin "toggle-weather" ''
    exec waybar-popup weather "curl -s wttr.in/NewYork?0u || echo 'Weather unavailable'; echo; read -n1 -p 'Press any key...'"
  '';
in {
  environment.systemPackages = [
    waybar-popup
    toggle-btop
    toggle-calendar
    toggle-weather
  ];
}
