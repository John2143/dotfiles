# Feature matrix: old stack → Noctalia v5.6.0

Every user-visible feature of the Waybar/Eww/dunst stack mapped to its Noctalia
replacement. "Old" references are to the files as they existed before this
branch (`nixos/modules/waybar.nix` at 874 lines, `nixos/modules/eww.nix`,
`nixos/home.nix`, `nixos/modules/theme.nix` before the edit).
"New" references are the plugin entries and helper binaries that now carry the
feature. Where a file was modified by the migration, old line numbers refer to
the pre-migration version (`git show HEAD:<path>`); line numbers in
`nixos/modules/theme.nix`, `nixos/theme-switch.sh` and
`nixos/modules/noctalia.nix` refer to the current tree.

Legend for the target column:

- **native** — a built-in Noctalia widget or surface, configured from
  `nixos/modules/noctalia.nix`.
- **`john/…:`** — first-party Luau plugin entry (`noctalia-plugins/`).
- **kept** — external program still installed and called by a helper or keybind.
- **dropped** — no replacement; behaviour intentionally removed.

---

## 1. Bar zones

Old composition (`waybar.nix:409-466`): `modules-left` workspaces + new
workspace + optional bluetooth + window; `modules-center` media;
`modules-right` 19 modules in a fixed order. Global bar: layer top, position
top, height 42, spacing 4, margin `0 12 0 12`, `reload_style_on_change`.

New composition: `[bar.default]` in `nixos/modules/noctalia.nix` with
`start` / `center` / `end` arrays, `thickness`, `margin_ends`,
`widget_spacing`, `reserve_space = true`, `layer = "top"`.

### 1.1 Left zone

`start = ["workspaces" "newworkspace"] ++ optional bluetooth ++ ["active_window"]`

| Old module (line) | Renders | New target | Config / entry | Behaviour delta |
|---|---|---|---|---|
| `hyprland/workspaces` (`waybar.nix:440-512`) | one pill per persistent workspace, glyph from `ws-icons`; hover expands a window-taskbar | **native** `workspaces` | `[widget.workspaces]`: `style = "regular"`, `show_labels = true`, `label_source = "name"`, `max_label_chars = 8`, `focused_output_only = true` | No hover taskbar: this bar has no `taskbar` widget. `workspace-taskbar.update-active-window`, per-address `hl.dsp.focus` and `ignore-list = ["^xwaylandvideobridge$"]` have no equivalent. Workspaces stay visible because every `workspace_rule` gained `persistent = true` (`nixos/home.nix`), and `default_name` keeps ids 1–10 ordered. |
| `custom/newworkspace` (`waybar.nix:514-522`) | `✚` button creating a random unused workspace id | **native** `custom_button` (`newworkspace`) | `[widget.newworkspace] type = "custom_button"`, `glyph = "plus"`, `tooltip = "New temporary workspace"`, `actions.left = "exec fish -c 'set ID (math (date +%s) % 9000 + 1000); hyprctl dispatch \"hl.dsp.focus({workspace=\"$ID\"})\"'"` | Ported verbatim; no plugin. Same random 1000–9999 id and `hl.dsp.focus`. |
| `bluetooth` (`waybar.nix:798-825`, conditional) | adapter state icon, connected device, battery percentage; left `blueman-manager`, right power toggle | **native** `bluetooth` | `[widget.bluetooth] show_label = false`; left opens Control Center → Bluetooth, right toggles the adapter | Device battery in the tooltip is gone; `blueman-manager` click is replaced by the control-center tab. `blueferry` battery probing is no longer called from the bar. |
| `hyprland/window` (`waybar.nix:417-420`) | active window title | **native** `active_window` | `[widget.active_window]`: `display = "icon_and_text"`, `max_length = 260` | Same data; Noctalia renders the window icon too. |

### 1.2 Center zone

`center = ["media_custom"]`

| Old module (line) | Renders | New target | Config / entry | Behaviour delta |
|---|---|---|---|---|
| `custom/media` (`waybar.nix:553-570`) | `▶/⏸/♫ <Player>: <artist> - <title> <vol%>`; left play/pause, right Eww media-picker, back/forward track skip, middle focus player window, scroll ±5% volume | **`john/dotfiles-bar:media`** + **`john/dotfiles-bar:media-panel`** | `[widget.media_custom] type = "john/dotfiles-bar:media"`; its manifest actions keep `middle = "none"`, `back = "exec playerctl --all-players previous"`, `forward = "exec playerctl --all-players next"` | The multi-player/Firefox-tab tooltip list moves into the panel. Pin selection (`/tmp/media-player-selected`) survives. Back/forward are action-only because no Luau callback exists for thumb buttons. Scroll volume stays 5% (old `media-player volume 0.05`). Focus-player middle-click is preserved (`media-player focus`). |

### 1.3 Right zone

