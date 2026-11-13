# System-wide light/dark theme

Runtime theme switch for the Hyprland desktops built from `nixos/home.nix`
(office, arch, and — because they import the same file — secu and term). Palette
is Catppuccin: **Latte** for light, **Mocha** for dark. Switching needs no
rebuild.

```sh
theme-switch toggle            # what SUPER+SHIFT+T and the waybar button run
theme-switch dark|light
theme-switch refresh           # re-apply the saved mode (home-manager does this on every rebuild)
theme-switch status            # waybar JSON: {"text":"☾","tooltip":…,"class":"dark"}
```

## Layout

| Path | Role |
|---|---|
| `nixos/modules/theme.nix` | the two palettes, every rendered file, the `theme-switch` package, the hyprpaper unit, the Hyprland `extraConfig` |
| `nixos/theme-switch.sh` | the script body (`writeShellApplication` supplies shebang, `set -euo pipefail`, `PATH`, shellcheck) |
| `theme-assets/{dark,light}/` | build output: one directory per mode, baked into the store |
| `~/.local/state/theme/mode` | `dark` or `light`; absent means dark |
| `~/.local/state/theme/current/` | **regular file copies** of the active mode, not store symlinks |

The copies are deliberate. Alacritty watches its import with inotify, and a
symlink swap into the store does not necessarily generate the event that a
rewritten file does.

## What follows, and how

| Surface | Mechanism |
|---|---|
| alacritty | `import = ["~/.local/state/theme/current/alacritty.toml"]`, `live_config_reload` |
| Hyprland borders | `extraConfig` appends to the generated `hyprland.lua`: `pcall(dofile, …/current/hyprland.lua)` then `hl.config(theme)`; re-runs on every `hyprctl reload` |
| hyprlock | `.config/hypr/hyprlock.conf` is a template; `theme.nix` renders it and `hyprlock-theme` passes it with `--config` |
| wallpaper | own `hyprpaper.service` with `-c …/current/hyprpaper.conf` |
| waybar | generated `style.css` begins with `@import url("file://…/current/waybar.css")`; `theme-switch` reloads the unit |
| eww | `@import "theme"` in `eww/eww.scss`, resolved by grass against `$XDG_CONFIG_HOME/eww` |
| dunst | `dunstrc.d/50-theme.conf` drop-in; `services.dunst.configFile` stays null because `-config` disables drop-ins |
| wofi, fuzzel | `~/.config/{wofi/style.css,fuzzel/fuzzel.ini}` → `mkOutOfStoreSymlink` of the state file |
| GTK3 | `~/.config/gtk-3.0/settings.ini`, written by `theme-switch` |
| GTK4 / libadwaita, Qt | dconf `org.gnome.desktop.interface color-scheme` → `xdg-desktop-portal-gtk`; Qt also needs `QT_QPA_PLATFORMTHEME=xdgdesktopportal` (set in `home.nix`) |
| nvim | `.vimrc` reads `~/.local/state/theme/mode`; catppuccin runs `flavour = "auto"` |
| tmux | the catppuccin plugin `source-file -q`s the state file *before* it loads |
| starship, fzf, bat | 16-colour palette (`--color=16`, `BAT_THEME=ansi`) |

Verified details worth keeping:

- **GTK3 has no dconf backend.** `libgtk-3.so` 3.24.52 contains `settings.ini` but
  no `org.gnome.desktop.interface` and no portal client, and Wayland has no
  XSettings. GTK4 has both, which is why only GTK3 needs `settings.ini`.
- **hyprlock has no `source` directive** (hyprlang 0.6.8 has no such keyword), so
  its config cannot include the palette; hence the `--config` wrapper.
- **All out-of-store links use absolute paths.** `mkOutOfStoreSymlink ../x` copies
  `x` into the store at build time and is therefore *not* live.

## Adding an app

1. Add a file to `render` in `nixos/modules/theme.nix`, using `@name@` for palette
   hex (`#@base@` when a `#` is needed).
2. Point the app at it with
   `config.lib.file.mkOutOfStoreSymlink "${stateDir}/current/<file>"` — absolute.
3. Add the app's reload to `apply` in `nixos/theme-switch.sh` (best effort:
   `timeout N … || true`, so the activation run never fails).

## Limits

- **Already-open GTK3 windows** (Thunar, pavucontrol, gthumb) keep the old theme
  until the app is restarted. Everything else follows the toggle live, including
  libadwaita and Qt windows (both subscribe to the portal's `SettingChanged`).
- **Firefox, Discord, TeamSpeak, Steam** keep their own themes: Firefox is
  firejailed with `dbus-user none` so the portal is unreachable, and the flatpaks
  do not follow the portal. Firefox is pinned dark in `prefs.js`.
- **Dark wallpaper** is `~/backgrounds/luna_1.png`, which only exists on hosts that
  have it; on secu/term hyprpaper fails in dark mode and systemd gives up after its
  start limit. Accepted.
- The lock screen falls back to the dark asset if the state file is missing, so the
  locker cannot fail open.

## First deploy

`QT_QPA_PLATFORMTHEME` reaches the session environment only at login: log out and
back in once. Rollback is `sudo nixos-rebuild switch --rollback`; afterwards run
`dconf reset /org/gnome/desktop/interface/{color-scheme,gtk-theme}` or GTK4/Qt stay
on the last scheme.
