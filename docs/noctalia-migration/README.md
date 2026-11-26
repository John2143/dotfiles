# Noctalia v5.6.0 full-shell migration

Reference documentation for the hard swap from **Waybar + Eww + dunst + wofi +
cliphist + hyprlock + hyprpaper + gammastep + lxqt-policykit-agent + grim/swappy**
to a single **Noctalia v5.6.0** desktop shell on Hyprland.

Status: the tree is migrated but **not rebuilt or switched**. Nothing in this
directory was produced by running the new configuration; every claim about
Noctalia behaviour is sourced from the five reports in `research/` and from the
Noctalia v5.6.0 binary/package in the pinned nixpkgs. See
[rollout-rollback.md](rollout-rollback.md) for the build/test/switch procedure.

---

## 1. What was replaced

Noctalia is one process that owns the bar, notification daemon, lock screen,
wallpaper, launcher, clipboard history, screenshots, night light, polkit agent,
OSD, session menu, control center and tray. The old stack was nine independent
programs, three custom bars' worth of shell scripts, and six systemd units that
had to be restarted in the right order on every theme change.

| Old component | Replacement | Gate / key |
|---|---|---|
| Waybar (`nixos/modules/waybar.nix`) | Noctalia bar (`[bar.default]`) + built-in widgets + three Luau plugins | `[bar]`, `[widget.*]` |
| Eww (`nixos/modules/eww.nix`, `eww/`) | Native Luau `[[panel]]` entries | `john/dotfiles-bar:media-panel`, `:tailscale-panel`, `:autoclicker-panel`, `john/deskflow:panel` |
| dunst (`services.dunst`) | Noctalia notification daemon + history + DND + filters | `[notification] enable_daemon` |
| swaync (already disabled before this migration) | same as dunst | — |
| wofi / fuzzel app launcher | Noctalia launcher, `noctalia dmenu` for script menus | `[shell.launcher]` |
| cliphist + `wl-paste --watch` | Clipboard history (encrypted at rest, images, auto-paste) | `[shell] clipboard_enabled` |
| hyprlock + `hyprlock-theme` | Noctalia lock screen (PAM, ext-session-lock-v1) | `[lockscreen] enabled` |
| hyprpaper | Noctalia wallpaper per mode | `[wallpaper]` |
| gammastep | Night light on the shared `[location]` schedule | `[nightlight] enabled` |
| lxqt-policykit-agent | Noctalia polkit agent | `[shell] polkit_agent` |
| grim + slurp + swappy | Noctalia screenshot + annotation editor | `[shell.screenshot]` |
| `wf-recorder` + `juush` (`screenrec`) | **kept** — screen recording is not in Noctalia core | `.config/screenrec.sh`, `screenrec` helper |

Recording is the one surface Noctalia does not implement. It ships an official
plugin (`noctalia/screen_recorder`) around `gpu-screen-recorder`, but this repo
keeps its `screenrec` pipeline (`nixos/home.nix:36-53`) so the Temporal/juush
upload path and the existing keybinds survive unchanged.

### Why a hard swap, not coexistence

- Noctalia claims `org.freedesktop.Notifications` when the name is free
  (`[notification] enable_daemon = true`). A running dunst contests the same
  name; whichever loses silently stops displaying toasts.
- Noctalia claims `org.kde.StatusNotifierWatcher` when no watcher exists and
  otherwise registers as a client. A second tray host splits SNI icons between
  two bars.
- Two bars means two layer-shell reservations (`reserve_space = true`) and two
  sets of layer rules; the pre-migration `layerrule "blur,waybar"` targeted a
  namespace that no longer exists (the replacement blur rule matches
  `^noctalia-bar-.+$`).
- The theme pipeline (`theme-switch`) drove four bar/popup reload hooks (Waybar,
  hyprpaper, Eww, dunst); leaving those programs installed would keep half of
  them alive against a shell that owns the same surfaces.

---

## 2. Key decisions

### 2.1 Version and API pin

- **Noctalia 5.6.0** from the pinned nixpkgs (`flake.lock` nixpkgs rev
  `93a9ed0a866099a230ed5146a5bb7d16fd5c9b14`, 2026-11-21), package `pkgs.noctalia`.
  No extra flake input: the declarative config uses **Home Manager's**
  `programs.noctalia` module (`{enable, package, settings, customPalettes,
  checkConfig, systemd.enable}`), whose unit is wired to
  `config.wayland.systemd.target`. The nixpkgs NixOS module of the same name
  exists but is not used — `nixos/home.nix` is a Home Manager module.