`end = ["privacy" "screenrec"] ++ optional ["ipad"] ++ ["tailscale"] ++ optional ["deskflow"] ++ ["temporal" "voxtype" "group:hardware" "group:clock" "updates"] ++ optional arch ["thermostat"] ++ ["vast" "weather" "theme_toggle" "battery" "autoclicker" "tray" "volume" "notifications" "control-center"]`

| Old module (line) | Renders | New target | Config / entry | Behaviour delta |
|---|---|---|---|---|
| `custom/privacy` (`waybar.nix:696-702`) | `●` when any source is `RUNNING` | **native** `privacy` | `[widget.privacy] hide_inactive = true` | Now covers mic, camera and screen capture from PipeWire/V4L2 instead of `pactl` source state only. |
| `custom/screenrec` (`waybar.nix:704-712`) | ●/⬆/⏳/✔/✖ + label; left toggle, right last | **`john/dotfiles-bar:screenrec`** | `[widget.screenrec] type = "john/dotfiles-bar:screenrec"`; `screenrec status --follow` stream | Same states/colors. Hides on the resting `{"text":"","class":"idle"}` object instead of showing an empty capsule. `--follow` stays a long-lived stream. |
| `custom/ipad` (`waybar.nix:572-581`, isDesk) | `iPad <usb\|net> <●\|○>`; left recover, right create | **`john/dotfiles-bar:ipad`** | `[widget.ipad] type = "john/dotfiles-bar:ipad"`; `ipad-display status --waybar` | `colorForClass` applies the last class token, reproducing the old "link weight, state color" CSS. Helper installed only on `arch`/`office`. |
| `custom/tailscale` (`waybar.nix:583-598`) | icon + state; left opened Eww panel, right wofi exit-node picker | **`john/dotfiles-bar:tailscale`** + **`john/dotfiles-bar:tailscale-panel`** | `[widget.tailscale]`; left `togglePanel("john/dotfiles-bar:tailscale-panel")`, right `tailscale-exit-node` | Panel replaces the Eww window; `tailscale-exit-node` now pipes into `noctalia dmenu` instead of `wofi --dmenu`. The bar's `connected`/`disconnected`/`needs-login` classes finally have colours (they had no CSS rules before). |
| `custom/deskflow` (`waybar.nix:599-608`, isDesk) | `DF` summary pill; left start/stop; tooltip latency sparkline | **`john/deskflow:bar`** | `[widget.deskflow] type = "john/deskflow:bar"`; left on the server pill = `deskflow-ctl toggle`, left on a client pill opens `john/deskflow:panel`, middle refreshes, right = manifest `panel-toggle` | The single pill becomes a row: server pill + one pill per client (old `custom/deskflow-1..4`). Latency sparkline moves into the panel as per-client history. |
| `custom/deskflow-1..4` (`waybar.nix:358-372`, generated) | per-client pill, empty when slot unused | **`john/deskflow:bar`** (client rows) | `max_slots` widget setting, default 4, range 1–8 | Slots are rendered in one composite widget via `barWidget.render(ui.row(...))`; clicking a client pill opens the panel. |
| `custom/temporal` (`waybar.nix:610-618`) | `T`; left opens `https://temporal.ts.2143.me:8443` | **`john/dotfiles-bar:temporal`** | `[widget.temporal]`; `temporal-status` (TCP probe of `192.168.6.20:7233`) | Same probe and click. |
| `custom/voxtype` (`waybar.nix:620-626`) | recording/transcribing state, pulse animation | **`john/voxtype:bar`** | `[widget.voxtype]`; settings `hide_when_idle` (false), `show_label` (true); `voxtype status --follow --format json` | The stream restarts with a 15 s backoff and reconciles with a one-shot probe after 5 min of silence; Waybar simply died with the process. Click toggles recording. |
| `cpu` (`waybar.nix:643-652`) | usage %, warning 70 / critical 90; left btop scratchpad | **native** `sysmon` (`hw_cpu`, member of the hardware capsule group) | `[widget.hw_cpu] type = "sysmon"`, `stat = "cpu_usage"`, `actions.left = "exec toggle-btop"` | The btop scratchpad is **kept** (`toggle-btop`). Thresholds are global under `[system.monitor]`. |
| `memory` (`waybar.nix:654-662`) | used GB | **native** `sysmon` (`hw_ram`) | `[widget.hw_ram] stat = "ram_used"`, `actions.left = "exec toggle-btop"` | `{used}G` becomes the sysmon value with units. |
| `temperature` (`waybar.nix:664-675`) | package temperature; hwmon path `coretemp.0`, critical 90 | **native** `sysmon` (`hw_temp`) | `[widget.hw_temp] stat = "cpu_temp"`, `actions.left = "exec toggle-btop"` | Sensor selection is automatic; `[system.monitor] cpu_temp_sensor_path` can pin a hwmon file. |
| `clock` (`waybar.nix:538-544`) | `{:%H:%M:%S}`; left alacritty `cal -3`, right copies the date | **native** `clock` | `[widget.clock] format = "{:%H:%M:%S}"`, `actions.left = "panel-toggle control-center calendar"`, `actions.middle = "exec toggle-calendar"`, `actions.right = "exec copy-date"` | Seconds preserved. Calendar is both a control-center tab (left) and the old Alacritty scratchpad (middle). |
| `custom/clock-date` (`waybar.nix:546-551`) | `%A, %e %B %Y`, revealed by the clock drawer; right copy | **native** second `clock` (`clock_date`) in the clock capsule group; **kept** `copy-date` | `[widget.clock_date] type = "clock"`, `format = "{:%A, %e %B %Y}"`, `actions.right = "exec copy-date"` | Drawer reveal becomes an accordion group expansion. |
| `custom/updates` (`waybar.nix:677-684`) | `󰚰` when `~/dotfiles/flake.lock` is older than 24 h; left runs `nix flake update` in Alacritty | **`john/dotfiles-bar:updates`** | `[widget.updates]`; click runs `nix flake update` in a terminal | Terminal chosen by `noctalia.runInTerminal` (`$TERMINAL`, else first on PATH); pin it with the plugin's `terminal` setting. |
| `custom/thermostat` (`waybar.nix:834-845`, arch only) | `<cur>° → <target>°`; right AC toggle, middle thermostat toggle, scroll setpoint | **`john/dotfiles-bar:thermostat`** | `[widget.thermostat]`; `widget.actions.middle = "none"` so `onMiddleClick` fires; `hass-macro`/`hass-thermostat-status` unchanged | SIGRTMIN+8 becomes `noctalia msg plugin john/dotfiles-bar:thermostat all refresh` from `hass-macro` (`nixos/modules/keybind.nix`, `signal_bar`). The 30 s poll remains. |
| `custom/vast` (`waybar.nix:723-733`) | balance/instance/runway; left clears cache | **`john/dotfiles-bar:vast`** | `[widget.vast]`; `vast-waybar-status` + `/tmp/vast-waybar-status.json` (55 s TTL) | Click deletes the cache and re-polls instead of signalling Waybar. Empty output hides the widget, as before. |
| `custom/weather` (`waybar.nix:686-694`) | temp °F; left alacritty `wttr.in`; 3-day HTML tooltip | **native** `weather` | `[widget.weather] show_condition = true`, `show_temperature = true`, `actions.right = "exec toggle-weather"`; `[weather] unit = "imperial"` | Open-Meteo replaces wttr.in for the bar value; the Alacritty popup survives on right click. The 3-day HTML **tooltip** is gone. |
| `custom/theme` (`waybar.nix:714-721`) | ☀/☾; left `theme-switch toggle` | **native** `theme_mode` (`theme_toggle`) with an `exec` action | `[widget.theme_toggle] type = "theme_mode"`, `actions.left = "exec theme-switch toggle"` | Do **not** use the default `theme-mode-toggle`: it writes `[theme].mode` to `settings.toml` and skips `theme-switch`'s GTK/Alacritty/tmux work. Glyph follows the shell mode, which `theme-switch` sets through `theme-mode-set`. |
| `battery` (`waybar.nix:756-767`) | icon + capacity, warning 30 / critical 15 | **native** `battery` | `[widget.battery] hide_when_full = false` | Waybar's two-stage 30/15 classes become Noctalia's single warning threshold. |
| `custom/eww-hello` (`waybar.nix:747-754`) | `★`; left `eww open hello-world`, right close | **dropped** | — | The demo window (`eww/eww.yuck:2-32`) is gone; no bar trigger. |
| `custom/autoclicker` (`waybar.nix:735-745`) | mode glyph/timer; left toggle, middle cycle, right Eww menu | **`john/dotfiles-bar:autoclicker`** + **`john/dotfiles-bar:autoclicker-panel`** | `[widget.autoclicker]`; `widget.actions.middle = "none"`; right `togglePanel(...:autoclicker-panel)` | The `autoclicker watch` stream is unchanged. The settings GUI moves from Eww to a native panel (`autoclicker get/mode/set/status`, `autoclicker-target pick`). |
| `tray` (`waybar.nix:790-793`) | SNI icons | **native** `tray` | `[widget.tray] hide_passive = true` | Noctalia hosts `org.kde.StatusNotifierWatcher` itself. XEmbed-only apps are unsupported. The TeamSpeak flatpak override still works because it owns `org.kde.StatusNotifierItem-5-1`. |
| `pulseaudio` (`waybar.nix:769-788`) | icon + volume, bluetooth/muted variants; left `sinks.fish scarlett`, middle bluetooth, right pavucontrol, scroll volume | **native** `volume` | `[widget.volume] device = "output"`, `actions.left = "exec fish ~/.config/polybar/scripts/sinks.fish scarlett"`, `actions.middle = "exec fish ~/.config/polybar/scripts/sinks.fish bluetooth"`, `actions.right = "panel-toggle control-center audio"` | `sinks.fish` shortcuts are **kept**; `pavucontrol` becomes the audio tab. No separate input-volume widget; scroll step is 5%, not Waybar's 3%. |

