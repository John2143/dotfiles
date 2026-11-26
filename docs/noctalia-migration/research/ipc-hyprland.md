# Noctalia 5.6.0 — IPC surface and Hyprland integration

Research target: **Noctalia 5.6.0** (`noctalia v5.6.0`, the C++/OpenGL ES shell), matching the
`noctalia` 5.6.0 package in the pinned nixpkgs (rev `93a9ed0a8660`, 2026-11-21). Doc citations use the
version-pinned prefix `https://docs.noctalia.dev/noctalia/v5.6.0/...`; implementation claims were checked
against the `v5.6.0` source tag. Research date: 2026-11-25.

The binary used for probes is the Nix store build:
`/nix/store/lv5v8yhknsxa9wiazmppq5l8pvbw304z-noctalia-5.6.0/bin/noctalia` (a wrapper around
`.noctalia-wrapped`). `noctalia --version` prints `noctalia v5.6.0`.

## (a) Complete IPC command surface

All commands have the shape `noctalia msg <command> [args]`; `noctalia msg --help` lists them and each
verb accepts its own `--help` ([IPC overview](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/)). The
v5.6.0 binary reports **118 commands**. The tables below reproduce that help output, grouped by the
docs' sections, with the richer argument semantics from the docs pages.

### Shell, config, settings, session

Page: [IPC → Shell](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/shell/)