- **`plugin_api = 43`** in all three first-party plugins. 5.6.0 supports levels
  **3–56**; 43 is the level that introduced the `surface_container` /
  `outline_variant` colour roles, which the widgets use through
  `barWidget.setColor("outline_variant")` and friends. (Level 44 is palette JSON
  format 2; the palette file is rendered by the Nix module, not by a plugin, so
  44 is not required.)
- **Do not use post-5.6.0 keys**: `color-picker` widget,
  `media.circular_album_art`, `nightlight-temperature-set/-clear`, `color-pick`.
  They exist in the rolling docs/source and are config errors on 5.6.0.

### 2.2 All non-bar surfaces adopted

Every surface the old stack provided is now native, with two deliberate
exceptions: screen recording (kept external, see above) and per-monitor static
wallpaper images (Noctalia exposes per-monitor *directories*, not per-monitor
paths; `[wallpaper]` global default + `per_monitor_directories`).

Adopted: lock screen, wallpaper, clipboard history, launcher/dmenu, screenshots
and annotation, night light, polkit agent, notification daemon, OSD, session
menu, control center, tray, media/MPRIS, workspaces, power profiles.

### 2.3 Three Eww panels ported to native Luau panels

The Eww windows were data-rich control surfaces, not cosmetic popups. They are
rebuilt as Noctalia `[[panel]]` entries so the same helper binaries feed them:

| Eww window (`eww/eww.yuck` line) | Noctalia panel | Data / actions |
|---|---|---|
| `media-picker` (:141-224) | `john/dotfiles-bar:media-panel` | `media-picker-data players\|tabs`, `media-picker-action` |
| `tailscale` (:53-133) | `john/dotfiles-bar:tailscale-panel` | `tailscale-panel-data` (falls back to `tailscale status --json`) |
| `autoclicker-menu` (:244-343) | `john/dotfiles-bar:autoclicker-panel` | `autoclicker get/mode/set/status`, `autoclicker-target` |
| `hello-world` (:2-32) | **dropped** (demo window) | — |

In behaviour terms they are attached popups, not Eww's unfocusable
`onhoverlost` overlays: they attach to the bar, open near the click
(`placement = "attached"`, `open_near_click = true`) and stay until dismissed,
so they can hold keyboard focus for their controls. Eww's cursor-monitor
`--screen` calculation is gone.

### 2.4 Templates disabled so `theme-switch` stays authoritative

`nixos/theme-switch.sh` remains the only writer of GTK, dconf, Alacritty,
Fuzzel, tmux, nvim and Hyprland border colours. Noctalia's template layer must
therefore never run:

```toml
[theme]
source             = "custom"
custom_palette     = "CatppuccinDotfiles"
mode               = "dark"
shell_mode         = "follow"
sync_color_scheme  = false

[theme.templates]
enable_builtin_templates   = false
enable_community_templates = false
builtin_ids                = []
community_ids              = []
```

Reasons, from `research/theming.md` findings 10–11:

- The `alacritty` built-in appends an `import` by writing through
  `~/.config/alacritty/alacritty.toml`, which is a
  `mkOutOfStoreSymlink` into this git checkout — it would edit a tracked file.
- The `gtk3`/`gtk4` built-ins create `gtk.css`, append `@import` and write
  `gtk-theme`/`color-scheme` through GSettings/dconf, duplicating and racing
  `theme-switch`.
- The `hyprland` built-in appends `require("noctalia").apply_theme()` to
  `hyprland.lua`, which this repo renders and `dofile`s itself.
- `sync_color_scheme` writes `org.gnome.desktop.interface color-scheme` even
  with every template disabled. It must be `false` or the next Noctalia start
  can flip the session back after a `theme-switch toggle`.
- Waybar, Eww, wofi, dunst, hyprlock and hyprpaper have no Noctalia template at
  all, so templates cannot replace the old pipeline for them anyway.

The palette itself is safe to share: `[theme] source = "custom"` +
`custom_palette = "CatppuccinDotfiles"` reads
`~/.config/noctalia/palettes/CatppuccinDotfiles.json`, written by
`programs.noctalia.customPalettes` from the 26-key `palettes` table in
`nixos/modules/noctalia.nix` (kept byte-identical with
`nixos/modules/theme.nix:24-81`, Mocha for dark and Latte for light).

### 2.5 Custom palette JSON must contain `terminal` in both modes