Two widgets in this zone are new, not replacements: `notifications`
(`hide_when_no_unread = false`, left opens the notification tab, right toggles
DND) and `control-center` (left opens the home tab). Waybar had no equivalent.

### 1.4 Hover drawers (groups)

| Old group (line) | Renders | New target | Delta |
|---|---|---|---|
| `group/clock` (`waybar.nix:524-536`) with `clock` + `custom/clock-date` | hover drawer, 300 ms, `children-class = hidden-ck` | **native** capsule group `clock` with `members = ["clock" "clock_date"]`, `accordion = true`, `accordion_direction = "start"` | Expansion is Noctalia's accordion chip; no 300 ms `children-class` transition or per-group CSS. |
| `group/hardware` (`waybar.nix:628-641`) with `cpu`/`memory`/`temperature` | hover drawer, 300 ms, `children-class = hidden-hw` | **native** capsule group `hardware` with `members = ["hw_cpu" "hw_ram" "hw_temp"]`, `accordion = true` | Same three values; btop is still reachable by left-clicking any member. |

---

## 2. Eww panels

| Old window (`eww/eww.yuck` line) | Features | New target | Delta |
|---|---|---|---|
| `media-picker` (:141-224) | per-player play/pause, volume, pin; per-Firefox-tab mute, volume, focus; closes on mouse-out; top-center 504 px | **`john/dotfiles-bar:media-panel`** | Native panel, attached to the bar and opened near the click. Volume steps are still 5% (`media-picker-action` only does relative). Pin writes `/tmp/media-player-selected`; the bar reads it on its next poll, so there is no `kill -46` refresh — the panel calls `media-player`/panel refresh through IPC. Tab focus still depends on Hyprland Lua + Firefox title matching. |
| `tailscale` (:53-133) | tailnet/self identity, peer list, exit-node change, connect toggle, refresh | **`john/dotfiles-bar:tailscale-panel`** | Data from `tailscale-panel-data`, falling back to `tailscale status --json` if the helper is not installed. Connect/exit-node use `/run/wrappers/bin/sudo` explicitly, fixing Eww's bare-`sudo` silent failure. Panel is attached per-bar, not hard-coded to monitor 0. |
| `autoclicker-menu` (:244-343) | mode, interval, timer button, target any/focused/pick/clear, live details | **`john/dotfiles-bar:autoclicker-panel`** | Native controls; `autoclicker-target pick` runs slurp. No 1 s `ac_tick` defpoll — the panel refreshes on open and on its own update tick. |
| `hello-world` (:2-32) | demo window, monitor 0 top-right | **dropped** | Cosmetic only; its only trigger was the `eww-hello` star module (`waybar.nix:747-754`). |

