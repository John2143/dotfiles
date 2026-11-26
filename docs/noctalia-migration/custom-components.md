# First-party plugin maintenance guide

Three Luau plugins live in `noctalia-plugins/` and are enabled as a local `path`
source. This guide covers their layout, the manifest rules Noctalia v5.6.0
enforces, every entry and IPC hook, the shared Waybar-JSON helper, and how to
lint/validate changes locally.

Noctalia plugins are **Luau only** (Lua 5.1-derived, Luau syntax: `+=`, string
interpolation, `--!nonstrict`). Each entry runs in its own isolated Luau VM
inside the shell process, off the UI thread, with per-call time budgets. There is
no JS, QML or plain-Lua runtime, and no sandbox: a plugin is trusted code.

---

## 1. Plugin API level

Every manifest declares:

```toml
plugin_api = 43
```

- 5.6.0 supports **3 through 56** (`kOldestSupportedPluginApiVersion = 3`,
  `kCurrentPluginApiVersion = kNotificationActionsPluginApiVersion = 56` in
  `src/scripting/plugin_api.h`). A plugin declaring 57+ is listed but badged
  "incompatible plugin API" and cannot be enabled.
- 43 is `kContainerColorRolesPluginApiVersion`: the level that renamed
  `surface_variant` → `surface_container` and `outline` → `outline_variant` for
  plugin colour arguments. The widgets pass `"surface_container"`,
  `"outline_variant"`, `"on_surface_variant"` to `setColor`/`setGlyphColor`/
  `ui.*` colours, so 43 is the minimum, not a preference.
- 44 (`kPaletteFormat2PluginApiVersion`) is about plugins *writing* palette
  files; the palette this repo ships uses format 2 but is rendered by the Nix
  module, not by a plugin, so 44 is not needed.
- Other levels the plugins rely on: 22 (`require` of `./lib/...`), 24 (argv
  form of `runAsync`), 31 (`getColor`), 32 (container tooltips in `ui.row`),
  35 (`idle.watch`, not used), 42 (`[[panel]].max_height`/content height).
- Levels are cumulative; raise `plugin_api` only when adopting a newer call.

---

## 2. Directory layout and IDs

A source repo holds one directory per plugin, named after the tail of its id:

```
noctalia-plugins/
  deskflow/
    plugin.toml
    widget.luau
    panel.luau
    lib/deskflow.luau
    translations/en.json
  voxtype/
    plugin.toml
    widget.luau
    translations/en.json
  dotfiles-bar/
    plugin.toml
    lib/waybar_json.luau
    {media,screenrec,autoclicker,tailscale,ipad,thermostat,vast,updates}.luau
    {media_panel,tailscale_panel,autoclicker_panel}.luau
    translations/en.json
```

- `id = "john/deskflow"` ⇒ directory `deskflow/`. The directory name must equal
  the part after the slash.
- Full entry id everywhere is `<author>/<plugin>:<entry-id>`, e.g.
  `john/dotfiles-bar:media`.
- The source is wired from `nixos/modules/noctalia.nix` as
  `location = "${../../noctalia-plugins}"`, `kind = "path"`. A path source is
  read-only and has no revisions; the **rebuild** is the update mechanism.
  `noctalia msg plugins update john` does nothing useful for a path source.

---

## 3. Manifest rules

### 3.1 Required top-level fields

```toml
id          = "john/deskflow"   # author/plugin, globally unique
name        = "Deskflow"
version     = "1.0.0"           # MAJOR.MINOR.PATCH, no prerelease/build suffix
plugin_api  = 43                # integer, 3..56 on 5.6.0
author      = "john"
```

Optional: `license` (default `MIT`), `icon`, `description`, `tags`,
`deprecated`, `dependencies`. `dependencies` is metadata only — it does not
install anything. The executables must be on Noctalia's `PATH` (this repo
installs them through `nixos/modules/status-helpers.nix` into the Home Manager
profile, which the systemd unit inherits).

### 3.2 Entry declarations