`parsePaletteFile` in `src/theme/fixed_palette_json.cpp` rejects a mode object
that has no `terminal` object — the docs present `terminal` as optional, the
parser does not. The generated `CatppuccinDotfiles.json` therefore has, under
**each** of `dark` and `light`:

- the 16 roles: `primary`, `on_primary`, `secondary`, `on_secondary`,
  `tertiary`, `on_tertiary`, `error`, `on_error`, `surface`, `on_surface`,
  `surface_container`, `on_surface_variant`, `outline_variant`, `shadow`,
  `hover`, `on_hover`;
- a `terminal` object with `background`, `foreground`, `cursor`,
  `cursor_text`, `selection_bg`, `selection_fg`, and `normal` + `bright`
  objects each with `black`, `red`, `green`, `yellow`, `blue`, `magenta`,
  `cyan`, `white`. The module maps Catppuccin names onto these:
  `magenta = pink`, `cyan = teal`, `cursor = rosewater`, `white = subtext1`
  (normal) / `subtext0` (bright), matching what `theme.nix` renders into
  `alacritty.toml`.

Missing *role* keys load as empty colours rather than failing; a missing
`terminal` rejects the whole palette and silently falls back to the built-in
Noctalia palette. `version = 2` selects the current format; the top-level
`base = "Catppuccin"` only groups it in the picker.

The 16 roles are a Material-style mapping, not a rename of the Catppuccin keys:
`primary = mauve`, `secondary = peach`, `tertiary = teal`, `error = red`,
`surface = base`, `on_surface = text`, `surface_container = surface0`,
`on_surface_variant = subtext0`, `outline_variant = surface2`,
`shadow = crust`, `hover = teal`. `on_primary`, `on_secondary`, `on_tertiary`,
`on_error` and `on_hover` are all `crust`. `roleColours` in
`nixos/modules/noctalia.nix:89` is the single source for both flavours.

### 2.6 Manual-only lock screen invariant preserved

The session has never auto-locked and must not start now:

```toml
[lockscreen]
enabled             = true
lock_before_suspend = false
dnd                 = false
grace_period_seconds = 0
blurred_desktop     = false
# fingerprint is left at its default (true)

[idle.behavior.lock]
enabled = false
[idle.behavior.screen-off]
enabled = false
[idle.behavior.lock-and-suspend]
enabled = false
```

- `enabled = true` is required: it is the master switch for the lock surface,
  `loginctl lock-session` handling and `noctalia msg session lock`.
- `lock_before_suspend = false` disables Noctalia's native logind
  sleep-delay inhibitor, preserving the old "suspend without locking" behaviour
  (hypridle was deliberately never enabled; `nixos/home.nix:686-691`).
- `hypr-blank` (`nixos/home.nix`) refuses DPMS off when either logind reports
  `LockedHint=yes` **or** `noctalia msg status | jq .locked` is `true`. The old
  `pgrep -x hyprlock` arm is gone; the dual check covers the window where
  Noctalia is locked but logind has not been updated yet. Both paths are
  documented in the script's notification text.
- Lock binds keep `{ locked = true; }` so they fire while already locked.

### 2.7 Clipboard storage key

```toml
[storage]
key_source = "secret-service"
key_file   = ""
```

Clipboard history, notification history and the calendar cache are encrypted at
rest with keys derived from a storage master key. `secret-service` keeps the
master key in the session keyring (GNOME Keyring/KWallet); `key_source = "file"`
with a 64-hex-character file is the agenix path. `secret-service` is chosen
because this workstation already runs a keyring; if the keyring is not the one
PAM unlocks at login, history silently becomes session-only after each reboot —
switch to `key_source = "file"` if that is observed.

### 2.8 Plugins are a local path source, enabled by id

`noctalia-plugins/` is referenced from the Noctalia config as a `path` source
pointing at `${../../noctalia-plugins}` (relative to
`nixos/modules/noctalia.nix`), with:

```toml
[plugins]
enabled     = ["john/deskflow", "john/voxtype", "john/dotfiles-bar"]
auto_update = "none"

[[plugins.source]]
name     = "dotfiles"
kind     = "path"
location = "/nix/store/...-noctalia-plugins"   # ${../../noctalia-plugins}
enabled  = true
```

An explicit `[[plugins.source]]` list **replaces** the built-in `official` and
`community` git sources, so neither exists in this config. A `path` source is
read-only and has no revisions, so a rebuild is what updates the plugins; that
is also why `auto_update = "none"` is correct rather than a loss.