---

## 3. Non-bar surfaces

The seven core surfaces (lock, wallpaper, clipboard, launcher, screenshots,
night light, polkit) plus the notification daemon and the incidental surfaces
that came with the old stack.

| Surface | Old implementation | New target | Config | Delta / limitation |
|---|---|---|---|---|
| **Lock screen** (7) | `hyprlock` + `hyprlock-theme` wrapper (old `theme.nix`); binds `CTRL+ALT+L`, `SUPER+F20` | **native** `[lockscreen]` | `enabled = true`, `lock_before_suspend = false`, `dnd = false`, `grace_period_seconds = 0`, `blurred_desktop = false`; fingerprint defaults on | PAM through `noctalia-pam-helper` on the `login` service (the old `security.pam.services.hyprlock` is gone); no failed-attempt counter; manual-only (idle behaviours disabled). `loginctl lock-session` now works. |
| **Wallpaper** (7) | `hyprpaper` with `-c state/current/hyprpaper.conf` (old `theme.nix`) | **native** `[wallpaper]` | `enabled = true` only; `fill_mode`/transitions stay at defaults; the image is fed by `theme-switch` | Per-monitor **image** assignment is not declarative (only global default + per-monitor directories with `per_monitor_directories = true`). The old single global image maps cleanly. |
| **Clipboard** (7) | `cliphist` + `wl-paste --watch` + `wofi --dmenu` (old `home.nix`) | **native** clipboard panel | `[shell] clipboard_enabled = true`; history size, auto-paste and clear-confirmation stay at defaults (100 entries, `auto`, confirm); `[storage] key_source = "secret-service"` | Encrypted at rest; images supported; password-manager copies excluded. Auto-paste needs Hyprland's `keyboard` permission. `wl-paste --watch` processes and the `cliphist` package are removed. |
| **Launcher** (7) | `wofi --show drun` (`home.nix:424`), `fuzzel` for dmenu-style scripts | **native** launcher + `noctalia dmenu` | `[shell.launcher]` at defaults (full layout, recent view, usage tracking, auto-paste); no keys overridden | No CSS/styling; theme comes from the palette. No `--width/--lines` flags. `noctalia dmenu` needs a running shell. `fuzzel` stays installed for `screenrec`'s clip menu but is no longer the app menu. |
| **Screenshots + editor** (7) | `grim`/`slurp` + `swappy` + `juush` (`home.nix:441-447`) | **native** screenshot + annotation editor | `[shell.screenshot]` at defaults (save + copy + freeze, PNG, `annotate = false`); juush via per-bind `--pipe-to-command` | Built-in editor replaces swappy. `pipe_to_command` always receives PNG on stdin and gets `NOCTALIA_SCREENSHOT_PATH`. Needs `wlr-screencopy`; window capture needs `ext-image-capture-source`. |
| **Night light** (7) | `gammastep` (old `home.nix`, skipped on secu/arch) | **native** `[nightlight]` | `enabled = compName != "secu" && compName != "arch"`, `temperature_day = 6500`, `temperature_night = 3500`; `[location]` set by coordinates | One temperature for all outputs; schedule shared with weather/theme-auto. Needs `zwlr-gamma-control`. |
| **Polkit agent** (7) | `lxqt-policykit-agent` in the `hyprland.start` hook (`home.nix:571`) | **native** polkit agent | `[shell] polkit_agent = true`; `[shell.panel] polkit_placement = "floating"` | Must be the only agent; registered on the system bus. Fingerprint flow is undocumented. |
| Notifications | dunst (`services.dunst`), `dunstify`, `dunstctl reload` | **native** daemon + history + DND + filters | `[notification] enable_daemon = true`, `group_by_app = true`, `history_retention_hours = 0`, `position = "top_right"`, `keep_dismissed_in_history = true`; `[notification.filter.base_station_connect]` matches `blueman` / `^LHB-` with `show_toast = save_history = play_sound = false` | `org.freedesktop.Notifications` ownership moves to Noctalia; `x-dunst-stack-tag` no longer coalesces; `dunstctl` calls removed from `theme-switch`. The LHB pairing popup is the one explicitly filtered case. |
| Session / power menu | none (no wlogout) | **native** session panel | `[shell.session.actions]` = lock, logout, lock_and_suspend, reboot, shutdown (1–5) | New surface; suspend/reboot/shutdown resolve through logind. |
| OSD | none (pamixer/brightnessctl silent) | **native** OSD | `[osd] position = "top_center"`, `hide_delay_ms = 1400` | Appears for Noctalia-driven actions (`volume-up`, `brightness-up`, …) or `osd-show`; direct `pamixer` calls bypass it. |
| Tray | Waybar `tray` module | **native** `tray` widget | `[widget.tray]` | SNI only; daemon context menus rendered by Noctalia. |
| MPRIS | Waybar `custom/media` + Eww picker | **`john/dotfiles-bar:media`** + panel | `[shell.mpris] blacklist = []` | Per-player transport in Control Center → Media; the plugin keeps pin/Firefox-tab behaviour. |
| Screen recording | `screenrec` (wf-recorder + juush) | **kept external** | `screenrec` helper, keybinds unchanged | Not in Noctalia core; the official plugin would replace it with gpu-screen-recorder and lose the juush/Temporal upload. |
| Dock | none | **not enabled** | `[dock] enabled = false` | Available but off; the taskbar widget covers running apps. |
| Weather tab | wttr.in popup | **native** Control Center → Weather | `[weather] enabled = true`, `unit = "imperial"`, `refresh_minutes = 30`; `[location]` | Open-Meteo; no HTML tooltip. |
| Calendar | `cal -3` in Alacritty | **native** Control Center → Calendar | `[calendar] enabled = false` (no CalDAV account configured) | Calendar shows the date grid; events require `[calendar.account.*]`. |
| Screen time | none | **not enabled** | `[shell] screen_time_enabled = false` | Available; off to avoid new state. |
| Power profiles | none | **native** Control Center → Power (no `power_profile` widget placed) | requires `power-profiles-daemon` | New surface; no TLP/auto-cpufreq integration. |