| Table | Used here | Required keys | Notes |
|---|---|---|---|
| `[[widget]]` | yes | `id`, `entry` | Bar widget; may carry `[[widget.setting]]` and `[widget.actions]`. |
| `[[panel]]` | yes | `id`, `entry` | Popup; opened by `panel-toggle <author/plugin:entry>`. Optional `width`, `height` (`"content"` or px), `max_height`, `placement`, `open_near_click`. |
| `[[service]]`, `[[layer]]`, `[[desktop_widget]]`, `[[shortcut]]`, `[[launcher_provider]]` | no | — | Supported by 5.6.0; not used by these plugins. |

`[widget.actions]` binds a gesture to the IPC vocabulary. It takes precedence
over the Luau callback, so binding a gesture **stops that callback firing**.
Every widget also has a built-in `middle` → "open widget settings" binding; set
`middle = "none"` to reclaim it.

Current action declarations:

| Plugin | Entry | Actions |
|---|---|---|
| `john/deskflow` | `bar` | `left = "panel-toggle john/deskflow:panel"`, `right = "panel-toggle john/deskflow:panel"`, `middle = "none"` |
| `john/dotfiles-bar` | `media` | `middle = "none"`, `back = "exec playerctl --all-players previous"`, `forward = "exec playerctl --all-players next"` |
| `john/dotfiles-bar` | `autoclicker` | `middle = "none"` |
| `john/dotfiles-bar` | `thermostat` | `middle = "none"` |

Thumb buttons (`back`/`forward`) have no Luau callback, hence `exec`.

### 3.3 Settings

Declared with `[[setting]]` at plugin level (shared, edited under Settings →
Plugins) or `[[widget.setting]]` (per widget instance). A declaration needs
`key`, `type` and `label_key` (literal `label` is rejected). Types used:
`int` with `min`/`max`/`step`, `bool`, `string`.

`noctalia.getConfig(key)` takes exactly one argument and returns `nil` for an
undeclared key, with a loud warning. There is no fallback argument, and a typo
is a runtime miss, not a compile error — this is what `noctalia plugins lint`
catches.

Precedence: plugin-level value is the base; a widget-level declaration of the
same key wins for that widget; Settings GUI edits are written to
`~/.local/state/noctalia/settings.toml` and override both until removed.

### 3.4 Translations

`translations/<lang>.json` is a **flat map of dotted keys** (no nesting):

```json
{
  "settings.poll_ms.label": "Poll interval",
  "settings.poll_ms.description": "How often deskflow-ctl is queried, in milliseconds."
}
```

Rules:

- Every `label_key` and `description_key` in the manifest must have a matching
  JSON key in `translations/en.json`; a missing key renders the raw key.
- `noctalia.tr("key")` resolves a string; `noctalia.trp("key", n)` selects
  `.one`/`.other` variants (deskflow uses
  `panel.client_count.one` / `.other` with `{count}`).
- Adding a setting means adding three things together: the `[[…setting]]`
  block, the `label_key`/`description_key` strings, and a `getConfig` call.
  Lint checks the declaration↔read pair; it cannot check the JSON, so keep the
  keys in sync by hand.
- Panel UI strings in `*_panel.luau` are currently literals; only settings and
  voxtype's `tooltip.*`/`notify.*` go through `tr`.

---

## 4. Entry catalogue

### 4.1 `john/deskflow`