`programs.noctalia.checkConfig = true` runs `noctalia config validate` against
the generated TOML **at build time**, so an unknown 5.6.0 key fails the build
instead of silently doing nothing.

---

## 3. Architecture

```
Hyprland (Lua config)
  │  hl.on("hyprland.start") / systemd unit  ──────────────► noctalia (single process)
  │                                                            │
  │  .socket.sock / .socket2.sock (no hyprctl)                 ├─ bar: [bar.default]
  │◄───────────────────────────────────────────────────────────┤    ├ built-in widgets (clock, tray, volume, …)
  │                                                            │    └ plugin widgets ──► Luau VM per entry
  │                                                            │                          │ runAsync/runStream
  │                                                            │                          ▼
  │                                                            │                    status-helpers binaries
  │                                                            │                    (media-player, tailscale-*,
  │                                                            │                     deskflow-ctl, ipad-display,
  │                                                            │                     temporal-status, …)
  │                                                            ├─ notification daemon (org.freedesktop.Notifications)
  │                                                            ├─ lock screen (ext-session-lock-v1, PAM)
  │                                                            ├─ wallpaper (wlr-layer-shell + screencopy)
  │                                                            ├─ clipboard (ext-data-control-v1)
  │                                                            ├─ tray (StatusNotifierWatcher/Host)
  │                                                            └─ panels (launcher, control-center, clipboard,
  │                                                                 wallpaper, session + 4 plugin panels)
  │
  └─ theme-switch (root of colours) ──► ~/.local/state/theme/current/*
         │                                   ├ alacritty.toml, fuzzel.ini, tmux.conf, hyprland.lua
         │                                   └ wallpaper-path
         ├─ noctalia msg theme-mode-set <dark|light>
         └─ noctalia msg wallpaper-set <path>
```

IPC is a line-oriented Unix socket at
`${XDG_RUNTIME_DIR}/noctalia-${WAYLAND_DISPLAY}.sock`, not D-Bus. Every
`noctalia msg …` invocation needs the session environment; a systemd timer or
SSH command without `XDG_RUNTIME_DIR`/`WAYLAND_DISPLAY` reaches `wayland-0` or
fails with `error: noctalia is not running`.

---

## 4. File map

### Added

| Path | Purpose |
|---|---|
| `nixos/modules/noctalia.nix` | Declarative Noctalia config (452 lines): `settings` = `[shell]`, `[storage]`, `[theme]` (custom palette `CatppuccinDotfiles`), `[location]`, `[nightlight]`, `[weather]`, `[lockscreen]`, `[wallpaper]`, `[dock]`, `[notification]` + LHB filter, `[osd]`, `[plugins]`, `[bar.default]` (start/center/end + capsule groups) and `[widget.*]` instances. Generates the palette JSON via `customPalettes`; enables `programs.noctalia` with `systemd.enable`, `checkConfig`; adds `TimeoutStopSec = 10` and a pinned unit `PATH`. |
| `nixos/modules/status-helpers.nix` | One binary per legacy helper. See the table below. |
| `noctalia-plugins/deskflow/` | `plugin.toml`, `widget.luau` (`bar`), `panel.luau` (`panel`), `translations/en.json`. |
| `noctalia-plugins/voxtype/` | `plugin.toml`, `widget.luau` (`bar`), `translations/en.json`. |
| `noctalia-plugins/dotfiles-bar/` | `plugin.toml`, `lib/waybar_json.luau`, 9 widgets, 3 panels, `translations/en.json`. |
| `docs/noctalia-migration/` | This documentation plus `research/`. |

`status-helpers.nix` entry points (line numbers in that file):

| Binary | Line | Replaces |
|---|---|---|
| `copy-date` | 34 | Waybar `custom/clock-date` right-click (`waybar.nix:24`) |
| `media-player` | 43 | Waybar `custom/media` body (`waybar.nix:34-260`) |
| `media-picker-data` | 267 | Eww defpoll `media-picker-data` (`eww.nix:110-178`) |
| `media-picker-action` | 337 | Eww row actions (`eww.nix:180-254`) |
| `nix-update-status` | 415 | Waybar `nix-update-status` (`waybar.nix:202-217`) |
| `tailscale-status` | 433 | Waybar `custom/tailscale` body (`waybar.nix:282-326`) |
| `tailscale-panel-data` | 482 | Eww `tailscale-eww-update` (`eww.nix:5-73`) |
| `tailscale-toggle` | 547 | Eww connect/disconnect (`eww.nix:75-88`) |
| `tailscale-exit-node` | 565 | Eww/wofi exit-node picker (`waybar.nix:327-361`) |
| `temporal-status` | 589 | Waybar `custom/temporal` |
| `ipad-display` | 603 | `nixos/packages/ipad-display.nix` (isDesk only) |
| `deskflow-ctl` | 606 | `nixos/packages/deskflow-ctl.nix` (isDesk only) |