---

## 4. Keybinds

All binds live in `nixos/home.nix` unless noted. `SUPER` = `mainMod`.
Line numbers in this section refer to the **pre-migration** file
(`git show HEAD:nixos/home.nix`); the current file has the same binds at
different lines. Binds not listed here (focus, workspace movement, PoE,
TeamSpeak, Discord passthrough) are unchanged and are not Noctalia's concern.

### 4.1 Changed binds

| Bind (line) | Old action | New action | Why |
|---|---|---|---|
| `SUPER+Space` (`home.nix:424`) | `wofi --show drun`, logging stdout to `~/drun_logs/` | `noctalia msg panel-toggle launcher` | Launcher replaces wofi. Usage is tracked by Noctalia (`track_usage`); the log file has no equivalent. |
| `SUPER+V` (`home.nix:438`) | `cliphist list \| wofi --dmenu \| cliphist decode \| wl-copy` | `noctalia msg panel-toggle clipboard` | Native history panel with search, pins, auto-paste. |
| `SUPER+SHIFT+N` (new) | — | `noctalia msg panel-toggle control-center notifications` | Direct access to the notification tab/history. |
| `SUPER+comma` (new) | — | `noctalia msg settings-toggle` | Opens Noctalia Settings (the only xdg-toplevel it creates; floated by a window rule). |
| `ALT+Tab` (new) | — | `noctalia msg window-switcher hold` | Hold semantics: the overlay stays while Alt is held; `ALT+SHIFT+Tab` adds `reverse`. |
| `CTRL+SHIFT+1`, `CTRL+SHIFT+ALT+1` (`home.nix:441-442`) | `grim -g (slurp) - \| wl-copy` | `noctalia msg screenshot-region --copy-to-clipboard --no-save-to-file` | Native region capture. |
| `CTRL+SHIFT+2` (`home.nix:443`) | `grim \| swappy -f -` then `juush` | `noctalia msg screenshot-region --annotate --no-save-to-file --no-copy-to-clipboard --pipe-to-command --pipe-command "fish -c 'set loc (screenshot_location); cat > $loc; juush $loc'"` | Built-in annotation editor replaces swappy; juush receives PNG on stdin. |
| `CTRL+SHIFT+3` (`home.nix:444`) | `slurp`, `sleep 1`, `grim`, `juush` | `sleep 1; noctalia msg screenshot-region --no-save-to-file --no-copy-to-clipboard --pipe-to-command --pipe-command "…same fish…"` | Freeze-before-select replaces the manual `sleep 1`; the sleep is kept to let the region overlay settle. |
| `CTRL+SHIFT+ALT+4`, `CTRL+SHIFT+4` (`home.nix:445-446`) | `grim -g (slurp) $loc; juush $loc` | same as `CTRL+SHIFT+3` (pipe → file → upload) | Native capture writes the file through the pipe hook. |
| `CTRL+ALT+L` (`home.nix:514`) | `hyprlock-theme` with `{ locked = true; }` | `noctalia msg session lock` with `{ locked = true; }` | hyprlock removed; Noctalia's lock screen is the only locker. |
| `Print` (`home.nix:516`) | `hl.dsp.dpms({ action = "enable" })` | **unchanged** | Turning panels on is harmless; the guard only matters for turning them off. |
| `SUPER+SHIFT+M` (`home.nix:517`) | `hl.dsp.exit()` | **unchanged** | Compositor-native logout; the session panel's `logout` action exists separately. |
| `XF86AudioRaiseVolume` / `LowerVolume` (`home.nix:524-525`) | `pamixer -i/-d 5` | `noctalia msg volume-up` / `volume-down` | Routes through Noctalia so the volume OSD appears. `pamixer` still works but is silent. |
| `SUPER+XF86AudioMute` (`home.nix:528`) | `focussed-vol-adjust.sh toggle` (per-app) | **unchanged** (per-app mute is not a Noctalia feature) | Global mute is `noctalia msg volume-mute` if a plain `XF86AudioMute` bind is added. |
| `F20` (`keybind.nix:230`) | dpms enable | **unchanged** (`hl.dsp.dpms`) | same as `Print`. |
| `SUPER+F20` (`keybind.nix:230`) | `hyprlock-theme` `{ locked = true; }` | `noctalia msg session lock` `{ locked = true; }` | same as `CTRL+ALT+L`. |