| Verb | Arguments | Notes |
|---|---|---|
| `status` | — | Prints shell state as JSON. v5.6.0 keys: `barVisible`, `panelOpen`, `activePanelId`, `locked` (`application_ipc.cpp:72-81`); not documented key-by-key. |
| `log-level-status` | — | Prints current console log level. |
| `log-level-set` | `<debug\|info\|warn\|error>` | Runtime only; file log stays unfiltered. |
| `config-get` | `<path>` | Prints the effective value at a dotted path, including built-in defaults. Unknown path prints `error: path not found: <path>`. |
| `config-set` | `<path> <value>` | Value is parsed as TOML, validated against the schema, written to `settings.toml`, then reloaded. Strings must be TOML-quoted; a key segment containing `/` or `.` is quoted, e.g. `config-set 'plugin_settings."author/plugin".key' true`. |
| `config-reload` | — | Reloads the merged config stack immediately. |
| `settings-open` | `[context]` | Opens/focuses the Settings window, optionally at a section (e.g. `bar`). |
| `settings-close` | — | Closes Settings. |
| `settings-toggle` | `[context]` | Open/close Settings, optionally at a section. |
| `settings-open-plugin` | `<plugin-id>` | Opens an installed, enabled plugin's settings page. |
| `settings-open-widget` | `[bar-name] [widget-name]` | Opens Settings at a bar widget; from a widget gesture it targets that widget. **Not listed on the v5.6.0 IPC docs pages; present in `noctalia msg --help`.** |
| `window-switcher` | `[hold\|close\|hide] [all\|output\|workspace\|current] [reverse]` | Opens the Alt+Tab overlay; words combine in any order. `hold` implements Alt+Tab release semantics; `reverse` steps backward. |
| `session` | `<lock\|suspend\|lock-and-suspend\|logout\|reboot\|reboot-uefi\|shutdown>` | Runs the configured session action; logout uses UWSM when active, otherwise a compositor-native exit. |
| `greeter-sync` | — | Pushes wallpaper, colors and monitor layout to Noctalia Greeter. Not on the IPC pages, but documented under [Shell → Greeter sync](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/#greeter-sync); only registered when the greeter helper is installed. |

### Surfaces (bar, panels, dock, widgets)

Page: [IPC → Surfaces](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/surfaces/)

| Verb | Arguments | Notes |
|---|---|---|
| `bar-show` | `[bar-name] [monitor-selector]` | Omit both to show every bar on every output. |
| `bar-hide` | `[bar-name] [monitor-selector]` | Hides and blocks edge/pointer reveal until a show/toggle. |
| `bar-toggle` | `[bar-name] [monitor-selector]` | Does not block edge reveal. |
| `bar-reserve-toggle` | `[bar-name] [monitor-selector]` | Temporarily flips reserve-space; runtime only, not written to config. |
| `bar-auto-hide-set` | `<on\|off\|smart> [bar-name] [monitor-selector]` | Runtime-only auto-hide override. Help also accepts `true/false/1/0`. |
| `bar-layer-set` | `<top\|overlay\|auto> [bar-name] [monitor-selector]` | Runtime layer override; `auto` = top normally, overlay while an attached panel is open. |
| `panel-open` | `<id> [context]` | Opens a panel by id without toggling. |
| `panel-close` | `[id]` | Closes the active panel, or the named one if active. |
| `panel-toggle` | `<id> [context]` | Panel ids documented: `launcher` (optional query), `session`, `clipboard`, `wallpaper`, `control-center` (optional tab), and plugin `[[panel]]` ids `author/plugin:entry`. |
| `dock-show` | — | Shows all docks and persists the override. |
| `dock-hide` | — | Hides all docks and persists the override. |
| `dock-toggle` | — | Toggles and persists. |
| `dock-reload` | — | Reloads dock configuration. |
| `desktop-widgets-edit` | — | Enters desktop-widget edit mode. |
| `desktop-widgets-exit` | — | Leaves edit mode. |
| `desktop-widgets-toggle-edit` | — | Toggles edit mode. |
| `desktop-widgets-show` | — | Runtime-only reveal (does not change the saved setting). |
| `desktop-widgets-hide` | — | Runtime-only hide; tears down widget instances. |
| `desktop-widgets-toggle` | — | Runtime-only flip; prints `shown` or `hidden`. |
| `lockscreen-widgets-edit` | — | Edit lockscreen widget layout (session must be unlocked). |
| `lockscreen-widgets-exit` | — | Leave lockscreen edit mode. |
| `lockscreen-widgets-toggle-edit` | — | Toggle lockscreen edit mode. |

### Media & UI (notifications, clipboard, media, wallpaper, theme, screenshots)

Page: [IPC → Media & UI](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/)

| Verb | Arguments | Notes |
|---|---|---|
| `notification-dnd-set` | `<on\|off>` | Suppresses/hides toasts; history still fills. |
| `notification-dnd-toggle` | — | Toggles Do Not Disturb. |
| `notification-dnd-status` | — | Prints `on` or `off`. |
| `notification-show` | `<summary> [body...]` | Internal Noctalia-origin toast; JSON payload also accepted (see (b)). |
| `notification-invoke-latest` | — | Invokes the most recent notification's `default` action. |
| `notification-clear-active` | — | Dismisses visible toasts; entries stay in history. |
| `notification-clear-history` | — | Removes all history entries. |
| `clipboard-clear` | — | Clears history; pinned entries survive; live selection untouched. |
| `clipboard-copy` | `<text>` | Sets the clipboard selection; everything after the verb is payload; 64 KiB IPC cap. |
| `clipboard-text` | — | Prints the newest clipboard text with no trailing newline. |
| `media` | `<next\|previous\|toggle\|play\|pause\|stop\|next-player\|previous-player\|volume-up\|volume-down\|volume-set> [step]` | Controls the active MPRIS player. |
| `wallpaper-random` | `[connector]` | Random wallpaper on all monitors or one connector. |
| `wallpaper-next` | `[connector]` | Next wallpaper in order. |
| `wallpaper-previous` | `[connector]` | Previous wallpaper in order. |
| `wallpaper-get` | `[connector]` | Prints the persisted default path, or the effective path for an output. |
| `wallpaper-set` | `[connector] <path>` | Persists to `settings.toml`; accepts an image path or `color:#RRGGBB[AA]`. |
| `theme-mode-get` | — | Prints resolved `dark`/`light` (honours `auto`). |
| `theme-mode-set` | `<dark\|light\|auto>` | Persists `[theme].mode` and reloads. |
| `theme-mode-toggle` | — | Toggles dark/light. |
| `color-scheme-get` | — | Prints `<source> <name>`, source ∈ `builtin`, `wallpaper`, `community`, `custom`. |
| `color-scheme-set` | `<builtin\|wallpaper\|community\|custom> <name>` | Persists `[theme].source` plus the selection and reloads. |
| `templates-apply` | — | Re-renders enabled theme templates without changing mode. |
| `screenshot-region` | `[options]` | Interactive region capture; needs `wlr-screencopy-unstable-v1`. |
| `screenshot-fullscreen` | `[pick\|all\|<connector>] [options]` | Focused monitor by default; `pick` opens the display picker; `all` is one combined desktop image. |
| `screenshot-window` | `[options]` | Focused window at native resolution; needs `ext-image-copy-capture-v1` and `ext-foreign-toplevel-image-capture-source-manager-v1`. |
| `screenshot-annotate` | `[options]` | Freezes every monitor and opens the annotation editor. |
| `annotate` | `[path...] [options]` | Draws over live apps, or opens an image file in the editor. |

Screenshot/annotate per-call options (documented, all commands accept them after the verb): `--save-to-file/--no-save-to-file`, `--copy-to-clipboard/--no-copy-to-clipboard`, `--pipe-to-command/--no-pipe-to-command`, `--freeze-screen/--no-freeze-screen`, `--confirm-region`, `--remember-last-region`, `--show-cursor`, `--annotate`, `--skip-annotate-on-copy-save`, `--close-on-copy`, `--close-on-save`, `--copy-on-close`, `--pipe-command <cmd>`, `--directory <dir>`, `--filename-pattern <pat>`, `--append-mode-suffix`, `--format <png|jpeg|webp|jxl>`, `--quality <1-100>`. They map one-to-one onto `[shell.screenshot]` keys.

The v5.6.0 docs' Media & UI page has **no `color-pick` command**; `color-pick` exists only in the
unversioned/latest docs and in post-5.6.0 source (`git show main:src/cli/schema_msg.h`). It is absent
from the 5.6.0 binary's `--help`.

### Plugins

Page: [IPC → Plugins](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/plugins/)

| Verb | Arguments | Notes |
|---|---|---|
| `plugin` | `<author/plugin:entry> <target[:bar-name]> <event> [payload]` | Dispatches to the entry's `onIpc(event, payload)`. Target: `focused`, a connector (`DP-1`), `focused:default`/`DP-1:top`, or `all`. `all` is required for singleton `[[service]]`/`[[panel]]` entries. Payload is the raw remainder of the line. |
| `plugins` | `<list\|enable\|disable\|update\|source>` | `enable/disable <author/plugin>`; `update <source-name>`; `source list`; `source add <name> <git\|path> <location>`; `source remove <name>`. |

### System controls

Page: [IPC → System Controls](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/system-controls/)

| Verb | Arguments | Notes |
|---|---|---|
| `osd-enable` | — | Runtime-only; does not change `[osd].enabled`. |
| `osd-disable` | — | Closes any visible popup. |
| `osd-toggle` | — | Prints `on`/`off`. |
| `osd-show` | `<icon> [value...]` | Custom popup; JSON payload accepted (see (b)). |
| `volume-set` | `<value>` | `65`, `65%`, or `0.65`; clamped to 100% unless `[audio] enable_overdrive = true` (then 150%). |
| `volume-up` | `[step]` | Default step 5%. |
| `volume-down` | `[step]` | Default step 5%. |
| `volume-mute` | — | Toggles output mute. |
| `volume-osd` | `[value]` | Shows the OSD without changing volume. |
| `mic-volume-set` | `<value>` | Normalized or percent. |
| `mic-volume-up` | `[step]` | Default step. |
| `mic-volume-down` | `[step]` | Default step. |
| `mic-mute` | — | Toggles microphone mute. |
| `mic-volume-osd` | `[value]` | Shows the mic OSD without changing volume. |
| `brightness-set` | `[target] <value>` | Target `current`, `all`, `*`, connector, or monitor selector. |
| `brightness-up` | `[target] [step]` | Default step. |
| `brightness-down` | `[target] [step]` | Default step. |
| `brightness-osd` | `<value>` | No monitor target. |
| `brightness-list-backlight-devices` | — | Lists sysfs backlight device names. **Not on the v5.6.0 IPC docs pages; present in `--help`.** |
| `keyboard-backlight-set` | `<0-100>` | Sets all keyboard backlights. |
| `keyboard-backlight-up` | — | +5%. |
| `keyboard-backlight-down` | — | −5%. |
| `keyboard-backlight-toggle` | — | Toggles all keyboard backlights. |
| `keyboard-backlight-osd` | `<value>` | OSD without changing brightness. |
| `nightlight-enable` | — | Enables the schedule. |
| `nightlight-disable` | — | Disables the schedule. |
| `nightlight-toggle` | — | Toggles the schedule. |
| `nightlight-force-toggle` | — | Forces on / returns to schedule. |
| `wifi-enable` | — | Wi-Fi radio on. |
| `wifi-disable` | — | Wi-Fi radio off. |
| `wifi-toggle` | — | Toggles Wi-Fi. |
| `wifi-status` | — | Prints `on`/`off`. |
| `bluetooth-enable` | — | Adapter on. |
| `bluetooth-disable` | — | Adapter off. |
| `bluetooth-toggle` | — | Toggles Bluetooth. |
| `bluetooth-status` | — | Prints `on`/`off`. |
| `network-toggle` | — | Disconnects the active network, or reconnects when nothing is connected. **Not on the v5.6.0 IPC docs pages; present in `--help`.** |
| `caffeine-enable` | — | Prevents idle actions. |
| `caffeine-disable` | — | Allows idle actions again. |
| `caffeine-toggle` | — | Toggles caffeine. |
| `power-set` | `<profile>` | Requires `org.freedesktop.UPower.PowerProfiles`; exact profile id (e.g. `performance`, `balanced`, `power-saver`). |
| `power-cycle` | `[next\|prev]` | Help accepts a direction (default forward); the v5.6.0 docs describe it as argument-less and wrapping. |
| `dpms-on` | — | Monitors on. |
| `dpms-off` | — | Monitors off; defers until a lock transition has a safe frame. |
| `keyboard-layout-cycle` | — | Cycles the compositor keyboard layout. **Not on the v5.6.0 IPC docs pages; present in `--help`.** |
| `effects-profile-set` | `<output\|input> <profile>` | Sets an EasyEffects profile. **Not on the v5.6.0 IPC docs pages; present in `--help`.** |

`nightlight-temperature-set` and `nightlight-temperature-clear` appear in the unversioned/latest docs
but **not** in the v5.6.0 docs, the v5.6.0 binary, or the `v5.6.0` source tag. They are post-5.6.0.

### Workspaces

| Verb | Arguments | Notes |
|---|---|---|
| `workspace-switch` | `<next\|prev>` | Adjacent workspace on the target monitor; stops at both ends. **Undocumented on the v5.6.0 IPC pages.** |
| `workspace-alert-add` | `<workspace>` | By number, name, or id. **Undocumented on the IPC pages.** |
| `workspace-alert-add-window` | `<window-id>` | Adds an alert for a window. |
| `workspace-alert-clear` | `<workspace>` | Clears one alert. |
| `workspace-alert-clear-all` | — | Clears all alerts. |
| `workspace-alert-status` | — | Prints alerts. |
| `taskbar-cycle` | `<next\|prev>` | Steps to the adjacent task/workspace group in the invoking taskbar. **Undocumented on the IPC pages.** |

## (b) How external scripts push state into the shell

### Transport and invocation rules

`noctalia msg` is **not D-Bus**. It is a line-oriented Unix stream socket:

- Server path: `${XDG_RUNTIME_DIR}/noctalia-${WAYLAND_DISPLAY}.sock`, with `WAYLAND_DISPLAY` defaulting to
  `wayland-0` when unset (`src/ipc/ipc_client.cpp:19-29`, `src/ipc/ipc_service.cpp:316-325`).
- Client sends `<caller-cwd>\x1e<command>` then shuts down the write side and reads the response until EOF.
  Relative paths therefore resolve against the caller's cwd, not the shell's (`ipc_client.cpp:60-113`).
- Connect/send/recv timeouts are 2 seconds; if the socket is absent the client prints
  `error: noctalia is not running` and exits 1 (probe: `noctalia msg status` → that exact message, exit 1).
- The server caps a command line at 64 KiB (`src/ipc/ipc_service.cpp:22`), which is why `clipboard-copy`
  payloads are documented as capped by the transport.
- Any response beginning with `error:` makes the CLI exit 1; otherwise exit 0. `ok`/data is printed
  verbatim.

Practical consequence: a systemd timer, cron job, or SSH command needs `XDG_RUNTIME_DIR` (and normally
`WAYLAND_DISPLAY`) in its environment to reach the right per-session socket. A job without them defaults
to `wayland-0` and may hit the wrong instance.

### OSD injection — `osd-show`

Two forms ([System Controls → OSD](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/system-controls/#osd)):

```sh
noctalia msg osd-show wifi "VPN connected"
noctalia msg osd-show '{"icon":"brightness-low","value":"40%","progress":0.4}'
noctalia msg osd-show '{"icon":"wifi-off","value":"VPN disconnected","inactive":true}'
```

JSON fields: `icon` (required string), `value` (string), `progress` (0–1, clamped, omit for text-only),
`inactive` (boolean). Custom popups obey `[osd.kinds].custom` and share the same OSD slot as built-in and
plugin popups. `osd-enable/disable/toggle` are runtime overrides and do not change `[osd].enabled`.

### Notification injection — `notification-show`

Non-JSON form: `notification-show <summary> [body...]`. JSON form supports `app_name`, `summary`
(required), `body`, `urgency` (`low|normal|critical`), `timeout_ms` (0 = persistent), `icon`, `category`,
`desktop_entry` ([Media & UI → Notifications](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/#notifications)).

Important semantic: these are **internal Noctalia notifications**. They are toast-only and are **not
stored in notification history**; the same toast/sound filters apply, but the `save_history` flag does
not ([Notifications service](https://docs.noctalia.dev/noctalia/v5.6.0/services/notifications/)).
Calendar reminders are the documented exception. To inject a notification that behaves like an external
Freedesktop notification, use `notify-send`/the `org.freedesktop.Notifications` API instead (Noctalia
owns that name by default, see (e)).

### Config injection — `config-get` / `config-set`

- `config-get <path>` reads the **effective** merged value, including built-in defaults. The source prints
  the TOML node (`src/config/config_service.cpp:2075-2089`); expect TOML syntax in the output (strings may
  be quoted — inferred from toml++ serialization, not tested live).
- `config-set <path> <value>` builds a TOML `path=value` delta, validates it against the schema (new
  diagnostics are rejected), writes the override into the state-directory `settings.toml`, and reloads
  (`config_service.cpp:2090-2134`). It is a **persistent GUI-layer write**, not a write to your
  hand-written config: `settings.toml` is loaded last and wins
  ([How configuration works](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/#which-value-wins)).
- Paths are dotted TOML keys. A segment containing `/` or `.` must be TOML-quoted, e.g.
  `config-set 'plugin_settings."author/plugin".key' true`; strings must be quoted:
  `config-set shell.font_family "'Noto Sans'"`.
- Setting a value equal to the effective lower-layer value removes the redundant override rather than
  storing it (docs, same section).

This is the only generic "push arbitrary state" command: any schema-valid setting (theme, widget text,
bar behavior, plugin settings, etc.) can be changed and hot-reloaded this way.

### Bar-widget updates

There is **no generic `widget-set` IPC verb**. External control of bar widgets is through three paths:

1. **Config.** Widgets are plain TOML (`[widget.<name>]`). `config-set` can rewrite a widget field (e.g.
   `config-set widget.hostname.text "'new text'"`), and the shell reloads the config. This is an
   inference from the documented `config-set` + hot-reload behavior; it was not exercised against a live
   shell.
2. **Widget actions.** A widget's `[widget.<name>.actions]` table binds gestures to the same command
   vocabulary as `noctalia msg`: a bare command runs IPC, `exec ...` runs a shell command, `none` unbinds
   ([Bar → Widget Actions](https://docs.noctalia.dev/noctalia/v5.6.0/bar/actions/)). The bar never takes
   keyboard focus, so there are no modifier chords. Bindings live in four layers, later wins:
   built-in defaults → widget defaults → `[bar.<name>.actions]` → `[widget.<name>.actions]`.
3. **Plugin IPC.** Plugin-provided widgets/panels/services are entry instances with an `onIpc` callback;
   `noctalia msg plugin <author/plugin:entry> <target> <event> [payload]` is the supported way to push an
   event into them. Target `all` is required for services/panels; per-output targets are `focused`,
   a connector, or `<target>:<bar-name>` (`src/scripting/plugin_ipc.cpp:42-140`).

Built-in widgets' displayed data (volume, media, battery, network, workspaces, notifications, etc.) is
driven by their services; the documented way to change that state is the corresponding IPC command
(`volume-set`, `media toggle`, `wallpaper-set`, `theme-mode-set`, …), not a widget-level setter.

### Other script-facing entry points

- `noctalia dmenu [-p prompt]` reads newline-separated items on stdin, shows them in the launcher, and
  prints the selection to stdout (offline CLI, no running shell needed for `--help`; the selection path
  needs the shell).
- `noctalia config validate [path]` / `config export` / `config settings-count` / `config replay-report`
  for validation and support tooling.
- `noctalia theme ...` generates palettes from an image; `noctalia firefox-theme ...` is the Pywalfox
  host helper; `noctalia completions <shell>` re-generates completions from the live schema.
- Hooks run shell commands on shell events; use `noctalia msg ...` inside them. Documented events include
  `started`, `wallpaper_changed`, `colors_changed`, `theme_mode_changed`, session lock/unlock,
  `logging_out`, `rebooting`, `shutting_down`, Wi-Fi/Bluetooth, battery, and power-profile changes
  ([Hooks](https://docs.noctalia.dev/noctalia/v5.6.0/automation/hooks/)).

## (c) Hyprland integration

### Autostart

Docs: add to the `hyprland.start` hook in `~/.config/hypr/hyprland.lua`:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
end)
```

Alternatively use `noctalia --daemon` if the starter expects the command to return after the shell has
initialized; daemon mode returns after init and starts the optional polkit agent asynchronously
([Running Noctalia](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/running-the-shell/)).
Noctalia does **not** manage session autostart from Settings (FAQ).

### Does Noctalia register global keybinds? No.

- Docs FAQ: “Noctalia Settings does not create compositor keybinds. Keybinds belong in your compositor's
  configuration; Noctalia only receives the IPC command.”
  ([FAQ](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/faq/)).
- `[keybinds]` is **not** a global shortcut registry. It centralizes chords used *inside* Noctalia
  surfaces (validate/cancel/arrows/tab/copy/save/select-all/delete). Super/Win/Meta/Logo/Mod4 chords are
  **rejected as compositor-reserved** and are a config parse error
  ([Configuration → Shell → Keybinds](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/#keybinds)).
- Source/protocol probe: `grep -rni 'global.*shortcut\|GlobalShortcuts' src protocols` returns 0 matches;
  the bundled protocol XMLs contain no global-shortcuts protocol. Noctalia binds
  `hyprland-focus-grab-v1` and `hyprland-toplevel-mapping-v1`, which are focus/window mapping, not
  keybind registration.
- Therefore there is nothing to "disable": to remove a Noctalia shortcut, remove or rebind the
  `hl.bind(...)` in your Hyprland config. The only keyboard Noctalia takes is focus on its own layer
  surfaces while they are open (launcher, panels, window switcher, lock screen).

Docs' recommended Hyprland bind block (place in `hyprland.lua`):

```lua
local mainMod = "SUPER"
local ipc = "noctalia msg "
hl.bind(mainMod .. "+Space", hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"))
hl.bind(mainMod .. "+S", hl.dsp.exec_cmd(ipc .. "panel-toggle control-center"))
hl.bind(mainMod .. "+comma", hl.dsp.exec_cmd(ipc .. "settings-toggle"))
hl.bind("ALT + Tab", hl.dsp.exec_cmd(ipc .. "window-switcher hold"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd(ipc .. "window-switcher hold reverse"))
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(ipc .. "volume-up"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(ipc .. "volume-down"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(ipc .. "volume-mute"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(ipc .. "brightness-up"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down"))
```

### Window rules

Only one window rule is recommended, for the Settings window (a normal xdg-toplevel, app id
`dev.noctalia.Noctalia` — `src/shell/settings/settings_window.cpp:104,517`):

```lua
hl.window_rule({
  match = { class = "dev.noctalia.Noctalia" },
  float = true,
  size = "monitor_w*0.5625 monitor_h*0.85",
})
```

All other Noctalia surfaces are layer-shell surfaces, not windows, so window rules do not apply to them.
The docs do not require any other window rule. Noctalia itself never creates window rules: probe
`grep -rni 'windowrulev2\|keyword windowrule\|layerrule' src` returns 0.

### Layer rules and namespaces

Docs require (or strongly recommend) disabling Hyprland's own layer animations, because Noctalia animates
its surfaces and Hyprland's `layersIn`/`layersOut` causes tearing: “Add this rule even if you do not use
blur.”

```lua
hl.layer_rule({
  name = "noctalia-no-anim",
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
  no_anim = true,
})
```

Optional blur rule (same namespace regex) adds `ignore_alpha = 0.5`, `blur = true`, `blur_popups = true`.

The namespace list in that regex is a subset of what the v5.6.0 source creates. Exact namespaces
(`src/...` at tag v5.6.0):

| Namespace | Source |
|---|---|
| `noctalia-bar-<bar-name>` | `src/shell/bar/bar.cpp:2514` |
| `noctalia-notification` | `src/shell/notification/notification_toast.cpp:2358` |
| `noctalia-dock` | `src/shell/dock/dock_geometry.cpp:292` |
| `noctalia-panel` | `src/shell/panel/panel_manager.cpp:975`, `persistent_panel_host.cpp:232` |
| `noctalia-attached-panel` | `src/shell/panel/panel_manager.cpp:1256` |
| `noctalia-osd` | `src/shell/osd/osd_overlay.cpp:617` |
| `noctalia-window-switcher` | `src/shell/switcher/window_switcher.cpp:1738` |
| `noctalia-backdrop` | `src/shell/backdrop/backdrop.cpp:243` |
| `noctalia-wallpaper` | `src/shell/wallpaper/wallpaper.cpp:1282` |
| `noctalia-desktop-widget-<type>-<uid>` | `src/shell/desktop/desktop_widgets_host.cpp:44` |
| `noctalia-desktop-widgets-editor`, `noctalia-lockscreen-widgets-editor` | `src/shell/desktop/editor/desktop_widgets_editor_types.cpp:6,16` |
| `noctalia-screen-corner` | `src/shell/screen_corners/screen_corners.cpp:134` |
| `noctalia-plugin:<entry-id>` | `src/shell/plugin_layer/plugin_layer.cpp:141` |
| `noctalia-annotate`, `noctalia-screenshot-region` | `src/capture/annotation_overlay.cpp:810`, `screenshot_region_overlay.cpp:436` |
| `noctalia-overview-launcher` | `src/shell/overview/overview_launcher_capture.cpp:131` |

So a rule copied from the docs will not blur/animate-suppress the backdrop, wallpaper, plugin layers,
desktop widgets, screenshot/annotate overlays, or screen corners. That may be intentional (blurring the
wallpaper layer is pointless), but if you want `no_anim` on all Noctalia layers, extend the regex.

### Permissions / hyprctl

Noctalia does **not** invoke `hyprctl`. Probe: `grep -rn 'hyprctl' src` returns 0. It talks to Hyprland
directly over the compositor's Unix sockets:

- Request socket: `${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket.sock`, falling back to
  `/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket.sock`.
- Event socket: `.socket2.sock` in the same directory.
- Source: `src/compositors/hyprland/hyprland_runtime.cpp:251-282`.

It also detects the Hyprland config provider (`j/status` → `configProvider == "lua"`) and switches between
`hl.dsp.*` Lua dispatchers and legacy dispatchers (`hyprland_runtime.cpp:284+`, `hyprland_output_backend.cpp:119-157`,
`hyprland_workspace_backend.cpp:57-59`). So a Lua config is natively supported; nothing needs to be
translated to the legacy config language.

If `ecosystem.enforce_permissions = true`, the docs require two allow rules (and a Hyprland restart, since
permission rules are not reloaded on config reload):

```lua
hl.permission("^/usr/bin/noctalia$", "screencopy", "allow")
hl.permission("^hl-virtual-keyboard-noctalia$", "keyboard", "allow")
```

- `screencopy`: screenshots and lock-screen desktop capture.
- `keyboard`: clipboard and launcher auto-paste; the virtual keyboard is named
  `hl-virtual-keyboard-noctalia`.

On Nix, the binary is not at `/usr/bin/noctalia`, so the first regex as written will not match. Use the
store path (`readlink -f "$(command -v noctalia)"`) or a regex such as
`^/nix/store/[a-z0-9]+-noctalia-5\.6\.0/bin/\.?noctalia(-wrapped)?$`; this is an inference from the docs'
“change the binary path to match” instruction plus how Nix packages wrap binaries, **not tested against
enforced Hyprland permissions**.

The docs only mention `screencopy` and `keyboard` permissions; whether Hyprland's permission system also
gates command-socket dispatches is **unverified**. No additional permission is documented for the
Hyprland IPC socket itself.

## (d) Compositor settings and Home Manager authority

### What the compositor-settings pages actually do

The `docs/compositor-settings/*` pages are **recipes for the human**, not an integration that writes
config. The Hyprland page's own description is “Configure Hyprland for the best experience with
Noctalia. … recommended options”
(`<meta name="description">` on the v5.6.0 Hyprland page).

Probes for writers: `grep -rn 'hyprland\.lua\|hyprland\.conf\|config\.kdl' src` → 0 matches;
`grep -rn 'hyprctl' src` → 0 matches. Noctalia does not create, patch, or reload Hyprland/Niri/Sway
config files. It only reads compositor state and sends runtime dispatches over the compositor's IPC.

The Hyprland page asks you to add, manually:

1. **Autostart** via `hl.on("hyprland.start", ...)`.
2. **Aesthetic defaults** in `hl.config({})`: `general.gaps_in = 5`, `gaps_out = 10`;
   `decoration.rounding = 20`, `rounding_power = 2`, shadow (`enabled`, `range = 4`, `render_power = 3`,
   `color = 0xee1a1a1a`), blur (`enabled`, `xray`, `size = 3`, `passes = 2`, `vibrancy = 0.1696`). These
   are described as “general window appearance and functionality”, not Noctalia requirements.
3. **Persistent workspaces** (`hl.workspace_rule({ workspace = "1", monitor = "DP-1", persistent = true, default_name = "web" })`
   etc.) so empty workspaces stay visible in Noctalia's workspace indicator.
4. **IPC keybinds** (section above).
5. **Settings window rule** (float + size).
6. **Layer `no_anim` rule** (and optional blur rule).
7. **Permission rules** when `ecosystem.enforce_permissions = true`.

Only items 6 (animation glitches) and 7 (enforcement blocks functionality) are framed as correctness
requirements; 2–5 are experience recommendations. Item 3 is “for the best workspace indicator behavior”.

### Keeping a Home-Manager-managed Hyprland Lua config authoritative

Because Noctalia never writes Hyprland's file, HM remains authoritative by construction: generate
`~/.config/hypr/hyprland.lua` from HM as usual and put the Noctalia snippets in that generated file.
Noctalia will read the running compositor, not the file. If you later see `hl.*` settings change
themselves, the cause is not Noctalia.

The real authority conflict is inside Noctalia's own config stack:

- The HM module writes declarative settings to `$XDG_CONFIG_HOME/noctalia/config.toml` (via
  `xdg.configFile`), and custom palettes to `~/.config/noctalia/palettes/<name>.json`
  (`noctalia-dev/noctalia@v5.6.0:nix/home-module.nix:154-174`).
- Noctalia then loads, in order: built-in defaults → system defaults in `$XDG_CONFIG_DIRS/noctalia/` →
  every `*.toml` in `~/.config/noctalia/` (with `[include]`) → **GUI/IPC-managed overrides in
  `~/.local/state/noctalia/settings.toml`**, which win
  ([How configuration works](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/#which-value-wins)).
- Any Settings UI change, setup flow, wallpaper selection, or `config-set` writes to that state file.
  The docs explicitly warn that runtime wallpaper choices “take priority over `wallpaper.default.path`”
  ([NixOS page](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/nixos/)).
- There is **no read-only / “ignore state file” option** in v5.6.0. Probe against the v5.6.0 source:
  `grep -rn 'read_only\|readonly\|readOnly' src/config/schema | wc -l` → `0`. The documented
  remedy is to inspect or remove the redundant keys from
  `~/.local/state/noctalia/settings.toml`, or delete the file to clear all overrides. For wallpaper,
  remove the saved `path` entries under `[wallpaper.default]`, `[wallpaper.last]`, and
  `[wallpaper.monitors."<connector>"]`.
- The state file may be a symlink: “If the file is a symbolic link, Noctalia writes through to the link
  target and keeps the link in place.” Do **not** symlink it to an HM-managed file: Noctalia will mutate
  that file at runtime.

So the practical rule for an HM-authoritative setup is: curate `programs.noctalia.settings`, and treat
`~/.local/state/noctalia/settings.toml` as disposable app state — avoid GUI persistence and avoid
`config-set` for values HM owns, or reconcile/delete the state file after using them.

HM module options in the v5.6.0 flake module (`nix/home-module.nix`):

| Option | Type / default | Effect |
|---|---|---|
| `programs.noctalia.enable` | bool | Installs the package; enables the module. |
| `programs.noctalia.package` | package, nullable | Package to install/wrap. |
| `programs.noctalia.settings` | TOML attrset, raw string, or path | Written to `~/.config/noctalia/config.toml`. |
| `programs.noctalia.customPalettes` | attrsOf (JSON attrset/string/path) | Written to `~/.config/noctalia/palettes/<name>.json`. |
| `programs.noctalia.checkConfig` | bool, default `true` | Runs `noctalia config validate` on the generated TOML at build time. |
| `programs.noctalia.extraPackages` | list of packages, default `[]` | Adds commands to Noctalia's `PATH` by wrapping the package. |
| `programs.noctalia.systemd.enable` | bool | Creates a `Type=notify` user unit. |

**Docs/source mismatch:** the systemd-service docs say the Nix ordering guarantee requires
`programs.noctalia.systemd.target` to be the compositor target. The v5.6.0 **Home Manager** module has no
`systemd.target` option; it wires the unit to `config.wayland.systemd.target`
(`nix/home-module.nix:133-149`). The **NixOS** and **Hjem** modules do expose
`programs.noctalia.systemd.target` (default `graphical-session.target`). If you use the HM module under
Hyprland/uwsm, verify what `config.wayland.systemd.target` resolves to in your HM configuration.

## (e) systemd units and D-Bus names

### systemd

- Binary behavior: `noctalia --daemon` returns after the shell initializes; the optional polkit agent
  starts asynchronously afterwards ([Running Noctalia](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/running-the-shell/)).
- Shipped unit template `assets/noctalia.service.in`:
  - `[Unit] Description=Noctalia Wayland shell`, `PartOf=graphical-session.target`,
    `Before=graphical-session.target`, `After=niri.service`, `After=plasma-kwin_wayland.service`,
    `After=umbriel.service`, and for uwsm `After=wayland-session-waitenv.service`.
  - `[Service] Type=notify`, `ExecStart=@NOCTALIA_EXECUTABLE@`, `Restart=on-failure`.
  - Commented install targets include `WantedBy=wayland-session@hyprland.desktop.target` for uwsm-managed
    Hyprland.
- Hyprland/Sway are supported **only in uwsm sessions** for this unit, because they do not run as their
  own systemd user services ([systemd user service](https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/systemd-service/)).
- HM equivalent: `programs.noctalia.systemd.enable = true` creates `noctalia.service` with `Type=notify`,
  `PartOf/After/WantedBy = config.wayland.systemd.target`, `Before = <target minus graphical-session.target>`,
  `ExecStart = lib.getExe finalPackage`, `Restart=on-failure` (`nix/home-module.nix:129-150`).
- Recommended companion: `[shell] launch_apps_as_systemd_services` (default `false`) so apps launched from
  Noctalia survive shell restarts. Docs call this “Launch Apps as systemd Services”.

### D-Bus names owned/claimed by Noctalia

| Name / registration | Bus | When | Evidence |
|---|---|---|---|
| `org.freedesktop.Notifications` (`/org/freedesktop/Notifications`) | session | `[notification] enable_daemon = true` (default `true`) and the name is free. On KDE it requests `ReplaceExisting`; elsewhere it does not replace an existing owner. If the name is taken, it logs, keeps internal toasts, and retries on `NameOwnerChanged`. | docs `[notification] enable_daemon`; `src/dbus/notification/notification_service.cpp:24-78`; `src/app/application_services.cpp:163-255` |
| `org.kde.StatusNotifierWatcher` (`/StatusNotifierWatcher`) | session | Claims the watcher name when no other watcher owns it; otherwise becomes a client and registers `org.kde.StatusNotifierHost-<pid>`. | `src/dbus/tray/tray_service.cpp:23-25,685,713` |
| `org.freedesktop.ScreenSaver` (`/org/freedesktop/ScreenSaver` and `/ScreenSaver`) | session | Always attempted at startup. Implements `Inhibit`, `UnInhibit`, `ActiveChanged` so apps can suppress idle/lock. If the name cannot be acquired, the service disables itself and logs. | `src/dbus/idle/screensaver_service.cpp:16-38,115-170` |
| `dev.noctalia.Mpris` (`/dev/noctalia/Mpris`) | session | Always registered when the session bus is available. Control API: `GetPlayers`, `GetActivePlayer`, `SetActivePlayerPreference`, `ClearActivePlayerPreference`, signals `PlayersChanged`, `ActivePlayerChanged`, `TrackChanged`. | `src/dbus/mpris/mpris_service.cpp:61-62,1368-1400` |
| `dev.noctalia.Debug` (`/dev/noctalia/Debug`) | session | Always attempted; methods `EmitInternalNotification`, `SetVerboseLogs`, `GetVerboseLogs`. Undocumented on the docs site. | `src/debug/debug_service.cpp:11-25` |
| polkit agent registration at `/org/noctalia/PolkitAuthenticationAgent` | system (`org.freedesktop.PolicyKit1`) | Only when `[shell] polkit_agent = true` (default `false`). Noctalia registers as an agent; it does not own the PolicyKit name. | `src/dbus/polkit/polkit_agent.cpp:32,406-408`; [Shell settings](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/) |

### D-Bus names consumed by Noctalia

| Name | Purpose |
|---|---|
| `org.freedesktop.secrets` | Secret Service client for the storage master key and calendar credentials. Noctalia **never provides** a Secret Service; it requires GNOME Keyring, KWallet, or KeePassXC, or the file-based alternatives `[storage].key_source = "file"` / calendar `credential_source = "file"` ([Secret Service](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/secret-service/)). |
| `org.freedesktop.login1` | `Lock`/`Unlock` signals, `PrepareForSleep`, `SetLockedHint`, idle/sleep-delay inhibitors. This is how `loginctl lock-session` reaches Noctalia. |
| `org.freedesktop.UPower` and `org.freedesktop.UPower.PowerProfiles` | Battery and power-profile controls. |
| `org.freedesktop.NetworkManager`, `org.freedesktop.ModemManager1` | Wi-Fi/network state and toggles. |
| `org.mpris.MediaPlayer2.*` | Media player discovery/control. |
| `org.freedesktop.Accounts` | User account/avatar lookups. |
| systemd `$NOTIFY_SOCKET` (`sd_notify`) | `Type=notify` readiness/stopping. |

### Idle stack

- Idle **behaviors** use the Wayland `ext_idle_notifier_v1` protocol and honour active inhibitors
  ([Idle service](https://docs.noctalia.dev/noctalia/v5.6.0/services/idle/)).
- Caffeine uses `zwp_idle_inhibit_manager_v1` when available and a logind idle inhibitor as fallback
  (`src/idle/idle_inhibitor.cpp:25-43`).
- Apps' D-Bus `org.freedesktop.ScreenSaver` inhibits are received by Noctalia's own ScreenSaver service;
  while held, idle behaviors do not fire and a pre-action fade is cancelled (docs Idle page).
- Noctalia does not own a polkit *name*; it registers an agent with PolicyKit1 only when enabled.

### Notification-daemon ownership detail

`[notification] enable_daemon = false` means Noctalia does not claim `org.freedesktop.Notifications`;
internal toasts still work ([Notifications service](https://docs.noctalia.dev/noctalia/v5.6.0/services/notifications/)).
If another daemon later releases the name, Noctalia's `NameOwnerChanged` watch retries acquisition
(`application_services.cpp:236-255`). This is the main coexistence knob with dunst/mako/swaync.

## Unverified and open questions

- **Hyprland permission path under Nix.** Docs assume `/usr/bin/noctalia`; the Nix store path is
  different and the module may wrap the binary. The exact executable path Hyprland checks (wrapper vs
  `.noctalia-wrapped`) was not tested against `ecosystem.enforce_permissions = true`. The suggested
  store-path regex is an inference.
- **Whether Hyprland's permission system gates Noctalia's command-socket dispatches** (as opposed to
  screencopy/keyboard) is not stated in the Noctalia docs and was not tested.
- **`config-set` on a widget field to update a built-in bar widget** is inferred from the documented
  config hot reload and generic path setter; no live shell was available to observe the widget repaint.
- **`config-get` output formatting** (TOML quoting of top-level strings) is inferred from the toml++
  streaming in `config_service.cpp`; not observed live.
- **HM `programs.noctalia.systemd.target`.** The v5.6.0 HM module lacks it while the docs say it exists;
  the NixOS/Hjem modules have it. Whether a newer noctalia flake module adds it is outside this
  version-pinned review.
- **Hyprland `hl.permission` syntax/version.** The docs' Lua examples were taken as authoritative; the
  minimum Hyprland version that accepts `hl.permission` was not verified.

## Conclusions

1. **The IPC surface is large and script-complete.** 118 verbs in v5.6.0 cover shell state/config,
   surfaces, notifications, clipboard, MPRIS, wallpaper/theme, screenshots/annotation, plugins, audio,
   brightness, keyboard backlight, network, power, idle, and workspaces. Most migration glue can be
   `noctalia msg ...` rather than custom daemons.
2. **State injection is deliberately narrow.** `osd-show` and `notification-show` are the only direct
   "display this" primitives; `config-set` is the generic, persistent state mutator; plugin IPC is the
   only extension-level push channel. There is no generic bar-widget setter.
3. **Noctalia registers no global keybinds.** Keybinds are entirely compositor-side. The `[keybinds]`
   table is internal surface navigation and rejects Super/Meta chords. Nothing needs disabling; remove
   the `hl.bind` lines instead.
4. **Hyprland integration is runtime-only.** Noctalia reads/drives Hyprland over `.socket.sock`/
   `.socket2.sock`, supports the Lua config provider natively, and never runs `hyprctl` or writes
   compositor config. The docs' compositor-settings pages are manual recipes. The only mandatory config
   work is the layer `no_anim` rule (to avoid glitches) and permission rules when enforcement is on.
5. **Home Manager authority is safe for Hyprland, fragile for Noctalia's own settings.** Noctalia cannot
   overwrite the HM-generated Lua file, but its state `settings.toml` overrides HM's `config.toml` and is
   written by GUI, setup, wallpaper, and `config-set`. An HM-authoritative deployment must avoid or
   reconcile that file; there is no read-only switch in 5.6.0.
6. **The D-Bus footprint is real but mostly conditional.** Noctalia claims `org.freedesktop.Notifications`
   by default when the name is free, takes `org.kde.StatusNotifierWatcher` when free, owns `org.freedesktop.ScreenSaver`, and
   exposes `dev.noctalia.Mpris`/`dev.noctalia.Debug`; polkit agent registration is opt-in; Secret Service
   is client-only. Plan for exactly one notification daemon and one polkit agent per session.
7. **Documentation drift matters for 5.6.0.** `nightlight-temperature-set/-clear` and `color-pick` are
   post-5.6.0 and must not be used in a 5.6.0 migration. Most `--help` verbs that are absent from the 5.6.0 IPC
   pages are still real commands: `brightness-list-backlight-devices`, `effects-profile-set`,
   `keyboard-backlight-*` ×5, `keyboard-layout-cycle`, `network-toggle`, `settings-open-widget`,
   `taskbar-cycle`, `workspace-alert-*` ×5, and `workspace-switch`; `greeter-sync` is documented under
   Shell settings instead. The binary is the authoritative list.

## Source Evaluation

1. **Noctalia v5.6.0 binary `noctalia msg --help`** (Nix store build) — primary, generated from the
   live command registry. Strongest evidence for the complete verb list and arities; cannot show runtime
   semantics.
2. **`noctalia-dev/noctalia@v5.6.0` source** — primary implementation. Used for socket paths, mode
   ownership, namespace strings, and negative probes. Exact but reflects code, not necessarily intended
   UX.
3. **[IPC overview](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/)** — official, version-pinned;
   confirms `--help` discovery and compositor-agnostic binds.
4. **[IPC → Shell](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/shell/)** — official; config-get/set,
   session, switcher semantics.
5. **[IPC → Surfaces](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/surfaces/)** — official; bar/panel/
   dock/widget semantics.
6. **[IPC → Media & UI](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/)** — official;
   notification/OSD-adjacent, clipboard, wallpaper, theme, screenshot options.
7. **[IPC → System Controls](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/system-controls/)** —
   official; OSD JSON, volume/brightness/nightlight/power semantics.
8. **[IPC → Plugins](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/plugins/)** — official; plugin target
   and source-management semantics.
9. **[Hyprland compositor settings](https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/hyprland/)**
   — official; the only source for the exact Lua snippets, namespace regex, and permission rules.
10. **[How configuration works](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/)** — official;
    load order and the `settings.toml` override rule, which is the core of the HM-authority question.
11. **[systemd user service](https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/systemd-service/)**
    — official; uwsm/Hyprland ordering and unit intent.
12. **[FAQ](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/faq/)** — official; the explicit
    statement that Settings does not create compositor keybinds and does not manage autostart.

## Bibliography

- [IPC overview](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/)
- [IPC → Shell](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/shell/)
- [IPC → Surfaces](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/surfaces/)
- [IPC → System Controls](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/system-controls/)
- [IPC → Media & UI](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/)
- [IPC → Plugins](https://docs.noctalia.dev/noctalia/v5.6.0/ipc/plugins/)
- [Hyprland](https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/hyprland/)
- [Noctalia systemd user service](https://docs.noctalia.dev/noctalia/v5.6.0/compositor-settings/systemd-service/)
- [How configuration works](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/)
- [Shell settings / Keybinds](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/shell/)
- [Secret Service & keyrings](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/secret-service/)
- [Notifications service](https://docs.noctalia.dev/noctalia/v5.6.0/services/notifications/)
- [Idle service](https://docs.noctalia.dev/noctalia/v5.6.0/services/idle/)
- [Running Noctalia](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/running-the-shell/)
- [NixOS / Home Manager module](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/nixos/)
- [FAQ](https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/faq/)
- [Hooks](https://docs.noctalia.dev/noctalia/v5.6.0/automation/hooks/)
- [Bar → Widget Actions](https://docs.noctalia.dev/noctalia/v5.6.0/bar/actions/)
- [Plugin entries](https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/entries/)
- Noctalia source, tag `v5.6.0`: https://github.com/noctalia-dev/noctalia.git (tag `v5.6.0`)
  (files cited inline as `noctalia-dev/noctalia@v5.6.0:<path>:<line>`)
- Pinned nixpkgs package definition (5.6.0):
  https://raw.githubusercontent.com/NixOS/nixpkgs/93a9ed0a8660/pkgs/by-name/no/noctalia/package.nix