`ipad-display` and `deskflow-ctl` are only installed when `compName` is `arch`
or `office` (`status-helpers.nix:625-628`).

`nixos/modules/noctalia.nix` section index (line numbers):

| Section | Line |
|---|---|
| `palettes` (Mocha/Latte, 26 keys) | 27 |
| `roleColours` (Material role → Catppuccin) | 89 |
| `palette` (format 2 + `terminal`) | 148 |
| `settings.shell` | 156 |
| `settings.storage` | 168 |
| `settings.theme` (custom palette, templates off) | 170 |
| `settings.location` | 191 |
| `settings.nightlight` | 197 |
| `settings.weather` | 203 |
| `settings.lockscreen` | 209 |
| `settings.wallpaper` / `settings.dock` | 220 / 222 |
| `settings.notification` (incl. LHB filter at 234) | 224 |
| `settings.osd` | 244 |
| `settings.plugins` | 249 |
| `settings.bar.default` (start/center/end, capsule groups at 312) | 266 |
| `settings.widget` | 328 |
| `programs.noctalia` (enable, systemd, checkConfig, customPalettes) | 434 |

### Modified

| Path | Change |
|---|---|
| `nixos/home.nix` | Imports `./modules/noctalia.nix` + `./modules/status-helpers.nix` and drops `./modules/waybar.nix` / `./modules/eww.nix`; removes `wofi`, `cliphist`, `gammastep`, `hyprlock`, `hyprpaper`, `grim` (and the commented `swappy`) from the package list; removes `lxqt-policykit-agent` and both `wl-paste --watch cliphist` lines from the `hyprland.start` hook; `screenrec`'s runtime inputs switch from `pkgs.dunst` to `pkgs.libnotify`; `waybar` layer rules become the two Noctalia layer rules; `hypr-blank` gains the `noctalia msg status` lock check; adds `persistent = true` to every workspace rule; binds: `SUPER+Space` launcher, `SUPER+V` clipboard, `SUPER+SHIFT+N` notifications, `SUPER+comma` settings, `ALT+Tab` window switcher, screenshot binds, `CTRL+ALT+L` and `SUPER+F20` `session lock`, volume keys to `noctalia msg`; drops the dunst service block. |
| `nixos/modules/theme.nix` | Removes the `wofi.css`, `dunst.conf`, `hyprlock.conf`, `waybar.css`, `eww.scss` and `hyprpaper.conf` render targets and their `xdg.configFile` links; removes `hyprlock-theme` and the `hyprpaper` unit; adds a `wallpaper-path` file (`theme.nix:208`) and puts `pkgs.noctalia` on `theme-switch`'s PATH (`theme.nix:240`). |
| `nixos/theme-switch.sh` | Replaces the waybar/eww/dunst/hyprpaper reload block with `noctalia msg theme-mode-set "$mode"` and `noctalia msg wallpaper-set "$wall"` (`theme-switch.sh:64-70`). GTK/dconf/tmux/nvim/Hyprland reload still runs. |
| `nixos/modules/keybind.nix` | `signal_waybar` is renamed `signal_bar` and calls `noctalia msg plugin john/dotfiles-bar:thermostat all refresh`; `SUPER+F20` becomes `noctalia msg session lock`; `hass-macro`'s runtime inputs swap `procps` for `noctalia`. `hass_notify` keeps its per-tag coalescing: it stores the returned notification id under `$XDG_RUNTIME_DIR/hass-notify-<tag>` and passes `-r`, so repeats replace the previous toast through the standard `replaces_id` field. |
| `nixos/modules/autoclicker.nix` | `autoclicker-menu-toggle` keeps its name but now calls `noctalia msg panel-toggle john/dotfiles-bar:autoclicker-panel` instead of the Eww cursor-monitor probe; `autoclicker-eww-sync` is deleted; the daemon and `autoclicker watch` stream are unchanged. |
| `nixos/shared-configuration.nix` | `weather-status` (wttr.in helper) removed; `security.pam.services.hyprlock` removed — Noctalia's helper uses the `login` PAM service, not a bespoke `hyprlock` one. |
| `nixos/home-cli.nix` | `lxqt.lxqt-policykit` removed (Noctalia owns the agent). |
| `.config/screenrec.sh`, `.config/juush.bash` | `dunstify` → `notify-send`; the notification-id reuse logic is unchanged. |