### 4.2 Unchanged binds

| Bind | Action | Note |
|---|---|---|
| `SUPER+Return` | Alacritty | terminal unchanged |
| `SUPER+CTRL+Space`, `SUPER+E` | Dolphin | unchanged |
| `SUPER+Q` | close window | compositor |
| `SUPER+SHIFT+T` | `theme-switch toggle` | still the authoritative light/dark switch |
| `SUPER+D/F/S`, `SUPER+SHIFT+S` | pseudo-tile, fullscreen, float, split | compositor |
| `CTRL+SHIFT+5` | clipboard text → `~/screenshots/clipboard.txt` → `juush` | not a Noctalia surface |
| `CTRL+SHIFT+9`, `ALT+9`, `CTRL+SHIFT+6`, `CTRL+SHIFT+0`, `CTRL+SHIFT+8` | `screenrec start/--reuse/stop/toggle/last` | recording stays external |
| `CTRL+SHIFT+7` | `hyprpicker` → `wl-copy` | unchanged |
| `SUPER+H/J/K/L` | focus | compositor |
| `SUPER+1..5`, `SUPER+SHIFT+1..5` | focus LEFT/RIGHT monitor + workspace | compositor; workspace ids 1–10 preserved |
| `SUPER+SHIFT+Q/W/E` | workspaces `ts` (15), `disc` (11), `obsidian` (12) | names still defined in `home.nix:261-268` |
| `SUPER+bracketleft/right` | workspace prev/next | compositor |
| `SUPER+CTRL+bracketright/left`, `CTRL+period/comma/slash` | move workspace to monitor | compositor |
| `SUPER+CTRL+I`, `SUPER+CTRL+SHIFT+I` | move to iPad headless / window to `ip1` | unchanged |
| `SUPER+CTRL+SHIFT+1..0`, `+Q/W/E` | move window to workspace | unchanged |
| `CTRL+ALT+M` | `hypr-blank` | unchanged; LockedHint guard still valid |
| `SUPER+A` (press/release) | `voxtype record start/stop` | widget shows the state |
| `SUPER+XF86AudioRaise/Lower` | `focussed-vol-adjust.sh` | per-app volume |
| `Prior`/`Next` | TeamSpeak mute / output mute | unchanged |
| `KP_Subtract`, `XF86AudioPrev` | Discord passthrough | unchanged |
| `CTRL+ALT+D`, `SUPER+CTRL+ALT+D` | PoE trade pass / alacritty | unchanged |
| `SUPER+Z/X`, `F10/F11/F12` | PoE chat / inventory | unchanged |
| `SUPER+Escape` | `autoclicker off` | daemon still runs |
| `SUPER+N` | `notify-send (slurp -p)` | unchanged |
| `SUPER+R` | rename workspace to window class | unchanged |
| `SUPER+mouse_down/up` | workspace next/prev | unchanged |
| `SUPER+LMB/RMB` | drag/resize window | unchanged |
| `F18` / `CTRL+F18` / `ALT+F18` / `SUPER+F18` | `hass-macro light-lamp` / `light-dresser` / `light-ac` / `light-bedroom` | unchanged; push `signal_bar` |
| `F19` / `CTRL+F19` / `ALT+F19` / `SUPER+F19` / `CTRL+ALT+F19` | `hass-macro thermostat-toggle` / `thermostat-down` / `thermostat-up` / `ac-toggle` / `fan-toggle` | unchanged; each calls `signal_bar` (thermostat refresh IPC) |
| `F21` / `CTRL+F21` | `hass-macro dyson-fan` / `desk-light` | unchanged; each calls `signal_bar` |

