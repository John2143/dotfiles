# theme-switch: runtime light/dark switch for the Hyprland desktops.
#
# Renders nothing: nixos/modules/theme.nix prebuilds both palettes and exposes
# them as $THEME_ASSETS/{dark,light}/<file>. This script copies one variant into
# ~/.local/state/theme/current/ (regular files, so inotify watchers fire), records
# the mode in ~/.local/state/theme/mode, and asks each app to reload.
#
# Usage: theme-switch dark|light|toggle|refresh|status

state="${XDG_STATE_HOME:-$HOME/.local/state}/theme"
mode_file="$state/mode"
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

current_mode() {
  local m=""
  if [ -r "$mode_file" ]; then m="$(head -n1 "$mode_file")"; fi
  if [ "$m" = light ]; then echo light; else echo dark; fi
}

write_gtk_settings() {
  local mode="$1" dir theme prefer
  if [ "$mode" = light ]; then theme=adw-gtk3; prefer=0; else theme=adw-gtk3-dark; prefer=1; fi
  # GTK3 does not read dconf (its binary has no org.gnome.desktop.interface), so the
  # theme name has to come from settings.ini. GTK4 has both sources; settings.ini is
  # harmless there and covers non-libadwaita GTK4 apps.
  for dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
    mkdir -p "$dir"
    {
      printf '[Settings]\n'
      printf 'gtk-theme-name=%s\n' "$theme"
      printf 'gtk-application-prefer-dark-theme=%s\n' "$prefer"
    } > "$dir/.settings.ini.tmp"
    mv -f "$dir/.settings.ini.tmp" "$dir/settings.ini"
  done
}

apply() {
  local mode="$1" f name scheme gtk_name sock
  mkdir -p "$state/current"
  exec 9>"$state/.lock"
  flock -w 10 9

  for f in "$THEME_ASSETS/$mode"/*; do
    name="$(basename "$f")"
    install -m 0644 "$f" "$state/current/.$name.tmp"
    mv -f "$state/current/.$name.tmp" "$state/current/$name"
  done
  printf '%s\n' "$mode" > "$state/.mode.tmp"
  mv -f "$state/.mode.tmp" "$mode_file"

  # Best effort from here on: this also runs from activation, where there is no
  # session bus, no compositor and no tmux server.
  write_gtk_settings "$mode" || true

  if [ "$mode" = light ]; then scheme="prefer-light"; gtk_name="adw-gtk3"; else scheme="prefer-dark"; gtk_name="adw-gtk3-dark"; fi
  timeout 5 dconf write /org/gnome/desktop/interface/color-scheme "'$scheme'" >/dev/null 2>&1 || true
  timeout 5 dconf write /org/gnome/desktop/interface/gtk-theme "'$gtk_name'" >/dev/null 2>&1 || true

  if [ -d "$runtime/hypr" ]; then
    timeout 5 hyprctl instances -j 2>/dev/null | jq -r '.[].instance' 2>/dev/null | while read -r inst; do
      timeout 5 hyprctl -i "$inst" reload config-only >/dev/null 2>&1 || true
    done || true
  fi
  timeout 10 systemctl --user try-reload-or-restart waybar.service >/dev/null 2>&1 || true
  timeout 10 systemctl --user try-restart hyprpaper.service >/dev/null 2>&1 || true
  timeout 5 eww reload >/dev/null 2>&1 || true
  timeout 5 dunstctl reload >/dev/null 2>&1 || true

  if timeout 5 tmux has-session >/dev/null 2>&1; then
    # catppuccin sets the @thm_* options with `set -ogq`, which keeps the value
    # already set; clear them so the re-source picks up the new flavour.
    tmux show-options -g 2>/dev/null | awk '$1 ~ /^@thm_/ {print $1}' | while read -r opt; do
      tmux set-option -gu "$opt" || true
    done || true
    timeout 10 tmux source-file "$HOME/.config/tmux/tmux.conf" >/dev/null 2>&1 || true
  fi

  if command -v nvim >/dev/null 2>&1; then
    shopt -s nullglob
    for sock in "$runtime"/nvim.*.0 "$runtime"/*/nvim.*.0; do
      timeout 2 nvim --server "$sock" --remote-expr "execute('set background=$mode | colorscheme catppuccin')" >/dev/null 2>&1 || true
    done
  fi
}

case "${1:-}" in
  dark|light) apply "$1" ;;
  toggle) if [ "$(current_mode)" = light ]; then apply dark; else apply light; fi ;;
  refresh) apply "$(current_mode)" ;;
  status)
    m="$(current_mode)"
    if [ "$m" = light ]; then icon="☀"; else icon="☾"; fi
    printf '{"text":"%s","tooltip":"Theme: %s (click to toggle)","class":"%s"}\n' "$icon" "$m" "$m"
    ;;
  *) echo "usage: theme-switch dark|light|toggle|refresh|status" >&2; exit 2 ;;
esac
