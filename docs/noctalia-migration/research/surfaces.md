# Noctalia v5.6.0 — Non-bar surfaces: parity review against the current stack

Research target: **Noctalia 5.6.0**, the C++/OpenGL ES Wayland shell (`noctalia` binary), matching the `noctalia`
5.6.0 package in the pinned nixpkgs (rev `93a9ed0a8660`, 2026-11-21). Citations use the version-pinned docs prefix
`https://docs.noctalia.dev/noctalia/v5.6.0/...`; where a default is not stated on the docs page it was read from the
`v5.6.0` source tag. Research date: 2026-11-25.

Everything below is about *replacing*: hyprlock, hyprpaper, cliphist+wofi, wofi/fuzzel, grim/slurp/screenrec,
gammastep, lxqt-policykit-agent, the MPRIS and system-tray bar modules, the power/session menu, and the
brightness/volume OSDs.

## Scope and method

- Read the v5.6.0 docs pages for shell settings, dock, launcher, wallpaper, control center, the relevant widget and
  service pages, IPC, keys/Secret Service, the official-plugins catalogue, and the FAQ.
- Cross-checked every default quoted here against the v5.6.0 source tag (`src/config/config_types.h`,
  `src/config/schema/config_schema_*.cpp`), because several docs code blocks are abbreviated.
- Confirmed protocol/implementation claims in source (`src/shell/lockscreen/lock_screen.cpp`,
  `src/shell/wayland/clipboard_globals.cpp`, `src/dbus/polkit/`, `src/auth/`).
- Probes for negative claims are stated inline with the command and its output.

One structural fact drives most of the parity analysis: **there is one process and one config stack.** Every surface
listed here is a layer-shell surface (or a D-Bus service) inside the single `noctalia` process, configured from the
same TOML merge (`~/.config/noctalia/*.toml` < `~/.local/state/noctalia/settings.toml`). There is no per-surface
binary to start, stop, or supervise, and no per-surface systemd unit to drop. See
[How configuration works](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/).

## Parity summary

| Today | Noctalia surface | Default | Config gate | Verdict |
|---|---|---|---|---|
| hyprlock | Lock screen (`[lockscreen]`) | `enabled = true` | `[lockscreen] enabled` | Full replacement; PAM + fingerprint, ext-session-lock-v1 |
| hyprpaper | Wallpaper (`[wallpaper]`) | `enabled = true` | `[wallpaper] enabled` | Full replacement; per-monitor *image* choice is GUI state, not config |
| cliphist + wofi | Clipboard history panel | `clipboard_enabled = true` | `[shell] clipboard_enabled` | Full replacement; encrypted at rest, images, auto-paste |
| wofi / fuzzel | Launcher + `noctalia dmenu` | always available | none (no on/off key) | Full replacement; dmenu-compatible, Luau plugin providers |
| grim + slurp + swappy/satty | Screenshot + annotation editor | always available | `[shell.screenshot]` policy | Full replacement; built-in editor, 12 tools + backdrop |
| wf-recorder + wrapper script | **not in core** — official plugin `noctalia/screen_recorder` | plugin disabled | plugin enable | Replacement only with `gpu-screen-recorder` installed |
| gammastep | Night light (`[nightlight]`) | `enabled = false` | `[nightlight] enabled` | Replacement where `wlr-gamma-control` exists |
| lxqt-policykit-agent | Polkit agent (`[shell] polkit_agent`) | **`false`** | `[shell] polkit_agent` | Must be explicitly enabled; leave only one agent |
| MPRIS bar module | Media widget + Control Center Media tab | widget placement | none (`[shell.mpris] blacklist` filters) | Replacement; no module config beyond a player blacklist |
| Tray bar module | Tray widget (SNI) | widget placement | none | Replacement for SNI apps only |
| wlogout / custom power menu | Session panel (`[shell.session]`) | five actions | `[[shell.session.actions]]` | Replacement; actions are configurable/disableable |
| swayosd / custom OSD | OSD (`[osd]`, `[osd.kinds]`) | all kinds on | `[osd] enabled`, per-kind | Superset of brightness/volume OSDs |

## Surfaces

### 1. Lock screen (replaces hyprlock)