### 4.3 Removed binds

None. Every old bind has a target; binds whose program disappeared
(`hyprlock-theme`) now call Noctalia IPC.

---

## 5. Theme targets

`theme-switch` renders `~/.local/state/theme/current/<file>` and reloads every
consumer. Files marked "removed" are no longer rendered, linked or reloaded.

| Target | Old wiring | Status | New wiring |
|---|---|---|---|
| Alacritty | `render` `alacritty.toml`; imported by `.config/alacritty/alacritty.toml:1-8` (`live_config_reload`) | **kept** | `theme.nix:199`; Noctalia's alacritty template must stay disabled (it would write through this symlink into the checkout). |
| Fuzzel | `render` `fuzzel.ini` (`[colors]` only); symlink is the config | **kept** | `theme.nix:200`, link `theme.nix:267`; fuzzel remains for `screenrec` actions. |
| Hyprland borders | `render` `hyprland.lua`; `dofile`d from `extraConfig` | **kept** | `theme.nix:201`, `theme.nix:272-278`; `hyprctl reload config-only` still re-reads it. |
| tmux | `render` `tmux.conf`; catppuccin plugin `source-file` | **kept** | `theme.nix:202-206`; `theme-switch` still clears `@thm_*` and re-sources. |
| wallpaper | old `render` `hyprpaper.conf` | **replaced** | `render` `wallpaper-path` (`theme.nix:208`); `theme-switch` calls `noctalia msg wallpaper-set` (`theme-switch.sh:66-70`). |
| Waybar | `render` `waybar.css`; `@import` in generated `style.css` | **removed** | No Waybar. Bar styling is palette-derived in Noctalia. |
| Eww | `render` `eww.scss`; `@import "theme"` | **removed** | No Eww. |
| dunst | `render` `dunst.conf`; drop-in `dunstrc.d/50-theme.conf` | **removed** | Noctalia notification styling comes from `[notification]` and the palette. |
| hyprlock | full-file `hyprlock.conf` render + static dark symlink + `hyprlock-theme` | **removed** | Noctalia lock screen uses the palette; no lock config file. |
| hyprpaper | `render` `hyprpaper.conf` + custom unit | **removed** | `[wallpaper]` in Noctalia. |
| wofi | `render` `wofi.css` | **removed** | wofi not installed. |
| Noctalia palette | — | **added** | `~/.config/noctalia/palettes/CatppuccinDotfiles.json`, generated by `programs.noctalia.customPalettes` from the `palettes` table in `noctalia.nix` (same values as `theme.nix:24-81`), `[theme] source = "custom"`; both modes need a `terminal` block. |
| GTK3 | `theme-switch` writes `gtk-3.0/settings.ini` | **kept** | `theme-switch.sh:20-35`; Noctalia GTK template disabled so it cannot race this. |
| GTK4/Qt | `dconf write color-scheme`/`gtk-theme`; `QT_QPA_PLATFORMTHEME=xdgdesktopportal` | **kept** | `theme-switch.sh:55-57`, `theme.nix:258`; `sync_color_scheme = false` stops Noctalia writing the same dconf key. |
| nvim | `.vimrc:39` reads `~/.local/state/theme/mode`, catppuccin `flavour = "auto"` | **kept** | `theme-switch.sh:78-83` re-applies over nvim RPC sockets. |
| starship/fzf/bat | 16-colour ANSI only | **kept** | unchanged. |