| Entry | Kind | File | Callbacks / actions |
|---|---|---|---|
| `bar` | widget | `widget.luau` | one summary pill for the server (`ui.row` + `ui.label` through `barWidget.render`, text `DF` before the first poll); no per-client pills. Left and right = manifest `panel-toggle` (start/stop is the panel's button, or IPC `toggle`); middle (`onMiddleClick`) = re-poll. Settings: `poll_ms` (default 2000, 500–30000). |
| `panel` | panel | `panel.luau` | `onOpen`/`onToggle`/`onRefresh` poll; server start/stop; one row per client — transport pill, name + address, route, RTT, a `ui.graph` of that client's latency history (last two minutes, linear under an adaptive ceiling) and a `min / avg / max` caption with the ceiling. Fed by `deskflow-ctl status` + `deskflow-ctl clients`, and follows the widget's polls through `noctalia.state` (`state.set("deskflow", {summary, clients, error, updated_ms})`). |

Both entries are thin: decoding, the class→role map, the graph series and the
poller live in `lib/deskflow.luau`, required as
`require("./lib/deskflow.luau")` from each entry. `deskflow-ctl clients` prints
the client array `[{name, ip, class, where, rtt, history}]` where `history` is
milliseconds, oldest first, at most 60 samples (one per 2 s poll). `poll_ms` is
read in `widget.luau` only, because a widget-level setting is in scope only in
the entry that declares it.

`deskflow-ctl` and the widget are installed only on `arch`/`office`
(`status-helpers.nix:611-614`); on other hosts the entry would poll a missing
binary.

### 4.2 `john/voxtype`

| Entry | Kind | File | Behaviour |
|---|---|---|---|
| `bar` | widget | `widget.luau` | Streams `voxtype status --follow --format json` via `runStream`. States: `idle`, `recording`, `transcribing`, `stopped`, `error`, `unknown`. Left: start the daemon if stopped, probe if unknown, else `voxtype record toggle`. Right: session-only toggle of "hide when idle" (does not persist). Settings: `hide_when_idle` (false), `show_label` (true). |

Stream resilience: a dead stream is restarted from `update()` with a 15 s
backoff; a live stream is silent while nothing changes, so after 5 minutes
without a line the widget reconciles with a one-shot
`voxtype status --format json`. `update()` runs every 5 s.

### 4.3 `john/dotfiles-bar`

Eight widgets and three panels, all thin adapters over a helper binary that
already prints Waybar JSON.

| Entry | Kind | Helper / stream | Left | Right | Middle | Scroll |
|---|---|---|---|---|---|---|
| `media` | widget | `media-player status` (poll) | `media-player toggle` | open `media-panel` | `media-player focus` | vertical → volume ±5% |
| `screenrec` | widget | `screenrec status --follow` (stream) | `screenrec toggle` | `screenrec last` | — | — |
| `autoclicker` | widget | `autoclicker watch` (stream) | `autoclicker toggle` | open `autoclicker-panel` | `autoclicker cycle` | — |
| `tailscale` | widget | `tailscale-status` (poll) | open `tailscale-panel` | `tailscale-exit-node` | — | — |
| `ipad` | widget | `ipad-display status --waybar` (poll) | `ipad-display recover` | `ipad-display create` | — | — |
| `thermostat` | widget | `hass-thermostat-status` (poll) | — (no click) | `hass-macro ac-toggle` | `hass-macro thermostat-toggle` | vertical → setpoint up/down |
| `vast` | widget | `vast-waybar-status` (poll) | clear cache + re-poll | — | — | — |
| `updates` | widget | `nix-update-status` (poll) | `nix flake update` in a terminal | — | — | — |
| `media-panel` | panel | `media-picker-data players\|tabs` | per-player play/pause, pin, volume; per-tab mute/volume/focus | — | — | — |
| `tailscale-panel` | panel | `tailscale-panel-data` (fallback `tailscale status --json`) | connect toggle, peer list, exit-node picker | — | — | — |
| `autoclicker-panel` | panel | `autoclicker get/status` | mode, interval, button, target, live summary | — | — | — |

Plugin-level settings (all `int` milliseconds, plus `terminal` string):
`media_interval` 2000, `tailscale_interval` 20000, `ipad_interval` 5000,
`thermostat_interval` 30000, `vast_interval` 60000,
`updates_interval` 3600000, `terminal` `""`.

Panels have no settings. `media-panel`, `tailscale-panel` and
`autoclicker-panel` declare `width`, `height = "content"`, `max_height = 680`,
`placement = "attached"`, `open_near_click = true`; the deskflow panel is
`width = 420`, `height = "content"`, `max_height = 560` (centred, not attached).

---

## 5. `lib/waybar_json.luau`

Every `dotfiles-bar` widget starts with:

```lua
local status = require("./lib/waybar_json.luau")
```

`require` is API 22+: the argument must start with `./` or `../`, end in
`.luau`; each entry has its own module cache.

Entry chunks resolve against the **plugin root** (`m_pluginDir`), not the
entry file's own directory — that is why every entry file lives at the plugin
root and requires `./lib/…`. Required modules resolve against their own
directory. `noctalia plugins lint` resolves from the calling file instead and
silently skips unresolvable paths, so a wrong require lints clean and only
fails at runtime; see `research/plugins.md`.

The contract it encodes:

- **Helpers are unchanged.** `status-helpers.nix` still prints
  `{"text":…,"class":…,"tooltip":…}` (plus an optional `"alt"`). The module is
  the adaptor, not a reimplementation.
- `M.parse(stdout)` — scans lines, keeps the last line starting with `{`, and
  returns `{text, class, tooltip, alt}` or `nil` for empty/non-JSON output. A
  diagnostic printed before the object is ignored; a half-written line is
  skipped. Empty stdout is how several helpers say "hide me".
- `M.colorForClass(class, map, fallback)` — splits the class string on
  whitespace and lets the **last matching token win**. This reproduces the old
  CSS cascade for composite classes (`ipad-display` emits `"usb streaming"`:
  `usb` is weight, `streaming` is colour).
- `M.applyImperative(data, colorMap, fallback, hideEmpty)` — pushes the parsed
  value through `barWidget.setVisible/setText/setTooltip/setColor/
  setGlyphColor`. `hideEmpty` is either `true` (hide when text is empty) or
  `{classes = {...}, empty = true}` for widgets whose resting state is a real
  object with empty text (`screenrec`'s `class = "idle"`). When `data` is `nil`
  and the widget is not meant to hide, the previous reading stays on the bar
  instead of flickering.

Colour maps map old CSS classes to palette roles, not hex values. Examples:
`playing → tertiary`, `paused → secondary`, `stopped → on_surface_variant`,
`recording → error`, `vast-tunnel-up → secondary`, `disconnected → error`.
If a helper starts emitting a new class, add it to the widget's `COLORS` table;
an unknown class falls back rather than erroring.

Do not use `barWidget.setText` and `barWidget.render` in the same widget:
`render` supersedes `setText`/`setGlyph`/`setImage` (this is why deskflow is
the only composited widget).

---

## 6. IPC hooks

### 6.1 Command form

```
noctalia msg plugin <author/plugin:entry> <target> <event> [payload]
```

- `target`: `focused`, a connector (`DP-1`), `connector:bar-name`
  (`focused:default`), or `all`. Singleton entries (panels, services) require
  `all`.
- `event` and everything after it are passed to `onIpc(event, payload)`.
- The socket is `${XDG_RUNTIME_DIR}/noctalia-${WAYLAND_DISPLAY}.sock`; a caller
  without the session environment gets `error: noctalia is not running`.

### 6.2 Events implemented

| Entry | Events |
|---|---|
| `john/deskflow:bar` | `refresh` (re-poll), `toggle` (server start/stop) |
| `john/deskflow:panel` | `refresh`, `toggle` |
| `john/voxtype:bar` | `refresh` (one-shot status probe; the stream keeps running) |
| `john/dotfiles-bar:media` | `refresh` |
| `john/dotfiles-bar:screenrec` | `refresh` (re-applies the last stream object; the stream owns state) |
| `john/dotfiles-bar:autoclicker` | `refresh` (re-applies last object) |
| `john/dotfiles-bar:tailscale` | `refresh` |
| `john/dotfiles-bar:ipad` | `refresh` |
| `john/dotfiles-bar:thermostat` | `refresh` |
| `john/dotfiles-bar:vast` | `refresh` |
| `john/dotfiles-bar:updates` | `refresh` |
| `john/dotfiles-bar:{media,tailscale,autoclicker}-panel` | `refresh` |

The exact commands, all using the `all` target so a per-output bar cannot be
missed:

```
noctalia msg plugin john/deskflow:bar all refresh
noctalia msg plugin john/deskflow:bar all toggle
noctalia msg plugin john/deskflow:panel all refresh
noctalia msg plugin john/deskflow:panel all toggle
noctalia msg plugin john/voxtype:bar all refresh
noctalia msg plugin john/dotfiles-bar:media all refresh
noctalia msg plugin john/dotfiles-bar:screenrec all refresh
noctalia msg plugin john/dotfiles-bar:autoclicker all refresh
noctalia msg plugin john/dotfiles-bar:tailscale all refresh
noctalia msg plugin john/dotfiles-bar:ipad all refresh
noctalia msg plugin john/dotfiles-bar:thermostat all refresh
noctalia msg plugin john/dotfiles-bar:vast all refresh
noctalia msg plugin john/dotfiles-bar:updates all refresh
noctalia msg plugin john/dotfiles-bar:media-panel all refresh
noctalia msg plugin john/dotfiles-bar:tailscale-panel all refresh
noctalia msg plugin john/dotfiles-bar:autoclicker-panel all refresh
```

Panels are also opened with the plain panel verb, not a plugin event:

```
noctalia msg panel-toggle john/deskflow:panel
noctalia msg panel-toggle john/dotfiles-bar:media-panel
noctalia msg panel-toggle john/dotfiles-bar:tailscale-panel
noctalia msg panel-toggle john/dotfiles-bar:autoclicker-panel
```

### 6.3 Signal replacement

Waybar re-ran a module on a real-time signal; Noctalia plugins only re-read when
told. The mapping:

| Old | New |
|---|---|
| `pkill -RTMIN+8 waybar` (thermostat; `nixos/modules/keybind.nix:21-22`) | `noctalia msg plugin john/dotfiles-bar:thermostat all refresh` |
| `refresh 9` (vast; `waybar.nix:12-20`) | `noctalia msg plugin john/dotfiles-bar:vast all refresh` |
| `kill -46` / `refresh 12` (media; Eww pin + `media-player`) | `noctalia msg plugin john/dotfiles-bar:media all refresh` |
| `refresh 14` (tailscale; `tailscale-status`, `tailscale-exit-node`) | `noctalia msg plugin john/dotfiles-bar:tailscale all refresh` **and** `…:tailscale-panel all refresh` |

Everything is best-effort: the helpers append
`>/dev/null 2>&1 || true`, so a stopped shell degrades to "no refresh" rather
than a failing command. `status-helpers.nix:28` centralises this as
`refreshPlugin`.

There is no outbound IPC API from a plugin. Use `noctalia.togglePanel(...)`
in-process (the widgets do) rather than shelling out to `noctalia msg`.

---

## 7. Persistence and shared state

- `/tmp/media-player-selected` and `/tmp/media-player-active` are the
  cross-process media pin/active-player files. They are also read by
  `media-player` and written by `media-picker-action`, so the panel and bar
  agree. They are world-writable `/tmp` files by design (legacy contract); a
  stale pin is dropped when the player disappears.
- `/tmp/vast-waybar-status.json` is the 55 s VAST cache; the widget deletes it
  on click.
- `noctalia.state` is the in-memory per-plugin channel. Deskflow uses it to
  push snapshots from the widget to the panel: the widget publishes
  `{summary, clients, error, updated_ms}` under key `deskflow` after every poll
  and the panel (`state.watch`, `applySnapshot`) only takes a snapshot newer
  than the one it polled itself. It is cleared when the plugin stops, so the
  panel polls on open.
- Anything durable must go to `noctalia.pluginDataDir()` (owner-only, survives
  updates). None of these plugins currently persist anything.

---

## 8. Linting and validation

### 8.1 Plugin lint (offline, no shell needed)

```
noctalia plugins lint noctalia-plugins
```

- Accepts one path: a plugin directory or a directory of plugins; defaults to
  `.`. Exits 1 if any error-level finding exists.
- Checks: settings read with `getConfig` but not declared in `plugin.toml`
  (runtime loud miss), obsolete entry-specific `getConfig` aliases, settings
  declared but never read (warning), and `entry = "…luau"` files that do not
  exist.
- It does not parse Luau deeply and cannot validate translation JSON, palette
  roles or runtime behaviour.

Without a local `noctalia` binary:

```
nix shell nixpkgs#noctalia -c noctalia plugins lint noctalia-plugins
```

Run it after any manifest or script change. A missing entry file is the most
common breakage after renaming a widget.

### 8.2 Config validation

```
noctalia config validate                       # default config path
noctalia config validate ~/.config/noctalia/config.toml
```

Validates the merged TOML against the 5.6.0 schema and prints legacy-key
normalisations with file/line/column. The module already sets
`programs.noctalia.checkConfig = true`, so `nixos-rebuild build` runs this
against the generated file and fails on an unknown key; the manual command is
for the live file:

```
nix shell nixpkgs#noctalia -c noctalia config validate ~/.config/noctalia/config.toml
```

`settings.toml` is the app-owned override layer: it can mask a declarative key
during a live check. Validate the Home Manager output (the file the module
writes) when debugging a build, and the live file when debugging runtime
behaviour.

Useful runtime checks:

```
noctalia msg status                 # JSON: barVisible, panelOpen, activePanelId, locked
noctalia msg plugins list           # installed/enabled/incompatible API badges
noctalia msg plugin john/dotfiles-bar:media all refresh
journalctl --user -u noctalia -f    # plugin load errors and getConfig warnings
```

### 8.3 Development loop

1. Edit a `.luau` file → saved scripts hot-reload on the next config reload;
   run `noctalia msg config-reload` or change any setting in Settings.
2. Manifest changes (`plugin.toml`) need a config reload, not a shell restart.
3. Enable once with `noctalia msg plugins enable john/dotfiles-bar`; the
   `[plugins].enabled` array in `nixos/modules/noctalia.nix` is the declarative
   form and a GUI/CLI enable writes `settings.toml`, which would then shadow it.
   The module sets `auto_update = "none"` and a single `path` source named
   `dotfiles`, so there is nothing to pull.
4. `noctalia msg plugins disable <id>` keeps code and settings.

---

## 9. Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Widget does nothing on middle click | built-in `middle` = open settings shadows `onMiddleClick` | add `middle = "none"` to `[widget.actions]` |
| `getConfig` returns `nil` + warning | key not declared, or declared at plugin level while read as widget-level (or typo) | declare it in the right table; run `noctalia plugins lint` |
| `noctalia plugins lint` reports `reads undeclared setting` for a shared `lib/` module | the linter attributes `noctalia.getConfig` to the file it is written in, and a widget-level setting is only in scope in that widget's entry file | read the setting in the entry file and pass the value into the lib (deskflow does this: `deskflow.clampPollMs(noctalia.getConfig("poll_ms"))`) |
| Widget never updates after a helper action | no `refresh` IPC sent | add `refreshPlugin "<entry>"` to the helper |
| Tooltip shows raw `<span>` text | Noctalia tooltips are plain text | strip markup in the helper |
| Widget shows the empty capsule | `hideEmpty` not passed / resting class not listed | pass `true` or `{classes={"idle"}, empty=true}` |
| Plugin badged incompatible | `plugin_api` > 56 | lower the level; check `plugin_api.h` for the capability's level |
| Panel does not open from `noctalia msg` | panel target must be `all` | `… panel-toggle john/dotfiles-bar:media-panel`, or `plugin … all toggle` |
| Settings edited in GUI revert after rebuild | GUI wrote `settings.toml` | delete the key from `~/.local/state/noctalia/settings.toml` |
| Plugin missing after rebuild | source `location` path wrong, or id not in `[plugins].enabled` | check `noctalia msg plugins list` and the store path in `noctalia.nix` |
| Same helper process appears once per monitor | bar widgets are instantiated **per output** (`src/shell/bar/bar.cpp` iterates `m_platform->outputs()`), so a widget that spawns a streaming child (`status --follow`, `watch`) runs one child per output | expected, not a leak: keep such children cheap and event-driven. Measured with 2 outputs from `voxtype`, `screenrec` and `autoclicker`: 0 s CPU over 37 min, ~35 MB RSS total, blocked on futex/socket reads. Only add refcounting/shared state if a child becomes expensive. Verify with `pgrep -cP $(systemctl --user show -p MainPID --value noctalia.service)` |