`flake.nix` is **not** modified: Noctalia 5.6.0 comes from the pinned nixpkgs,
and `./nixos/modules/waybar-popup.nix` stays imported on `arch`/`office`
because `toggle-btop`, `toggle-calendar` and `toggle-weather` are still used by
the Noctalia widgets.

### Deleted

| Path | Why |
|---|---|
| `nixos/modules/waybar.nix` | Bar, helper scripts and signals superseded by built-ins + plugins + `status-helpers.nix`. |
| `nixos/modules/eww.nix` | Panels ported; helpers moved to `status-helpers.nix`. |
| `nixos/modules/swaync.nix` | Never enabled (upstream build was broken); the file is gone with the rest of the notification stack. |
| `eww/` (`eww.yuck`, `eww.scss`, `check-css.py`) | No Eww process. |
| `.config/waybar/style.css` | No Waybar; Noctalia derives bar styling from the palette. |
| `.config/dunst/dunstrc` | Noctalia owns notifications and their styling; no `dunst` service. |
| `.config/swaync/style.css` | swaync removed. |
| `.config/hypr/hyprlock.conf` | No hyprlock; the lock screen is Noctalia's. |

`nixos/modules/waybar-popup.nix` is **kept** and still imported by the
`arch`/`office` host module lists: `toggle-btop`, `toggle-calendar` and
`toggle-weather` are the scratchpad helpers the Noctalia widget actions call.

Package expressions removed from the module lists: `waybar`, `eww`, `dunst`,
`wofi`, `cliphist`, `hyprlock`, `hyprpaper`, `gammastep`,
`lxqt.lxqt-policykit`, `grim`, `swappy`. `slurp`, `fuzzel`, `wl-clipboard`,
`wf-recorder`, `juush`, `playerctl`, `pactl`, `pamixer` stay because
`screenrec`/`juush`/media helpers/keybinds still use them.

---

## 5. Known behavioural changes and tradeoffs

### 5.1 `x-dunst-stack-tag` is ignored, so coalescing moved to `replaces_id`

`hass_notify` used to send `notify-send -h "string:x-dunst-stack-tag:hass-$1" …`.
That hint is a dunst extension; `org.freedesktop.Notifications` has no stack-tag
concept, so Noctalia ignores it silently and would show one toast per call.

`nixos/modules/keybind.nix` now does the coalescing itself: it keeps the last
notification id per tag in `$XDG_RUNTIME_DIR/hass-notify-<tag>` and passes
`-r <id>` on the next call, so HASS updates morph the existing toast through the
standard `replaces_id` field. Verified against the running daemon —
`notify-send -p` then `notify-send -p -r <id>` returns the same id.

Other things learned from the notification-layer prototypes, applied here:

- `[notification] layer = "overlay"`. The default `top` puts toasts *below*
  fullscreen windows, so alerts were invisible over a fullscreen game or video.
- `[notification] follow_focused_output = true`, matching dunst's
  `follow = keyboard` on a two-monitor desktop.
- Never put `allowed_urgencies` on a catch-all filter: 5.6.0's
  `resolveNotificationFilter()` does not fall through on an urgency mismatch, it
  suppresses with `fullySuppress = true` and drops every `low`/`normal`
  notification even with DND off. First match wins, so `filter_order` is
  load-bearing, and `play_sound` defaults to `true` per filter.
- `notify-send --wait` / `-A` do **not** hang: timed-out notifications are closed
  on D-Bus by the daemon (verified live — a 3 s toast released `--wait` after 3 s).
- Notification summaries/bodies are passed after `--` in `.config/screenrec.sh`
  so text starting with `-` is not parsed as an option.

### 5.2 Tooltips are plain text, not Pango markup

Waybar tooltips rendered Pango markup, and several helpers relied on it
(`<span>`, `&amp;`, multi-line blocks in the media/vast/weather tooltips). The
Luau widgets pass tooltip strings through `barWidget.setTooltip`, which renders
plain text: markup is stripped or shown literally and long multi-line tooltips
are not laid out like the GTK tooltip. `GTK_TOOLTIP_TIMEOUT=0` no longer exists,
so tooltips also auto-hide.