**Keys and defaults** (`[lockscreen]`, [Shell → Lock screen](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/#lock-screen)):

```toml
[lockscreen]
enabled               = true
lock_before_suspend   = true
dnd                   = false
grace_period_seconds  = 0
fingerprint           = true
allow_empty_password  = false
blurred_desktop       = false
transition            = ["fade", "wipe", "disc", "stripes", "zoom", "honeycomb", "vortex", "pixel", "diamond", "golden", "melt", "crt"]
transition_duration   = 1500
edge_smoothness       = 0.3
blur_intensity        = 0.5
tint_intensity        = 0.3
tint_color            = "surface"
wallpaper             = ""
monitors              = []
```

**Capabilities.**

- Uses `ext-session-lock-v1`; the docs' disable text is explicit that turning it off means "no `ext-session-lock-v1`
  engagement, no logind lock/unlock integration". Source confirms the protocol path
  (`ext_session_lock_manager_v1_lock`, `ext_session_lock_v1_unlock_and_destroy` in `src/shell/lockscreen/lock_screen.cpp`).
- **Lock before suspend is native and on by default.** Noctalia holds a logind sleep-delay inhibitor and locks on
  `PrepareForSleep` (lid close, `systemctl suspend`, hibernate). It waits for the lock frame on every output before
  releasing the inhibitor, bounded by logind's `InhibitDelayMaxSec` (default 5 s). This is the piece that currently
  requires hypridle or a `systemd` sleep hook; with Noctalia it needs no extra daemon.
- **PAM.** Authentication runs in `noctalia-pam-helper` against the PAM service chosen at build time
  (`-Dpam_service`, `"login"` by default). After a successful unlock Noctalia asks the same stack to refresh
  credentials (Kerberos tickets, PAM-integrated keyrings/GPG). Source comment in `lock_screen.cpp`:
  "PAM runs in noctalia-pam-helper against the service set at build time (`-Dpam_service`, `"login"` by default)".
- **Fingerprint.** `fingerprint = true` offers PAM fingerprint login. Noctalia drives the reader over D-Bus itself and
  strips `pam_fprintd` from the helper's stack ("the two can't share the sensor"), per the same source comment. So a
  `pam_fprintd` line is neither needed nor used by Noctalia's own prompt, while a running fprintd daemon and an
  enrolled finger are still required.
- **Per-output lock screen widgets** (`[lockscreen_widgets]`, [Lockscreen widgets](https://docs.noctalia.dev/noctalia/v5.6.0/lockscreen/widgets/)):
  same widget types as desktop widgets (clock, weather, media, sysmon, label), plus a movable `login_box` per output,
  with an editor that is only available while unlocked. That covers hyprlock's custom-label/clock blocks.
- `grace_period_seconds` reproduces hyprlock's "initial input" passwordless window (1–60 s); it is revoked on any
  sleep transition and on resume.
- Session actions render as lock-screen buttons; per-action `lockscreen_shortcut` allows e.g. suspend on `Escape`.
- Optional blurred pre-lock desktop capture (`blurred_desktop`) — requires screencopy.

**Limitations.**

- Depends on the compositor implementing `ext-session-lock-v1`; this is fine on Hyprland/Sway/niri/Umbriel, absent or
  partial elsewhere. On KWin the docs list lock desktop capture as unavailable without screencopy.
- A locally-built/foreign `noctalia` whose helper links the wrong `libpam` rejects every password; the FAQ requires
  building `noctalia-pam-helper` on the host and pointing `NOCTALIA_PAM_HELPER_PATH` at it. This matters for a Nix
  package built against a non-NixOS host, and it is the single most likely failure mode of the parity swap.
- No failed-attempt counter or per-user avatar list documented; the login box is a single password field (+ fingerprint
  + optional empty-password submit for security keys).
- `blurred_desktop`/transitions degrade gracefully: if capture fails the lock falls back to the per-output wallpaper.

**Disabling cleanly.** `[lockscreen].enabled = false` is a real master switch: lock actions become no-ops (idle lock,
session panel, launcher, `noctalia msg session lock`) and lock-and-suspend degrades to suspend-only. There is no
separate daemon left running.

### 2. Wallpaper (replaces hyprpaper)

**Keys and defaults** ([Wallpaper & backdrop](https://docs.noctalia.dev/noctalia/v5.6.0/desktop/wallpaper/)):

```toml
[wallpaper]
enabled             = true
fill_mode           = "crop"       # center | crop | fit | stretch | repeat | span
fill_color          = "#111111"
transition          = ["fade", "wipe", "disc", ...]   # 12 effects
transition_duration = 1500
edge_smoothness     = 0.3
transition_on_startup = false
sync_transitions      = true
directory           = ""           # empty = XDG_PICTURES_DIR / ~/Pictures
directory_light     = ""
directory_dark      = ""
per_monitor_directories = false

[wallpaper.default]
path = "/home/user/Wallpapers/default.png"

[wallpaper.automation]
enabled             = false
interval_seconds    = 1800
order               = "random"     # random | alphabetical
recursive           = false
pause_on_fullscreen = false
```

**Capabilities.**

- Formats: PNG, JPEG, WebP, JPEG XL, BMP, GIF, HEIC, HEIF, AVIF (HEIC/HEIF/AVIF need `libheif` plus an HEVC/AV1
  decoder at runtime).
- `fill_mode = "span"` treats the monitor set as one canvas, so a wide image flows across outputs — better than
  hyprpaper's per-output crop for multi-head setups.
- Solid colours are wallpapers: the picker stores `color:#FF00FF`, so colour fills share the transition pipeline.
- Automation picks at shell start and every `interval_seconds`, ordering `random` or `alphabetical`, optional
  `recursive`, and holds rotation while any window is fullscreen (`pause_on_fullscreen`, needs
  `wlr-foreign-toplevel-management`) and while the lock screen is up.
- `[[wallpaper.favorite]]` entries can pin an image **together with** `theme_mode`/`palette_source`, so a wallpaper
  switch can carry a palette change (hyprpaper has no equivalent).
- Separate `[backdrop]` surface (`enabled = false`, `blur_intensity = 0.5`, `tint_intensity = 0.3`) feeds niri-style
  overview backdrops.

**Limitations — the important one for dotfiles.**

- The documented per-monitor override is **directories, not an image path**:

  ```toml
  [wallpaper.monitor.DP-2]
  enabled         = false
  fill_color      = "#202020"
  directory       = "/home/user/Wallpapers/Vertical"
  directory_light = "..."
  directory_dark  = "..."
  ```

  and it is only active with `per_monitor_directories = true`. The v5.6.0 type `WallpaperMonitorOverride` has exactly
  `match`, `enabled`, `fillColor`, `directory`, `directoryLight`, `directoryDark` — no `path`. Per-output *image*
  selection happens in the picker with a monitor selected and is written as runtime state, so **you cannot express
  "eDP-1 gets A.png, DP-1 gets B.png" declaratively** the way hyprpaper's `preload`/`wallpaper` lines do. A Nix/TOML
  managed config can only set the global default image plus per-monitor folders (and rely on random rotation inside
  them).
- Automation is one interval for all outputs; only the *folder* can differ per monitor.
- Wallpaper is decoded on the GPU path of the shell; very large images are downsampled for crop/fit/stretch/span
  (identical on screen, lower VRAM). `center`/`repeat` keep 1:1 pixels.

**Disabling cleanly.** `[wallpaper].enabled = false` draws `fill_color` (or opaque black) instead of an image; the
shell still owns the background layer, so you cannot hand the background back to hyprpaper without also stopping
Noctalia's wallpaper surface. Practically: remove hyprpaper when adopting Noctalia.

### 3. Clipboard history (replaces cliphist + wofi)

**Keys and defaults** ([Shell settings](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/),
[Secret Service](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/secret-service/)):

```toml
[shell]
clipboard_enabled                = true   # false = no history/panel; live copy&paste still works
clipboard_keep_from_closed_apps  = true
clipboard_history_max_entries    = 100    # 10–10000; pinned entries exempt
clipboard_confirm_clear_history  = true
clipboard_auto_paste             = "auto" # off | auto | ctrl_v | ctrl_shift_v | shift_insert
clipboard_image_action_command   = ""     # e.g. "satty -f -" or "gimp {path}"

[storage]
key_source = "secret-service"  # secret-service | file
key_file   = ""                # absolute path, 64 lowercase hex chars, when key_source = "file"
```

**Capabilities.**

- **Encrypted at rest.** History is encrypted with a key derived from the storage master key; notification history and
  the calendar event cache get their own derived keys. With the default `secret-service` source, a locked keyring means
  history is session-only until it unlocks (automatic retry documented). `key_source = "file"` takes a 32-byte hex file
  — this is the agenix/sops-nix path and the one a declarative Nix setup wants.
- **Images:** PNG, JPEG, JPEG XL, AVIF, HEIC, HEIF, preferring PNG when several formats are offered; entries are
  re-pasted byte-for-byte with the original MIME type. Preview of AVIF/HEIC needs `libheif` at runtime.
- **Auto-paste** injects a virtual-keyboard chord after activation (`auto` = `Ctrl+V` for images, `Ctrl+Shift+V` for
  text). Hyprland's permission system requires an explicit `keyboard` grant for Noctalia's virtual keyboard; the
  Hyprland compositor page documents the exact rule.
- Password-manager copies marked `x-kde-passwordManagerHint` (1Password) never enter history and are not retained after
  the source closes.
- Panel: type-to-filter list, pinned rows (exempt from the cap), per-entry and clear-all with confirmation, image action
  button that receives `{path}` or stdin (`{stdin}` expands to `-`), and `clipboard_clear`/`clipboard-copy`/
  `clipboard-text` IPC. Search input exists (`clipboard.filter-placeholder` in `clipboard_panel.cpp`), which is the
  cliphist+wofi workflow in one surface.
- Transport: `ext-data-control-v1` when available, `zwlr_data_control_manager_v1` otherwise
  (`src/shell/wayland/clipboard_globals.cpp`).

**Limitations.**

- KWin typically lacks both data-control and virtual-keyboard; the compositor matrix lists clipboard history and
  clipboard auto-paste as unavailable there.
- If the keyring is not the one PAM unlocks at login, history/cache silently become session-only after every reboot; the
  Secret Service page documents the Seahorse fix. On NixOS this is avoided with `key_source = "file"`.
- Images are capped by MIME support, not by size; very large image entries are stored as bytes (no documented limit).

**Disabling cleanly.** `[shell].clipboard_enabled = false` disables history, persistence and the panel, while plain
copy/paste in text fields keeps working. The data-control binding is still used for the live selection.

### 4. Dock (optional; no current equivalent)

**Keys and defaults** ([Dock](https://docs.noctalia.dev/noctalia/v5.6.0/dock/)):

```toml
[dock]
enabled             = false      # off by default
position            = "bottom"   # top | bottom | left | right
icon_size           = 48
show_running        = true
auto_hide           = false
smart_auto_hide     = false
auto_hide_reveal_delay_ms = 250
reserve_space       = true
layer               = "top"      # top | overlay
magnification       = true
magnification_scale = 1.45
background_opacity  = 0.88
compositor_blur     = true
border              = "outline_variant"
border_width        = 0.0
shadow              = true
radius              = 16
concave_edge_corners = true
margin_ends         = 0
margin_edge         = 0
launcher_position   = "none"     # none | start | end
pinned              = ["firefox", "code", "kitty"]
```

**Why you'd want it.** It is the only Noctalia surface that gives a persistent, pointer-driven app strip: pinned +
running apps, per-window cycling and right-click minimise/restore, macOS-style magnification, `smart_auto_hide` (visible on an empty
workspace, hidden when windows exist), drag-to-reorder pins, and per-monitor overrides
(`[dock.monitor.<name>]`, first match wins, every field inheritable). If the migration replaces wofi's app menu with
the launcher, the dock is the faster path for the five or six apps actually used.

**Limitations.**

- Disabled by default; nothing else in the shell depends on it.
- Minimise actions and running-app state need a compositor backend that reports window state
  (`wlr-foreign-toplevel-management` on unknown compositors; Hyprland/niri have native backends).
- It is a second app strip next to the taskbar widget; running both duplicates the same information.

**Disabling cleanly.** `enabled = false` (the default). `dock-show`/`dock-hide`/`dock-toggle` save a runtime override.

### 5. Launcher (replaces wofi/fuzzel, including dmenu-style scripts)

**Keys and defaults** ([Launcher](https://docs.noctalia.dev/noctalia/v5.6.0/launcher/)):

```toml
[shell.launcher]
layout              = "full"     # full | simple
width               = 760        # 560–1100, full layout
search_position     = "bottom"   # top | bottom
default_view        = "recent"   # recent | pinned | all | categories
categories          = true       # simple layout chip row
category_icons_only = false
show_navigation_labels = true
show_settings_button   = true
show_session_button    = true
show_icons          = true
app_grid            = false
show_app_actions    = false
track_usage         = true
sort_by_usage       = true
ignore_mouse        = false
pinned              = []
provider_prefix     = "/"
auto_paste          = "auto"     # off | auto | ctrl_v | ctrl_shift_v | shift_insert
fetch_exchange_rates = true

[shell.launcher.providers.calculator]
prefix = "calc"
global = true
```

**Capabilities.**

- Built-in providers: Applications (fuzzy, XDG desktop entries, Flatpak/Snap/Nix/AppImage origin badges, `.desktop`
  actions), Calculator (libqalculate: units, bases, currency), Emoji, Panels (`/pan`, every registered panel and
  Control Center tab), Session (`/session`), Wallpaper (`/wall`), Windows (`/win`), plus plugin and dmenu providers.
- **Two dmenu paths**, which is what fuzzel/wofi `--dmenu` scripts need:
  1. `noctalia dmenu` — stdin lines in, selection on stdout, `-p/--prompt` for the placeholder, exit 0 on select and
     1 on cancel, tab splits title/description. It talks to the running instance over `XDG_RUNTIME_DIR`/`WAYLAND_DISPLAY`.
  2. Persistent `[shell.launcher.dmenu.entry.<id>]` providers with `command` (run via `/bin/sh -lc`, one candidate per
     stdout line), `exec` (with shell-quoted `{selection}` and `{query}`), `prefix`, `label`, `glyph`, `global`,
     `freeform`. `exec` is detached and does **not** open a terminal, so interactive commands must name their emulator.
- Luau plugins can add launcher providers (`[[launcher_provider]]`), overridable per user via
  `[shell.launcher.providers."<pluginId>:<entry>"]`.
- `ignore_mouse = true` gives keyboard-only operation; `[keybinds]` remaps validate/cancel/arrows/category cycling.

**Limitations.**

- **No `enabled` key.** The launcher is a panel, opened on demand; you "disable" it by not binding it. Nothing runs in
  the background for it (usage tracking writes history while `track_usage = true`).
- `noctalia dmenu` requires a running Noctalia; a scripted `wofi --dmenu` pipeline now has a hard dependency on the
  shell being alive.
- Terminal apps use `$TERMINAL` (no `-e` inside it) or terminal discovery; dmenu `exec` lines must specify the terminal
  themselves.
- Simple layout is fixed at 560×500; no CSS, no per-invocation `--width/--lines` flags like fuzzel's. Theme is
  Noctalia's palette, not a stylesheet in the dotfiles.

### 6. Session / power menu (replaces wlogout or a scripted menu)

**Keys and defaults** ([Shell → Session panel](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/#session-panel)):

```toml
[shell.session]
grid           = false
grid_columns   = 3
show_shortcuts = true

[[shell.session.actions]]
action   = "lock"          # lock | logout | suspend | lock_and_suspend | reboot | reboot_uefi | shutdown | command
enabled  = true
command  = "swaylock -f"   # optional; /bin/sh -c, overrides the built-in handler
label    = ""
glyph    = ""
shortcut = "1"             # 1–5 by default while the panel is open
lockscreen_shortcut = ""
countdown_seconds   = 0
variant  = "default"       # default | primary | secondary | destructive | outline

[shell.session.power]
suspend  = "sudo -n zzz"
reboot   = "sudo -n reboot"
shutdown = "sudo -n poweroff"
```

Defaults when `[[shell.session.actions]]` is omitted: **Lock, Log out, Lock & Suspend, Reboot, Shut down**, bound to
`1`–`5`. `reboot_uefi` is opt-in and always runs `systemctl reboot --firmware-setup`. Built-in suspend/reboot/shutdown
resolve from prioritized backends (systemd/logind first) and cache the winner for the session; `[shell.session.power]`
overrides them globally. The same configured list drives the launcher's `/session` provider and
`noctalia msg session <action>`, so one definition covers keybind, GUI and scripts.

**Limitations.**

- Log out uses compositor-native exits where available; a compositor without a documented exit path falls back to the
  configured command — check that a Hyprland logout entry is either the built-in or an explicit `command`.
- Countdowns are per-entry only (no global "press again to confirm").
- `reboot_uefi` requires systemd + UEFI and is not synced to the greeter.

**Disabling cleanly.** `actions = []` hides every session button (documented as an explicit example); per-entry
`enabled = false` removes one row.

### 7. OSD (replaces brightness/volume OSD tooling)

**Keys and defaults** ([Shell → OSD](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/#osd)):

```toml
[osd]
position = "top_center"    # 9 positions incl. center_right/center_left/center
position_vertical = "top_center"
orientation = "horizontal" # horizontal | vertical (volume/brightness sliders only)
hide_delay_ms = 1400       # 250–10000
scale = 1.0
background_opacity = 0.97
border = true
border_color = "outline_variant"
border_width = 1
follow_focused_output = false
offset_x = 20
offset_y = 8
# monitors = ["DP-1"]

[osd.kinds]
volume = true
volume_output = true
volume_input = true
brightness = true
wifi = true
bluetooth = true
power_profile = true
caffeine = true
nightlight = true
dnd = true
lock_keys = true
keyboard_layout = true
media = true
media_volume = true
privacy = true
keyboard_backlight = true
custom = true
```

**Capabilities.** One positioned popup surface covers volume (output/input), brightness, Wi-Fi, Bluetooth, power
profile, caffeine, night light, DND, lock keys, keyboard layout, MPRIS track *and* per-player volume, privacy
(mic/camera/screen-share) and keyboard backlight, plus `custom` popups from plugins/scripts. Sliders can be vertical;
text-only popups stay horizontal. OSDs can follow the focused output and be pinned to a monitor list. Scripts can drive
the same surface with `noctalia msg osd-show '{"icon":"brightness-low","value":"40%","progress":0.4}'` and
`brightness-osd 72`, which is the useful hook for external brightness/volume controllers.

**Limitation worth flagging.** The v5.6.0 docs code block does **not** list a master `enabled` key, but the v5.6.0
schema and type do: `field(&OsdConfig::enabled, "enabled")` in `config_schema_notifications.cpp`, `bool enabled = true;
// master gate for all OSD popups` in `config_types.h`. So `[osd] enabled = false` works in 5.6.0 and is undocumented;
per-kind toggles are the documented path.

### 8. Tray widget (system tray) and MPRIS

**Tray keys and defaults** ([tray widget](https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/tray/)):

```toml
[widget.tray]
colorize_icons = false
hidden = []                   # ids/names/bus/path tokens
pinned = []                   # always visible in bar when drawer = true
hide_passive = true
drawer = false
glyph = ""                    # empty = automatic chevron
glyph_position = "before"
peek = false
peek_delay_ms = 100
drawer_columns = 3
drawer_item_size = 0          # inherit
drawer_background_opacity = 0 # inherit
detached_panel = false
icon_override_blacklist = []
icon_type = "default"         # default | desktop | symbolic
```

**Capabilities.** StatusNotifierItem tray, using an existing `org.kde.StatusNotifierWatcher` and taking the name over if
that watcher dies. Inline icons or a drawer/peek glyph, pinned items (via right-click Pin), hidden list, passive-item
filtering, per-item icon substitution, symbolic fallbacks. An empty tray hides itself. Tray item context menus are
rendered by Noctalia (`src/shell/tray/tray_menu.cpp`), so app menus appear without a separate menu host.

**Limitations.** SNI only: there is no XEmbed/X11 tray support (the docs describe the tray as
"System tray (StatusNotifierItem)" and a search of the v5.6.0 source tree file list for `xembed` returns 0 matches —
`grep -ic xembed tree.txt` → `0`). Legacy apps that register an old-style tray icon will have no icon. Icons can take a
few seconds to reappear after a shell restart.

**Disabling cleanly.** Remove the widget from the bar's widget list; no global tray daemon exists. The notification
daemon is separate (`[notification] enable_daemon = true`) and can be turned off independently.

**MPRIS.** No tray module: `[widget.media]` shows artwork/title (peek, album-art-only, rotation, scrolling title),
left-click opens Control Center → Media (players, transport, queue-style switching, PipeWire visualizer), right-click
toggles play/pause, mouse side buttons skip. `[shell.mpris] blacklist = []` hides players (case-insensitive match on bus
name, identity, desktop entry, or a bus-name token). That is a straight replacement for an MPRIS bar module; what it
does not do is expose per-player controls in the bar beyond play/pause and skip.

### 9. Workspaces and taskbar widgets

**Workspaces** ([widgets](https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/workspaces/)): `style =
"regular" | "minimal" | "focus_hint"`, `show_labels = true`, `show_icons = true`, `label_source = "id" | "name"`,
`max_label_chars = 1`, `separator = ""`, `separator_color = "on_surface"`, `pill_scale = 1.0`,
`active_pill_size = 2.2`, `inactive_pill_size = 1.0`, `focused_color = "primary"`, `occupied_color = "secondary"`,
`empty_color = "secondary"`, `urgent_color = "error"`, `hide_when_empty = false`, `labels_only_when_occupied = false`,
`monitors = []` (`"*"` = all). Focus Hint carries the focused app icon.

**Taskbar** ([widgets](https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/taskbar/)): `pinned = []`,
`pinned_opacity = 0.5`, `show_running = true`, `group_by_workspace = false`, `show_all_outputs = false`,
`only_active_workspace = false`, `hidden_workspaces = []`, `prefer_symbolic_icons = false`, `icon_scale = 1.0`,
`workspace_group_content = "icons" | "count" | "dots"`, `show_active_indicator = true`, plus per-state colours.
Left-click focus/restore/minimise (where the compositor allows), middle-click close, scroll to focus.

**Limitation.** Workspace grouping needs per-window workspace assignment; on labwc it is unavailable and the settings
are hidden in the GUI (keys accepted but ignored). Occupancy is inferred there too, which affects `hide_when_empty` and
smart auto-hide.

### 10. Screenshot + annotation (replaces grim/slurp + satty/swappy)

**Keys and defaults** ([screenshot widget](https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/screenshot/),
[Shell → screenshot](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/)):

```toml
[shell.screenshot]
save_to_file          = true
directory             = ""          # empty = XDG_PICTURES_DIR / ~/Pictures
filename_pattern      = ""          # empty = screenshot_%Y%m%d_%H%M%S
append_mode_suffix    = true        # -region/-annotated/-window/-desktop
format                = "png"       # png | jpeg | webp | jxl
quality               = 90
copy_to_clipboard     = true
freeze_screen         = true
annotate              = false       # route every capture through the editor
show_cursor           = false
region_modifier       = "none"      # none | super | ctrl | alt | shift | space
```

**Capabilities.**

- Region, fullscreen (focused / picker / named connector / `all`), and window capture (`ext-image-capture-source`);
  freeze-before-select; size badge in device pixels; multi-monitor "select all"; `pipe_to_command` with
  `NOCTALIA_SCREENSHOT_PATH`; per-call overrides from IPC.
- Built-in annotation editor with tools: move, brush, highlighter, line, arrow, rectangle, circle, text, numbering,
  blur, eraser, crop, plus backdrop (rounded, gradient, shadow), zoom/pan, undo/redo, 8 swatches, per-tool size.
  This replaces satty/swappy for the common "screenshot → arrow + blur → copy" loop.
- Live overlay mode: `noctalia msg annotate` draws over running apps (`Z` freezes and reveals blur/crop/copy/save) — a
  presentation feature with no grim equivalent.
- IPC: `screenshot-region`, `screenshot-fullscreen [pick|DP-2|all]`, `screenshot-window`, `screenshot-annotate`,
  `annotate <path>`.
- `region_modifier` reproduces grim/slurp's "hold a modifier to move/resize" muscle memory.

**Limitations.** Screenshots need `wlr-screencopy`; window capture needs `ext-image-capture-source`; on KWin both are
commonly absent and the widget is omitted. `pipe_to_command` always receives PNG on stdin (only the saved file honours
`format`). At least one of `save_to_file`, `copy_to_clipboard`, `pipe_to_command` must be on.

**Disabling cleanly.** Remove the bar widget; the IPC verbs remain (harmless). No daemon.

### 11. Screen recording — **not core; official plugin**

There is no recording surface in the shell. Probes: the v5.6.0 docs sitemap has no recording page, and
`grep -c '"record' src/cli/schema_msg.h` → `0`, i.e. no `record` IPC verb.

The replacement is the official plugin `noctalia/screen_recorder`
([official plugins](https://docs.noctalia.dev/noctalia/v5.6.0/plugins/official-plugins/#screen_recorder)): a headless
session service wrapping `gpu-screen-recorder` (must be installed natively or as the Flatpak), with a replay buffer and
commands `plugin noctalia/screen_recorder:service all start|stop|toggle|replay-start|replay-stop|replay-toggle|replay-save`,
optional payload `focused|portal|region`. It also adds a `screen_recorder` Control Center shortcut (toggle recording;
right-click toggles the replay buffer).

Parity notes: the recording logic survives without any bar widget (a service), and region mode depends on `slurp`
(plugin dependency list includes `gpu-screen-recorder`, `slurp`). A wf-recorder-based pipeline is replaced by
gpu-screen-recorder + plugin settings; per-call options that a shell script passed to wf-recorder become plugin
settings or the `focused|portal|region` payload.

### 12. Screen time

`[shell] screen_time_enabled = false` (plus `screen_time_colorize_icons = false`). When on, Noctalia tracks foreground
time per app from the active `zwlr_foreign_toplevel` window, pauses while the session lock is active, retains about 14
days in `$XDG_STATE_HOME/noctalia/screen_time.json`, and shows today/last-3-days/last-14-days in the Control Center
Screen Time tab (also a Home shortcut `type = "screen_time"`). Reset from Settings; IPC absent.
Limitation: needs the foreign-toplevel protocol (broken/empty on KWin); it is foreground time, not total usage.

### 13. Night light (vs gammastep/redshift)

**Keys and defaults** ([Night Light](https://docs.noctalia.dev/noctalia/v5.6.0/services/night-light/)):

```toml
[nightlight]
enabled           = false
force             = false      # hold the night temperature, ignoring schedule
temperature_day   = 6500       # K; must exceed night by >= 100
temperature_night = 4000

[brightness]
enable_scheduled_brightness = false
scheduled_day_brightness    = 1.0
scheduled_night_brightness  = 0.5
```

- Uses `zwlr-gamma-control-unstable-v1` (present on Hyprland, Sway, niri, Umbriel; absent on stock KWin, where the
  docs say to use Plasma's Night Color).
- The schedule is **shared** with Weather and Theme-auto through `[location]` (`auto_locate` IP geolocation, or a
  geocoded `address`, or `custom_schedule` with explicit sunrise/sunset). This is the gammastep/redshift `geoclue`
  behaviour, minus the separate daemon and its config file.
- Fade: a one-hour ramp *centred* on sunrise/sunset (30 min before, 30 min after), anchored to wall clock — starting the
  shell mid-sunset lands on the correct temperature instead of restarting a fade. `force = true` pins the night value
  for the classic "toggle night light now" keybind; `nightlight-toggle`, `nightlight-force-toggle`,
  `nightlight-enable|disable`.
- Bonus: scheduled *brightness* on the same sun schedule (`[brightness] enable_scheduled_brightness`), per-monitor
  targets, which gammastep does not do.

**Limitations.** Gamma is the protocol's per-output transform, so one temperature applies to all CRO-controlled outputs
(no per-monitor Kelvin setting is documented or present in `NightLightConfig`). It needs a location source even for
`force`? — the FAQ says Night Light needs `[location]` configured, so a manual-only setup still wants an address or
coordinates. `offline_mode = true` does not break it once coordinates are set, but `auto_locate` itself needs the
network.

**Disabling cleanly.** Default is off; `enabled = false` releases gamma control and the compositor's native output
returns immediately.

### 14. Polkit agent (replaces lxqt-policykit-agent)

```toml
[shell]
polkit_agent          = false     # register Noctalia's native polkit authentication agent
polkit_colorize_icons = false

[shell.panel]
polkit_placement = "floating"     # attached | floating
polkit_position  = "center"
```

- **Default is off.** To replace `lxqt.lxqt-policykit` you must set `polkit_agent = true` *and* stop the other agent;
  two registered agents race for `org.freedesktop.PolicyKit1` and the losing one silently never prompts.
- Authentication is PAM (`PamAuthenticator::authenticateCurrentUser`, i.e. the same helper/PAM stack as the lock
  screen), registered on the system bus as an authentication agent with `PolkitAgent` (source:
  `src/dbus/polkit/polkit_agent.{h,cpp}`).
- The prompt is a normal Noctalia panel, so it can attach to the bar or float, and honours theme/UI scale.
- Not documented: fingerprint on the polkit prompt, and whether an "admin authentication" retry/keep-open flow exists.
  Both are **unverified**.

### 15. Power profiles (replaces `powerprofilesctl`-style menu entries)

- Requires the `org.freedesktop.UPower.PowerProfiles` D-Bus endpoint (power-profiles-daemon); the docs' IPC page says
  profile ids come from the service and are usually `performance`, `balanced`, `power-saver`.
- `[widget.power_profile]` has no settings of its own (only shared widget settings); left-click steps forward,
  right-click back, scroll both ways, all rebindable. `noctalia msg power-set balanced` / `power-cycle`.
- Control Center → Power adds battery percentage, state, time remaining, current draw, **battery health** and connected
  peripheral batteries from UPower, plus the profile selector. The tab is hidden when neither UPower nor PPD runs.
- Limitation: it is a PPD front end, not a TLP/auto-cpufreq front end; machines managed by those daemons will show no
  profiles. No per-profile custom commands.

### 16. Weather

```toml
[weather]
enabled         = true
refresh_minutes = 30
unit            = "metric"   # metric | imperial
effects         = true       # visual weather effects
```

Open-Meteo, current conditions + 6-day forecast, driven by the same `[location]`; shown in the Control Center Weather
tab, the Home date card, the `weather` bar widget, and `[[control_center.shortcuts]] type = "weather"`. Honours
`[shell] offline_mode`. `enabled = true` by default, but with no resolvable location the tab/widget stay empty — the
practical default is "off until you set a location".

### 17. Calendar

**Keys and defaults** ([Calendar](https://docs.noctalia.dev/noctalia/v5.6.0/services/calendar/)):

```toml
[calendar]
enabled                  = false
dedupe_events            = false
dedupe_ignore_patterns   = []
refresh_minutes          = 15
event_date_format        = "%A %e %B"
event_time_format        = "%H:%M"

[calendar.reminders]
enabled             = true
use_event_reminders = true
default_lead_minutes = 10
all_day_digest_time = "09:00"

[calendar.account.home_nextcloud]
type       = "caldav"      # google | caldav | ics | vdir
provider   = "custom"      # icloud | custom
server_url = "https://cloud.example.com/remote.php/dav/"
username   = "me"
credential_source = "file"
password_file = "/run/agenix/noctalia-caldav"
```

- Reads CalDAV (iCloud preset or a custom discovery root), Google (browser OAuth), ICS URLs, and local vdir directories
  (inotify-watched, vdirsyncer/khal layout). **Events are read-only** — no creation or editing.
- Reminders come from VALARM/Google reminders with a fallback lead, an all-day digest, and are stored in notification
  history (so they survive being away).
- Event cache is encrypted (`events.enc`) with a key derived from the storage master key; CalDAV passwords use Secret
  Service by default or `credential_source = "file"`, and **Google refresh tokens always require Secret Service**
  (file mode is CalDAV-only).
- Presentation: `[control_center.calendar] show_events_card = true`, `show_week_numbers = false`,
  `show_events_location = false`, `hide_past_events = false`, `past_events_threshold_minutes = 30`.

**Limitations.** Read-only; Google needs a working keyring; account ids must be `[a-z0-9_]+`; dedupe is title+start+end
based.

## Cross-cutting findings

1. **Single process, per-surface gates.** Noctalia has no per-surface daemons. Every surface above is toggled inside
   one config: `[lockscreen].enabled`, `[shell].clipboard_enabled`, `[wallpaper].enabled`, `[dock].enabled`,
   `[osd].enabled` + `[osd.kinds].*`, `[nightlight].enabled`, `[shell].polkit_agent`, `[shell].screen_time_enabled`,
   `[weather].enabled`, `[calendar].enabled`, `[shell.session].actions`. Widgets (tray, taskbar, workspaces, media,
   screenshot, power profile) are disabled by removing them from the bar's widget list, not by a config flag.
2. **The launcher has no master switch** — it is an on-demand panel, so you disable it by unbinding it. The
   notification daemon (`[notification] enable_daemon`) is a separate gate from toast rendering and from the OSD.
3. **GUI overrides beat hand-written TOML.** `~/.local/state/noctalia/settings.toml` loads last, so a click in Settings
   silently overrides a Nix-managed `~/.config/noctalia/*.toml` until that key is removed. For a declarative setup this
   is the main trap: either accept the state file as app-owned, or delete it after GUI use. (`[include]` does not
   function in `settings.toml`.)
4. **Protocol dependencies cluster.** `wlr-screencopy` gates screenshots, lock desktop capture; `wlr-gamma-control`
   gates night light; `ext-data-control-v1`/`wlr-data-control` + virtual keyboard gate clipboard history/auto-paste;
   `wlr-foreign-toplevel-management` gates window lists, minimise state, fullscreen pause, screen time. On Hyprland all
   are present, but its permission system needs explicit `screencopy` and `keyboard` grants
   ([Hyprland page](https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/hyprland/)).
5. **Encryption is not optional for history.** Clipboard history, notification history and calendar cache all encrypt
   with derived keys; on NixOS the clean path is `[storage] key_source = "file"` + `key_file` from agenix, otherwise
   restart behaviour depends on the keyring PAM unlocks.
6. **Secrets discipline.** Nothing in the non-bar surfaces requires plaintext config secrets: calendar uses
   `credential_source = "file"`, clipboard uses the storage key file, and `noctalia config export --credentials omit`
   exists for publishing dotfiles.

## Unverified and open questions

- **Fingerprint on the polkit prompt**: not documented; the lock screen explicitly drives fprintd itself, but the polkit
  agent's PAM stack is not described.
- **Per-output night-light temperature**: `NightLightConfig` has a single `dayTemperature`/`nightTemperature`; there is
  no per-monitor key, but I did not read the gamma-application code to confirm every output gets the same value.
- **Exact behaviour of `noctalia dmenu` under a compositor without a running shell** (e.g. during session startup
  ordering) is documented only as "start Noctalia first"; failure mode not tested here.
- **Whether the XEmbed gap matters in practice** depends on which of the current tray apps (nm-applet, blueman, etc.)
  register SNI — most modern ones do, but this was not probed on the target machine.
- **Wallpaper rotation with `per_monitor_directories` and a global interval**: docs say each monitor "picks
  independently"; whether the pick happens on one shared timer tick is not stated.
- **`[osd] enabled` is undocumented**; it exists in the 5.6.0 schema/type, so I treat it as supported but note that the
  docs may not promise stability for it.
- The home-manager `programs.noctalia` module options (`settings`, `customPalettes`, `checkConfig`, `systemd`) were out
  of scope for this item; the surface-level defaults here are the binary's, and module defaults could differ.

## Source Evaluation

1. **Shell settings page** (`/noctalia/v5.6.0/configuration/shell/`) — the single densest source; primary vendor doc,
   authoritative for keys, defaults and disable semantics. Biased toward describing intent; several code blocks
   abbreviated defaults (e.g. `[osd]` lacks `enabled`), so source cross-check was required.
2. **`src/config/config_types.h` @ v5.6.0** — ground truth for defaults (`LockscreenConfig`, `NightLightConfig`,
   `OsdConfig`, `WallpaperConfig`, `WallpaperMonitorOverride`, clipboard fields). Highest confidence; used to correct
   docs omissions.
3. **`src/config/schema/config_schema_shell.cpp`, `config_schema_notifications.cpp`** — confirms which keys exist at
   all (e.g. `polkit_agent`, `[osd] enabled`), resolving "is this configurable or only in the GUI".
4. **`src/shell/lockscreen/lock_screen.cpp`** — confirms `ext-session-lock-v1`, PAM helper behaviour, the
   `pam_service` build option and the `pam_fprintd` stripping rationale.
5. **Dock page** (`/noctalia/v5.6.0/dock/`) — primary vendor doc; complete key block and per-monitor override rules.
6. **Launcher page** (`/noctalia/v5.6.0/launcher/`) — primary vendor doc; provider/prefix/dmenu semantics.
7. **Wallpaper page** (`/noctalia/v5.6.0/desktop/wallpaper/`) — primary vendor doc; the per-monitor limitation is
   established jointly by this page and `WallpaperMonitorOverride`.
8. **Control Center page** (`/noctalia/v5.6.0/control-center/`) — tab inventory incl. screen time, power, calendar.
9. **Secret Service page** (`/noctalia/v5.6.0/configuration/secret-service/`) — encryption/keyring behaviour, the
   multiple-keyring caveat, and file-based alternatives.
10. **Official plugins page** (`/noctalia/v5.6.0/plugins/official-plugins/`) — establishes that recording is a plugin,
    not core, and its dependency on `gpu-screen-recorder`.
11. **FAQ** (`/noctalia/v5.6.0/getting-started/faq/`) — PAM helper failure mode, `NOCTALIA_PAM_HELPER_PATH`, location
    requirements for night light/weather, lock-before-suspend answer.
12. **Hyprland compositor page** (`/noctalia/v5.6.0/compositor-settings/hyprland/`) — permission grants for
    `screencopy` and `keyboard`, layer namespaces; directly relevant to this workstation.

## Conclusions

- Across the eleven tools in scope, the only outright gap is **screen recording**, which ships as an official plugin
  around `gpu-screen-recorder` rather than as a shell surface. The one partial gap is **per-monitor static wallpaper
  assignment**: config exposes folders and a global default image, not an image path per output.
- The strongest wins are structural, not cosmetic: one lock screen that natively locks before suspend and honours
  `loginctl lock-session`, clipboard history encrypted at rest with an agenix-friendly key file, a screenshot editor
  that removes satty/swappy, an OSD that is a superset of the brightness/volume OSD, and a session menu whose actions
  are one config array used by the GUI, the keybind and `noctalia msg`.
- The three migration risks are: (1) the PAM helper must match the host's `libpam`, or every password on the lock
  screen fails; (2) the keyring that PAM unlocks must be the one holding the storage key, or history silently becomes
  session-only after reboot; (3) `polkit_agent` defaults to `false`, so the old agent must be removed *and* the new one
  switched on deliberately.
- Declarative-config caveats: per-monitor wallpaper images and per-monitor night-light Kelvin are not expressible in
  TOML; GUI writes to `settings.toml` outrank your dotfiles; and the launcher has no disable key (it is simply not
  bound).
- On Hyprland specifically the surfaces work, but only with explicit `screencopy`/`keyboard` permission grants and with
  hyprpaper/hyprlock/lxqt-policykit stopped so nothing competes for the background layer or the polkit bus name.

## Bibliography

Vendor docs (all fetched 2026-11-25, version-pinned to 5.6.0):

- https://docs.noctalia.dev/noctalia/v5.6.0/configuration/
- https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/
- https://docs.noctalia.dev/noctalia/v5.6.0/configuration/secret-service/
- https://docs.noctalia.dev/noctalia/v5.6.0/dock/
- https://docs.noctalia.dev/noctalia/v5.6.0/launcher/
- https://docs.noctalia.dev/noctalia/v5.6.0/desktop/wallpaper/
- https://docs.noctalia.dev/noctalia/v5.6.0/control-center/
- https://docs.noctalia.dev/noctalia/v5.6.0/control-center/shortcuts/
- https://docs.noctalia.dev/noctalia/v5.6.0/lockscreen/widgets/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/night-light/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/brightness/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/calendar/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/weather/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/idle/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/notifications/
- https://docs.noctalia.dev/noctalia/v5.6.0/services/audio/
- https://docs.noctalia.dev/noctalia/v5.6.0/ipc/surfaces/
- https://docs.noctalia.dev/noctalia/v5.6.0/ipc/system-controls/
- https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/tray/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/clipboard/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/screenshot/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/session/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/workspaces/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/taskbar/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/media/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/nightlight/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/power-profile/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/privacy/
- https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/caffeine/
- https://docs.noctalia.dev/noctalia/v5.6.0/plugins/official-plugins/
- https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/hyprland/
- https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/kde/
- https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/faq/

Source (tag `v5.6.0`, commit `29c2209467d339a6456515593b26103fad33bd6c`):

- `src/config/config_types.h`
- `src/config/schema/config_schema_shell.cpp`
- `src/config/schema/config_schema_system.cpp`
- `src/config/schema/config_schema_notifications.cpp`
- `src/shell/lockscreen/lock_screen.cpp`
- `src/shell/wayland/clipboard_globals.cpp`
- `src/shell/clipboard/clipboard_panel.cpp`
- `src/dbus/polkit/polkit_agent.{h,cpp}`
- `src/auth/pam_authenticator.h`
- `src/cli/schema_msg.h`

Repo metadata:

- https://github.com/noctalia-dev/noctalia (tag list: `v5.6.0` is the newest)
- https://github.com/noctalia-dev/noctalia-docs (HEAD `4dccd3a`, 2026-11-25; docs source for the pages above)