---

## 6. Signal / refresh matrix

| Old trigger | Where | New trigger |
|---|---|---|
| `SIGRTMIN+9` (vast) | `sig.vast`, `waybar.nix:12-16`; helper `refresh 9` | `noctalia msg plugin john/dotfiles-bar:vast all refresh` (widget clears its cache on click; the 60 s poll remains) |
| `SIGRTMIN+12` (media) | `sig.media`; `media-player` refreshes after every click/scroll; Eww pin `kill -46` | `noctalia msg plugin john/dotfiles-bar:media all refresh` and the media panel's own `refresh`; no cross-process signal |
| `SIGRTMIN+14` (tailscale) | `sig.tailscale`; `tailscale-status`, `tailscale-exit-node` | `noctalia msg plugin john/dotfiles-bar:tailscale all refresh` + `…:tailscale-panel all refresh` from both helpers |
| `SIGRTMIN+8` (thermostat) | `pkill -RTMIN+8 waybar` in `hass-macro` (`keybind.nix:21-22` in the old tree; now `signal_bar`) | `noctalia msg plugin john/dotfiles-bar:thermostat all refresh` |
| `kill -USR2` (Waybar reload) | `waybar.service` `ExecReload` | none; `noctalia msg config-reload` reloads config, `theme-mode-set`/`wallpaper-set` apply theme changes |
| `dunstctl reload` | `theme-switch.sh:67` | none; Noctalia re-themes from the palette on `theme-mode-set` |
| `eww reload` | `theme-switch.sh:66` | none |

`noctalia msg plugin <entry> all refresh` is the universal replacement; every
first-party widget/panel implements `onIpc(event)` with `refresh` (deskflow adds
`toggle`).

---

## 7. Helper binary usage

| Helper | Consumed by |
|---|---|
| `media-player` | `john/dotfiles-bar:media` (status/toggle/focus/volume), media panel volume |
| `media-picker-data` | media panel (`players`, `tabs`) |
| `media-picker-action` | media panel (toggle, pin, player-volume, tab-volume, tab-mute, tab-focus) |
| `screenrec` | `john/dotfiles-bar:screenrec` (status/toggle/last), recording keybinds |
| `autoclicker`, `autoclicker-target` | `john/dotfiles-bar:autoclicker`, autoclicker panel, `SUPER+Escape` |
| `ipad-display` | `john/dotfiles-bar:ipad` (status/recover/create), isDesk only |
| `tailscale-status` | `john/dotfiles-bar:tailscale` |
| `tailscale-panel-data` | tailscale panel |
| `tailscale-toggle`, `tailscale-exit-node` | tailscale panel connect/exit-node, bar right-click |
| `deskflow-ctl` | `john/deskflow:bar`, `john/deskflow:panel`, isDesk only |
| `temporal-status` | `john/dotfiles-bar:temporal` |
| `nix-update-status` | `john/dotfiles-bar:updates` |
| `copy-date` | clock/date widget right-click |
| `vast-waybar-status` (legacy path) | `john/dotfiles-bar:vast` (`/tmp/vast-waybar-status.json` cache) |
| `hass-thermostat-status`, `hass-macro` | `john/dotfiles-bar:thermostat`, macropad binds |
| `voxtype` | `john/voxtype:bar` stream and click toggle |

---

## 8. Features dropped or relocated

1. `custom/eww-hello` + `hello-world` window — dropped (demo only).
2. Hover-expand **behaviour** of `group/clock`/`group/hardware` — replaced by
   click-to-expand accordion capsules; the 300 ms `children-class` transition
   and per-group CSS are gone.
3. Workspace **hover taskbar** (window icons from the workspace pill) — no
   `taskbar` widget is placed; the window list is gone unless one is added.
4. Media tooltip's full player/tab list on the bar — relocated into
   `media-panel`.
5. `blueman-manager` click-through — replaced by Control Center → Bluetooth.
6. dunst stack-tag coalescing — replaced by `group_by_app` plus the explicit
   LHB filter (README §5.1).
7. Pango-markup tooltips — plain text only.
8. Per-monitor static wallpaper image assignment — folders only.
9. Waybar's two-stage battery states 30/15 — single Noctalia warning threshold.
10. Waybar's `reload_style_on_change` / `SIGUSR2` live stylesheet reload — no
    stylesheet; theme changes come through `theme-mode-set`.