Consequence: helper output in `status-helpers.nix` is deliberately plain
(`tooltip` values contain `\n` text only). Do not reintroduce markup.

### 5.3 Hover drawers become capsule accordion groups

Waybar's `group/clock` and `group/hardware` (`waybar.nix:524-536`,
`628-641`) were hover-expand drawers with hidden children. Noctalia's
equivalent is a **capsule group with `accordion = true`**:

```toml
[[bar.default.capsule_group]]
id = "hardware"
members = ["hw_cpu", "hw_ram", "hw_temp"]
accordion = true
accordion_direction = "start"
```

The members are `hw_cpu` (`sysmon cpu_usage`), `hw_ram` (`ram_used`) and
`hw_temp` (`cpu_temp`); `clock` + `clock_date` form the second group. The
expansion is Noctalia's accordion chip, not a GTK drawer, so the 300 ms
`children-class` transition and the separate `#group-*` styling are gone.

The workspace **hover taskbar** (window icons revealed from the workspace pill)
has no equivalent: there is no `taskbar` widget in this bar. If the window list
is missed, add `taskbar` as a normal (always-visible) widget.

### 5.4 `custom/newworkspace` ported, not dropped

The `✚` button is kept as a `custom_button` with the original fish one-liner:

```toml
[widget.newworkspace]
type = "custom_button"
glyph = "plus"
tooltip = "New temporary workspace"
actions.left = "exec fish -c 'set ID (math (date +%s) % 9000 + 1000); hyprctl dispatch "hl.dsp.focus({workspace="$ID"})"'"
```

It renders a static glyph and runs the command through `exec`; no plugin is
involved.

### 5.5 Bar-launched TUI scratchpads are kept

`toggle-btop`, `toggle-calendar`, `toggle-weather`
(`nixos/modules/waybar-popup.nix:47-57`) still exist and are bound to widget
actions:

- hardware group members — left click → `exec toggle-btop`;
- clock — middle click → `exec toggle-calendar`, left click → Control Center →
  Calendar;
- weather — right click → `exec toggle-weather`.

So the Alacritty-on-a-special-workspace workflow survives. `waybar-popup.nix`
therefore stays imported on `arch`/`office` even though `waybar.nix` does not;
the file name is now vestigial (the helper only needs Hyprland and Alacritty).

### 5.6 `settings.toml` beats the Nix config

Load order: built-in defaults → `/etc/xdg/noctalia/` → every
`~/.config/noctalia/*.toml` → **`~/.local/state/noctalia/settings.toml`**. The
last layer is written by the Settings GUI, the setup wizard, wallpaper
selection and `noctalia msg config-set` / `theme-mode-set` /
`color-scheme-set`. 5.6.0 has no read-only switch.

Consequences:

- A GUI click can override a Nix-managed key until the state file is cleaned.
- `theme-mode-set` (used by `theme-switch`) writes `[theme].mode` to
  `settings.toml`. That is intended here — it keeps Noctalia's shell in step
  with `theme-switch` — but it means the state file will legitimately contain a
  `theme.mode` override.
- Never symlink `settings.toml` to a store/Home-Manager path: Noctalia writes
  through a symlink to its target.
- Reconcile with `noctalia msg config-get <path>` and by deleting the offending
  key (or the file) from `~/.local/state/noctalia/settings.toml`.

### 5.7 `noctalia dmenu` requires a running shell

`tailscale-exit-node` (`status-helpers.nix:564`) and any script that used
`wofi --dmenu` now pipe into `noctalia dmenu -p …`. That command talks to the
running instance over the IPC socket: with Noctalia down it prints nothing and
the picker cancels. This is a hard dependency the old wofi pipeline did not
have. Interactive/terminal commands must still name their terminal; dmenu
`exec` actions do not open one.

### 5.8 Theme visual differences

Noctalia's built-in "Catppuccin" is a hand-tuned Mocha/Latte with non-upstream
values (`on_surface_variant` dark `#a3b4eb`, `outline_variant` dark `#4c4f69`,
`hover` = teal). The custom `CatppuccinDotfiles` palette avoids that: the 16
Material roles map onto the same Catppuccin keys as the rest of the session, so
the shell and Alacritty/GTK agree. What cannot be exact is the derived-role
layer (`primary_container`, `surface_container_high`, `surface_container_low`,
`scrim`): Noctalia derives those from the 16 inputs, and Catppuccin has no
per-role equivalent for every derived tone.

### 5.9 Other deltas

- **Media**: the Waybar tooltip listed every MPRIS player and Firefox tab. That
  list is now the `media-panel`; the bar capsule shows one player. Per-tab
  volume/mute/focus lives only in the panel, as it did in Eww.
- **Volume**: the `volume` widget keeps `sinks.fish scarlett` on left click,
  `sinks.fish bluetooth` on middle click and Control Center → Audio on right
  click. Scroll step is Noctalia's 5%, not Waybar's `scroll-step = 3`.
- **Weather**: the bar reads Open-Meteo through `[location]` (unit `imperial`,
  so the old °F display is preserved), while right-click still runs
  `toggle-weather` (wttr.in in Alacritty). The 3-day HTML **tooltip** has no
  equivalent; the widget tooltip is current conditions.
- **Tray**: SNI only. The TeamSpeak flatpak still owns
  `org.kde.StatusNotifierItem-5-1` and now appears in Noctalia's `tray`
  widget; XEmbed-only apps would have no icon.
- **Polkit**: exactly one agent. `polkit_agent = true` while
  `lxqt-policykit-agent` still runs makes one of them lose the bus name
  silently, so the old autostart line is removed.
- **Screenshots**: the built-in editor replaces swappy. The juush binds pass
  the PNG on stdin:
  `--pipe-to-command --pipe-command "fish -c 'set loc (screenshot_location); cat > $loc; juush $loc'"`
  (stdin is always PNG; `NOCTALIA_SCREENSHOT_PATH` exists but is not used here).
  `CTRL+SHIFT+5` (clipboard text → juush) is unchanged.
- **Recording**: `screenrec` and `juush.bash` now call `notify-send` instead of
  `dunstify`; the notification-id reuse (`-p`/`-r`) still morphs one slot
  through the stages.
- **Workspaces**: `label_source = "name"`, `max_label_chars = 8`,
  `focused_output_only = true`. Every `workspace_rule` gained
  `persistent = true` so empty fixed workspaces stay in the widget; the
  `default_name` rules still keep ids ordered 1–10.
- **Night light**: enabled on every host except `secu` and `arch`, matching the
  old gammastep gating; `[location]` is set by coordinates (NYC) rather than
  geocoding, `temperature_night = 3500`. Without coordinates the service has no
  schedule; `force = true` pins the night value.
- **PAM**: Noctalia's lock screen authenticates through
  `noctalia-pam-helper`, which uses NixOS's built-in `login` PAM service. The
  old `security.pam.services.hyprlock = {}` declaration is removed. A
  foreign/local build with the wrong `libpam` rejects every password (the FAQ
  documents `NOCTALIA_PAM_HELPER_PATH`).
- **Hyprland permissions**: with `ecosystem.enforce_permissions = true`,
  Noctalia needs `screencopy` (screenshots, lock backdrop) and `keyboard`
  (clipboard/launcher auto-paste, virtual keyboard
  `hl-virtual-keyboard-noctalia`). The docs' `/usr/bin/noctalia` regex does not
  match a Nix store path.

---

## 6. Research reports

| Report | Answers |
|---|---|
| [research/bar-widgets.md](research/bar-widgets.md) | The 32 built-in widget types, every config key and default gesture, the action grammar, and the proof that no core widget renders arbitrary command output (hence the plugins). |
| [research/plugins.md](research/plugins.md) | Manifest schema, the seven entry kinds, `plugin_api` levels, runtime API (`runAsync`/`runStream`/`state`/`getConfig`/`getColor`), settings and IPC semantics. |
| [research/surfaces.md](research/surfaces.md) | Lock, wallpaper, clipboard, launcher, session, OSD, tray, screenshots, night light, polkit, power profiles, weather, calendar — keys, defaults, limitations, disable semantics. |
| [research/theming.md](research/theming.md) | `[theme]` keys, palette JSON validation, template catalog and hooks, config load order, and the collision analysis with `theme-switch`. |
| [research/ipc-hyprland.md](research/ipc-hyprland.md) | All 118 IPC verbs, socket transport, Hyprland integration (layer rules, permissions, no keybind registration), D-Bus names, systemd units. |

Local inventories that fed the feature matrix: `/tmp/nf-inv-1.md` (Waybar),
`/tmp/nf-inv-2.md` (Eww), `/tmp/nf-inv-3.md` (theme), `/tmp/nf-inv-4.md`
(keybinds/startup).
