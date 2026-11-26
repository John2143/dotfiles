# Noctalia v5.6.0 — Plugin API

Research target: Noctalia **v5.6.0** (docs version selector "v5.6.0 (Latest)"). All page citations use the
version-pinned docs prefix `https://docs.noctalia.dev/noctalia/v5.6.0/...`. Content was read from the pages under
that prefix, and the unversioned ("main / rolling") pages were used only to cross-check wording; where the two differ
the difference is called out. Date of research: 2026-11-25.

## Summary

A Noctalia plugin is a directory containing a static `plugin.toml` manifest plus one or more **Luau** entry scripts.
There is no QML, C++, JS or plain-Lua plugin path — the only scripting runtime is Luau (Luau is Lua 5.1-derived, but
the docs are explicit that it is Luau and the scripts use Luau syntax such as `+=` and string interpolation). Each
entry runs in its **own isolated Luau VM inside the shell process, off the UI thread**, with per-call time budgets.
Plugins are "trusted code": installing one is equivalent to running a user-owned script, and the filesystem helpers
are explicitly *not* sandboxed.

An entry can be one of exactly seven declaration kinds in the manifest: bar widget (`[[widget]]`), control-center
shortcut tile (`[[shortcut]]`), launcher provider (`[[launcher_provider]]`), desktop widget (`[[desktop_widget]]`),
panel (`[[panel]]`), layer-shell surface (`[[layer]]`), and headless background service (`[[service]]`). There is no
"keybind action", "notification filter", or "template" entry kind.

Compatibility is gated by a mandatory integer `plugin_api` in the manifest. **Noctalia v5.6.0 supports plugin API
levels 3 through 56** (the rolling docs say 3–59, which is *not* true for 5.6.0 — see Gaps).

## Findings

### 1. Manifest schema and required fields

Manifest file is `plugin.toml`, static (read at load/config reload, not hot-reloaded like scripts).

Required: `id`, `name`, `version`, `plugin_api`. "A manifest without any of them is rejected."
- `id` = `"<author>/<plugin>"`, globally unique, and the subdirectory name in a source repo must equal the part after
  the `/`.
- `version` must be exactly `MAJOR.MINOR.PATCH`, non-negative decimals, no leading zeros, **no prerelease or build
  suffixes**.

Optional top-level keys: `author`, `license` (defaults `"MIT"`), `deprecated` (bool, default `false`; soft marker only),
`icon`, `description`, `tags` (catalog search), `dependencies` (external tools the *user* must install; metadata only,
does not block enabling, and is not installed from the manifest — the Home Manager module's `extraPackages` is how
executables get onto Noctalia's `PATH`).

Verbatim example of the documented minimal manifest and widget entry
(`/noctalia/v5.6.0/plugins/development/`, "Minimal widget"):

```toml
id         = "me/hello"
name       = "Hello"
version    = "1.0.0"
plugin_api = 3
author     = "me"

[[widget]]
id    = "hello"
entry = "widget.luau"
```

Source: https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/ and
https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/manifest/

Entry declaration: every entry needs `id` (unique within the plugin) and `entry` (the `.luau` file), optionally a
settings schema. Full entry id used everywhere else is `<author>/<plugin>:<entry-id>`, e.g. `me/hello:hello`.

Layer entries have their own required/optional keys: `layer` (`background|bottom|top|overlay`, default `top`),
`anchors` (subset of top/bottom/left/right, default centered), `width`, `height`, `margins`, `exclusive_zone`
(int ≥ -1 or `"auto"`, default `0`), `keyboard` (`none|on_demand|exclusive`, default `none`), `click_through`
(default `false`), `output` (`all|focused|<connector>`, default `all`), `visible` (default `false`). Invalid values
fail with `layer entry '<id>': <message>`. Layers do **not** support entry-level settings (`[[layer.setting]]` is
not allowed).

### 2. Supported languages / runtime

Luau only. Docs: "all driven by trusted [Luau](https://luau.org) scripts running in isolated VMs", and "Each entry
runs in its own isolated Luau VM, off the UI thread, with per-call time budgets - a slow or crashing script never
stalls the shell."

Practical notes that follow from this:
- Optional relative module imports, `plugin_api = 22`: `require("./lib/format.luau")`; argument must start with `./`
  or `../` and end in `.luau`; lexical resolution relative to the calling file; per-entry module cache; circular
  imports fail with the import chain.
- The official repo ships a `noctalia.d.luau` luau-lsp definition file and `.luaurc` with `languageMode =
  nonstrict`; every plugin file starts with `--!nonstrict`.
- Translations are `translations/<lang>.json` with flattened dotted keys; `noctalia.tr` / `noctalia.trp`.

There is no QML, C++, JS, or stock-Lua entry type anywhere in the docs; nothing in the manifest schema or runtime API
suggests one.

### 3. Every entry type a plugin can contribute

From the manifest docs table "The supported entry kinds" (`/noctalia/v5.6.0/plugins/development/manifest/`):

| Table                    | Kind                      | What it does at runtime                                                              |
| ------------------------ | ------------------------- | ------------------------------------------------------------------------------------ |
| `[[widget]]`             | Bar widget                | Placed on a bar; ticks, handles clicks/scroll and IPC                                |
| `[[shortcut]]`           | Control-center tile       | Toggle tile added from control-center shortcut settings                              |
| `[[launcher_provider]]`  | Launcher provider         | Answers launcher queries behind a `prefix`, results via `launcher.setResults`        |
| `[[desktop_widget]]`     | Desktop widget            | Tile on the desktop; declares its UI as a `ui.*` tree                                |
| `[[panel]]`              | Panel                     | Pop-up surface; `ui.*` tree, opened by id (`noctalia msg panel-toggle <id>`)         |
| `[[layer]]`              | Layer surface             | Plugin-owned layer-shell surface; shown/hidden by local entry id                     |
| `[[service]]`            | Headless service          | Background loop, no UI; feeds the plugin's other entries over `noctalia.state`       |

Explicitly **not** entry kinds, and how the capability is actually reached in 5.6.0:

- **OSD**: not an entry. Runtime call `noctalia.osd.show(icon, value?, opts?)`, `plugin_api = 39` (same OSD slot as
  built-in popups; users can disable them with `[osd.kinds].custom = false`).
- **Template** (terminal/editor/browser theme templates): not a plugin extension point. Templates are config-dir
  files handled by the theming/template documentation, which has no plugin section.
- **Notification filter**: not a plugin extension point. Filtering is user config —
  `[notification.filter.<name>]` with `match_content`, `show_toast`, save-to-history flags — documented on the
  Notifications service page; that page shows filtering a *plugin's* toast (Audio Switcher) from config, not the
  plugin registering a filter.
- **Keybind action**: keybinds are compositor-side commands. A plugin is reachable from a keybind only by running
  `noctalia msg panel-toggle <author>/<plugin>:<entry>` or `noctalia msg plugin <author>/<plugin>:<entry> <target>
  <event> [payload]` in the compositor bind. There is no manifest key for keybinds.

Widget gesture defaults (`[widget.actions]`, `plugin_api = 14`) deserve separate mention because they change click
semantics: a declared binding takes precedence over the script, so binding `right` stops `onRightClick` firing. Every
widget gets a built-in `middle` binding that opens its settings, so `onMiddleClick` does not fire unless the manifest
or user config sets `middle = "none"` (screen_recorder does exactly this to free middle-click for "save replay").

### 4. Installation: local directory vs git source

Sources are configured under `[[plugins.source]]` in `config.toml`:

```toml
[plugins]
enabled = ["noctalia/screen_recorder"]
auto_update = "all" # "all" | "official" | "none"

[[plugins.source]]
name     = "official"
kind     = "git"
location = "https://github.com/noctalia-dev/official-plugins"
enabled  = true

[[plugins.source]]
name     = "my-dev"
kind     = "path"
location = "~/dev/my-plugins"
enabled  = true
```

- Two git sources ship by default: `official` (`https://github.com/noctalia-dev/official-plugins`) and `community`
  (`https://github.com/noctalia-dev/community-plugins`). Both can be toggled but are protected from removal; custom
  sources are removable.
- **Hand-placed local plugins**: a plugin dropped in `~/.local/share/noctalia/plugins/<plugin>/`
  (i.e. `$XDG_DATA_HOME/noctalia/plugins/<plugin>/`) is discovered as a built-in **`local`** source. This is the
  recommended dev loop; like every plugin it must still be *enabled* before it activates.
- **`path` sources** are read directly, treated as immutable/read-only (no git operations).
- **Git sources** are cloned into an app-managed cache under `$XDG_STATE_HOME/noctalia/`; enabling one *exports only
  that plugin's directory* into `$XDG_STATE_HOME/noctalia/plugins/materialized/`. Those exported files are a runtime
  cache, not editable plugin state — which is why persistent data must go to `noctalia.pluginDataDir()`, never
  `noctalia.pluginDir()`.
- Source `name` is identity: duplicate names are a config error; reusing a name with a different `location` deletes
  the old cache/export and re-fetches.
- `auto_update`: `"all"` (default, on startup and every 6 hours), `"official"`, `"none"`. The boolean form from
  earlier builds is rejected.
- Enable/disable is separate from installed: `noctalia msg plugins enable|disable <author/plugin>`; disabling keeps
  code and settings. A GUI toggle writes an app-owned `[plugins].enabled` override into `settings.toml`, which then
  wins over `config.toml` until removed.

Nix/home-manager path (relevant to this dotfiles migration): pin the plugin repo as a non-flake input and use it as a
`path` source, since an explicit `plugins.source` list **replaces** the defaults:

```nix
inputs.noctalia-plugins = {
  url = "github:noctalia-dev/official-plugins";
  flake = false;
};
# programs.noctalia.settings.plugins.source = [ { name = "official"; kind = "path";
#   location = "${inputs.noctalia-plugins}"; enabled = true; } ];
```

### 5. Plugin settings: declaration and consumption

Two (three, counting panels) scopes, same field schema:

- `[[setting]]` at manifest root → **plugin-level**, one shared set, edited via Settings → Plugins gear, seeded into
  *every* entry (widget, shortcut, panel, service). Use for config a service or panel needs.
- `[[widget.setting]]` → widget-entry settings, edited with that bar widget instance. Also used to store per-instance
  presentation tweaks; "not a second enabled plugin instance".
- `[[panel.setting]]` → panel-entry settings, edited under Settings → Plugins.
- If both plugin-level and widget-level declare the same key, the widget entry value wins for that widget.

Field schema: `key` (required), `type` (required; one of `string`, `string_list`, `string_map`, `bool`, `int`,
`double`, `select`, `file`, `folder`, `glyph`, `color`), `label_key` (required — literal `label`/`description` fields
are rejected), `description_key`, `default`, `min`/`max` (int/double), `step`, `options` (select, `{value,label_key}`),
`extensions` (file), `visible_when` (`{key=..., values=[...]}`), `advanced`, `secret` (API 47; only for
`string`/`string_list`/`string_map`). `string_map` requires API 6 and arrives as an associative Luau table.

Consumption: `noctalia.getConfig(key)` — single argument, no fallback; **undeclared keys log a loud warning and
return `nil`** ("no silent fallbacks").

User-side config paths:
- plugin-level: `[plugin_settings."noctalia/screen_recorder"] frame_rate = 30`
- widget instance: `[widget.<name>]` with `type = "<author>/<plugin>:<entry>"`, plus per-key subtables for
  `string_map` values (e.g. `[widget.display-output.output_glyphs] "eDP-1" = "laptop"`).

Precedence: values edited in Settings are written to `settings.toml` and override `config.toml` until removed. This
matters for a declarative dotfiles setup: GUI edits silently win over the Nix-provided TOML.

Settings-change delivery differs per entry kind: widgets/desktop widgets/panels are rebuilt, services keep state and
get `onConfigChanged()` (or, if they define none, the service runtime is restarted and the top-level chunk re-runs).
`noctalia.state` survives a service restart, so caches keyed on config must be invalidated by hand.

### 6. plugin_api compatibility rules

- Mandatory positive integer; "the oldest Noctalia plugin API level that the plugin requires, independent of both the
  plugin's version and Noctalia's release version."
- Levels are cumulative; leave the level alone until you adopt a newer capability.
- **v5.6.0 supports 3–56.** Out-of-range plugins are listed but badged "incompatible plugin API" and cannot be
  enabled.
- Update safety: if an enabled plugin's new revision targets an unsupported API level, Noctalia keeps that plugin's
  previous exported copy, still updates compatible plugins from the same source, and advances the catalog; the held
  plugin catches up after the shell upgrades.
- Capability levels most relevant to a migration: 3 base, 12 `systemStats`/`nowMs`, 14 widget action defaults, 17
  service start-on-enable + `onExit` reasons, 22 `require`, 24 argv-form `runAsync`, 26 `getSetting`, 31 `getColor`,
  35 `idle.watch`, 36 `[[layer]]`, 37 `calendarEvents`, 38 drag/drop in bar widgets, 39 `osd.show`, 43 new container
  color roles (`surface_container`, `outline_variant`; `surface_variant`/`outline` retired), 44 palette JSON format 2,
  46 explicit `setGpuMonitoring`, 47 `secret`, 48 `onSuspend`/`onResume`, 51 `mediaPlayer`, 53 `nightlight`, 54
  `compositor.*`, 55 `ui.ring`, 56 notification action buttons + `openPath`/`revealPath`.
  Levels 57–59 (key-repeat `onKey`, `nightlight.setTemperature`, `outputs().pixelWidth/pixelHeight/scaleFactor`) are
  "Unreleased" — not usable on 5.6.0.

### 7. Palette, IPC and config access from a plugin

**Palette read**: `noctalia.getColor(role)` returns the active palette's `#RRGGBB` for a role name (`plugin_api = 31`);
`nil` for unknown roles. For painting there is a richer color value accepted wherever a `UiColor`/`barWidget` color is
expected: a palette role (`"primary"`, `"on_surface"`), a role with alpha (`"primary/0.6"`, resolved live against the
palette), or a literal hex (`#rrggbb` / `#rrggbbaa`). `barWidget.setColor(role_or_hex[, mode])` and
`setGlyphColor(...)` follow the same rule; the default mode keeps the widget's configured `color`/`icon_color` when
you pass `"on_surface"`, and `mode = "script"` makes `"on_surface"` literal.
`noctalia.isDarkMode()` tracks `[theme].shell_mode` when pinned.

**Palette write**: there is no palette API. A plugin that wants to change colors would have to write palette files
(the `palette_api = 44` row explicitly discusses "Plugins that write palette files in format 2" — i.e. writing JSON
under `~/.config/noctalia/palettes/`, `[theme] source = "custom"`, `custom_palette = "<name>"`) and the user selects
it. Reading `custom_palette` is possible via `noctalia.getSetting("theme.custom_palette")` (API 26). Treat
"plugins can write palette files" as *inferred from that single doc sentence plus the file-location docs*; no API
function sets the active palette.

**Shell config read**: `noctalia.getSetting(path)` (API 26) reads any effective shell config by TOML dotted path;
tables/arrays become Luau tables with **zero-based** array indices (`"bar.order[0]"`). Paths the entry actually read
are watched: a change calls `onConfigChanged()`, or reloads the script if none is defined.

**Config write**: none. Plugins "read config but cannot write it"; the supported affordance is
`noctalia.openSettings()` (API 15), which opens the settings window at the calling plugin's own page.

**IPC inbound**: `onIpc(event, payload)` on any entry kind, triggered by
`noctalia msg plugin <author/plugin:entry> <target[:bar-name]> <event> [payload]`. Targets: `focused`, a connector
(`DP-1`), `connector:bar-name` (`focused:default`), or `all` (required for singleton entries such as `[[service]]`
and `[[panel]]`). Everything after `<event>` is passed through verbatim as payload.

**IPC outbound**: there is *no* function to emit a Noctalia IPC command. Docs explicitly prefer the in-process API
over shelling out ("Prefer [setWallpaper/togglePanel] over shelling out to the `noctalia` CLI from a plugin; the API
path runs in-process and avoids an IPC round trip"). Where no API exists, the documented escape hatch is
`noctalia.runAsync({ "noctalia", "msg", ... })`, or `noctalia.runInTerminal(cmd)`.

### 8. Shell commands and periodic updates

Shell commands, all returning a boolean "accepted":
- `noctalia.runAsync(cmdOrArgv)` — detached, no output. String form runs through `/bin/sh -c`; argv form (API 24)
  executes directly with no shell parsing — the docs say to use argv whenever settings, user input, paths or URLs are
  involved.
- `noctalia.runAsync(cmdOrArgv, cb)` — captures output; `cb(result)` with
  `{exitCode, stdout, stderr, timedOut, stdoutTruncated, stderrTruncated}`.
- `noctalia.runStream(cmd, onLine)` — long-lived process, one callback per stdout line; killed on reload/removal.
- `noctalia.runInTerminal(cmd)`, `noctalia.commandExists(name)`, `noctalia.processMatches(cb, ...needles)`,
  `noctalia.getenv(name)`.
- No sandbox: "Plugins are trusted code, so these helpers are not sandboxed" (filesystem section), and `../` can
  leave the plugin directory.

Periodic bar-widget updates: define `update()` and call `noctalia.setUpdateInterval(ms)` — that sets *this entry's*
`update()` cadence, clamped to ≥ 16 ms. There is no frame-tick API in the bar (`onFrameTick` exists only for desktop
widgets/panels/layers after `setNeedsFrameTick(true)`; desktop widgets additionally have `setWantsSecondTicks`).
Widgets can also be pushed from a `[[service]]` through `noctalia.state.set` / `state.watch`, which is the pattern
the official `example` plugin uses (service ticks at 1 s; the widget re-renders on each watched value).

### 9. Resource model

- In-shell, in-process: one **isolated Luau VM per entry**, off the UI thread, per-call time budgets. Entries do not
  share Lua memory; they exchange plain values (strings, numbers, booleans, tables thereof) via the per-plugin
  `noctalia.state` channel. No separate helper process is implied for ordinary entries.
- `[[service]]` is a singleton (no output); `[[layer]]` gets one surface *and one runtime per output* while shown, and
  hiding destroys both (state does not survive a hide).
- `noctalia.state` is in-memory and cleared when the plugin stops; `noctalia.pluginDataDir()` is the durable,
  owner-only (`0700`), per-plugin directory that survives updates and honors `NOCTALIA_STATE_HOME`.
- Concurrency limits documented: at most 8 idle watches and 8 nightlight watches per entry runtime, at most 4
  compositor subscriptions per entry, at most 4 outstanding `readFileAsync` (4 MiB each), at most 8 pending sound
  loads, at most 16 pending Umbriel callbacks, one color-picker callback pending.
- `ui.pixelStream` (API 40) is the one documented path to a *companion process* streaming frames over a shared-memory
  socket — relevant if a plugin needs foreign-rendered pixels.

### 10. Minimal bar-widget skeleton

Verbatim from `/noctalia/v5.6.0/plugins/development/` ("Minimal widget"):

```
id         = "me/hello"
name       = "Hello"
version    = "1.0.0"
plugin_api = 3
author     = "me"

[[widget]]
id    = "hello"
entry = "widget.luau"
```

```lua
function update()
  noctalia.setUpdateInterval(1000)
  barWidget.setGlyph("puzzle")
  barWidget.setText("Hello")
end

function onClick()
  noctalia.notify("Hello", "you clicked me")
end
```

Adding a declared setting and consuming it (manifest then script), from the manifest page:

```toml
[[widget]]
id    = "hello"
entry = "widget.luau"

  [[widget.setting]]
  key       = "label"
  type      = "string"
  label_key = "settings.label.label"
  default   = "Hello"
```

```lua
local label = noctalia.getConfig("label")
barWidget.setText(label)
```

Used from config:

```toml
[widget.my_widget]
type = "<author>/<plugin>:<entry>"   # e.g. "noctalia/screen_recorder:recorder"
```

Declarative alternative (composite content): `barWidget.render(ui.row({...}, {...}))` — bar-specific constraints are
that the capsule clips to bar thickness (keep the tree one control tall, branch on `barWidget.isVertical()`), there
is no keyboard focus (so `ui.input`/`ui.select`/`ui.scroll` are skipped with a warning), and once `render()` is used
`setText`/`setGlyph`/`setImage` have no visible effect.

### 11. Two (three) real example plugins

**`noctalia/example`** — https://github.com/noctalia-dev/official-plugins/tree/main/example
Reference plugin exercising every entry kind; `plugin_api = 43`, `version = "1.4.1"`. Directory:

```
example/
  plugin.toml          # 2 [[widget]], 1 [[service]], 1 [[shortcut]],
                       # 1 [[launcher_provider]], 2 [[panel]], 1 [[layer]]
  hello.luau           # imperative widget: setGlyph/setText/setTooltip + getConfig + onIpc
  declarative.luau     # same service tick rendered via barWidget.render(ui.*)
  ticker.luau          # service: setUpdateInterval(1000), state.set("tick", n), drives the layer
  shortcut.luau        # control-center tile: setLabel/setIcon/setActive
  finder.luau          # launcher provider, prefix "ex", launcher.setQuery() drill-in
  panel.luau, dnd.luau # panels: interactive controls; drag-and-drop reference
  banner.luau          # [[layer]] top banner, exclusive_zone = "auto"
  data.txt, translations/en.json, thumbnail.webp, README.md
```

It documents its own IPC entry points in comments, e.g.
`noctalia msg plugin noctalia/example:hello focused set "Hi there"` and
`noctalia msg plugin noctalia/example:ticker all layer-toggle`. `hello.luau` shows the canonical
`noctalia.state.watch("tick", fn)` → re-render wiring; `ticker.luau` shows `noctalia.idle.watch(5, fn)` and
`noctalia.layer.show/hide/configure`.

**`noctalia/screen_recorder`** — https://github.com/noctalia-dev/official-plugins/tree/main/screen_recorder
`plugin_api = 56`, `version = "1.6.0"`, `dependencies = ["gpu-screen-recorder", "slurp"]`, icon `video`. Directory:
`plugin.toml` (10 KB — all settings are plugin-level `[[setting]]`), `recorder_service.luau` (31 KB, the whole
recording state machine), `recorder.luau` (bar widget, thin client), `shortcut.luau`, `region_overlay.luau`
(`[[layer]]`, full-output, `click_through = true`, `keyboard = "none"`), `translations/en.json`, `thumbnail.webp`.
Architecture worth copying: the singleton service owns state and the subprocess; the widget and shortcut mirror it
over `noctalia.state` and drive it via IPC (`plugin noctalia/screen_recorder:service all start|stop|toggle|replay-*`).
Manifest also sets `[widget.actions] middle = "none"` to reclaim middle-click. Plugin-level settings include `select`
(`video_source` with `options`), `bool`, `folder` (`~/Videos/Recordings`), `string` (`filename_pattern`), and `int`
with `min`/`max` (`frame_rate`, 1–240) — a good map of the settings types in real use.

**`noctalia/world_clock`** — https://github.com/noctalia-dev/official-plugins/tree/main/world_clock
`plugin_api = 43`. `bar.luau` is the best short example of a widget that re-renders from shell state: it reads
`noctalia.state.get("world_clock.zones")`, branches on `barWidget.isVertical()`, calls
`barWidget.render(...)`/`ui.label`, opens the panel with `noctalia.togglePanel("noctalia/world_clock:panel")` on
click, and re-renders on every `update()` and on each watched state change.

### 12. Source layout / publishing rules (affects local dev and Nix packaging)

- A source repo holds many plugins, each in a subdirectory equal to the id's tail (`me/hello` → `hello/`), plus a
  root `catalog.toml` with `[[plugin]]` rows (`id`, `name`, positive `plugin_api` required, rest mirrors the manifest)
  so the store can list/compat-check without a clone.
- Optional `[[plugin.release]]` rows (`plugin_api`, `version`, full 40-char `rev`) let older shells get an older
  revision; they apply to `git` sources only — a `path` source (i.e. the Nix route) has no revisions to export, so a
  Nix-pinned source can only ever deliver one revision.
- Local dev loop: drop under `$XDG_DATA_HOME/noctalia/plugins/<plugin>/` (or a `path` source), enable once, edit
  `.luau` → hot reload; manifest changes need a config reload. Test IPC with the `noctalia msg plugin ...` form above.
- Community submission additionally needs `README.md` (rendered on the store page), `thumbnail.webp`, and
  `translations/en.json`; CI validates via a shared GitHub Action validator with `official`/`community` profiles.

## Gaps, uncertainties, and things to verify against the installed binary

1. **API ceiling**: v5.6.0 docs say "Noctalia currently supports plugin API levels 3 through 56"; the *rolling* docs
   say "3 through 59" and mark 57–59 "Unreleased". Do not assume a plugin declaring `plugin_api = 57` or higher works
   on 5.6.0. If a plugin from the store fails to enable with an "incompatible plugin API" badge, this is why.
2. **Palette writing**: no API sets the active palette. The only evidence that plugins write palette files is one
   sentence in the API-44 row ("Plugins that write palette files in format 2 need this level"). The mechanism (write
   JSON to `~/.config/noctalia/palettes/`, then the user or config selects `[theme].custom_palette`) is **inferred**,
   not documented as a plugin workflow. Marked unverified.
3. **Notification filtering and templates** are config features, not plugin extension points — established from the
   absence of any such entry kind in the manifest table *and* from the notification docs showing config-side
   `[notification.filter.*]` rules. This is an absence claim based on the docs' exhaustive entry-kind table; it was
   not probed against the binary.
4. **Per-call time budget** is stated qualitatively ("per-call time budgets") with no number in the docs. No documented
   specific millisecond limit.
5. **`~/.local/share/noctalia/plugins/<plugin>/` vs a `path` source**: both work; the docs present the data dir as the
   built-in `local` source and recommend `path` sources or that dir for development, but do not state precedence if a
   plugin id exists in both. Unverified.
6. **Home Manager `programs.noctalia` option surface** (e.g. whether `settings` accepts the `plugins.source` list
   verbatim as a Nix attrset with `kind`/`location`) is documented by example only; the module's own option
   documentation in the pinned nixpkgs was not read here.

## Conclusions

For the dotfiles migration the practical picture is: plugins are Luau-only, in-process, trusted, and declared through
one TOML manifest with a mandatory `plugin_api` that 5.6.0 caps at 56. Any capability the migration needs must map
onto the seven entry kinds plus the `noctalia.*` runtime namespace; there is no plugin route to keybinds, notification
filters, or theme templates — those stay config-side. For a declaratively managed setup, the safe pattern is a pinned
`path` source plus `[plugins].enabled` and `[plugin_settings."author/plugin"]` in the Nix `settings`, with the
caveat that GUI edits land in `~/.local/state/noctalia/settings.toml` and override the Nix values until removed.
Everything a plugin persists must go to `pluginDataDir()`, because git-source runtime files are re-exported caches.

## Source Evaluation

1. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/` — official docs, version-pinned. Primary source for sources,
   enable semantics, materialized path, `auto_update`, `plugin_api` range 3–56. Highest weight.
2. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/` — official docs. Entry-kind enumeration, VM/resource
   model, minimal skeleton.
3. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/manifest/` — official docs. Manifest fields, all seven
   entry tables, layer keys, settings schema (authoritative, very detailed).
4. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/entries/` — official docs. Lifecycle callbacks,
   `barWidget.*`, colors, scroll/gesture caveats, layer runtime behaviour.
5. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/runtime-api/` — official docs. `getColor`,
   `getSetting`, `runAsync`/`runStream`, filesystem, state channel, HTTP, idle, OSD, compositor, limits.
6. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/plugin-api/` — official docs. Cumulative API table
   and "3 through 56" for 5.6.0 (rolling page differs — treated as evidence of main-branch drift).
7. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/workflow/` — official docs. Local dev paths, catalog,
   release rows, submission requirements.
8. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/official-plugins/` — official docs. Descriptions and IPC command
   tables for `noctalia/example` and `noctalia/screen_recorder`.
9. `https://docs.noctalia.dev/noctalia/v5.6.0/plugins/development/declarative-ui/` — official docs. `barWidget.render`
   constraints and `ui.*` vocabulary.
10. `https://docs.noctalia.dev/noctalia/v5.6.0/bar/actions/` — official docs. Gesture vocabulary, binding precedence,
    `middle` default, action grammar (IPC command vs `exec`).
11. `https://docs.noctalia.dev/noctalia/v5.6.0/configuration/` — official docs. Config/state/data file locations
    ("Local plugins `~/.local/share/noctalia/plugins/`"), `--credentials` export behaviour.
12. `https://github.com/noctalia-dev/official-plugins` (files `example/plugin.toml`, `example/hello.luau`,
    `example/ticker.luau`, `example/declarative.luau`, `screen_recorder/plugin.toml`, `world_clock/plugin.toml`,
    `world_clock/bar.luau`, `noctalia.d.luau`, `README.md`) — first-party reference code. Used for real structure and
    for confirming API surface (the `.d.luau` has no outbound IPC/palette-write member). Weighted below the docs where
    they disagree, since `main` can be ahead of 5.6.0 (its header declares `plugin_api 53`).

## Bibliography

- Noctalia docs (v5.6.0): `/plugins/`, `/plugins/official-plugins/`, `/plugins/development/`,
  `/plugins/development/manifest/`, `/plugins/development/entries/`, `/plugins/development/declarative-ui/`,
  `/plugins/development/runtime-api/`, `/plugins/development/plugin-api/`, `/plugins/development/workflow/`,
  `/bar/widgets/`, `/bar/actions/`, `/ipc/`, `/ipc/plugins/`, `/configuration/`, `/theming/palette/`,
  `/theming/app-theming/`, `/services/notifications/`, `/getting-started/nixos/`, `/automation/hooks/`
  (all prefixed `https://docs.noctalia.dev/noctalia/v5.6.0`).
- Noctalia docs, rolling (`https://docs.noctalia.dev/noctalia/...`) — same pages, used only to cross-check wording and
  to detect main-branch drift.
- Sitemap `https://docs.noctalia.dev/sitemap-0.xml` — used to enumerate every plugin-related doc page for 5.6.0 and to
  confirm no undocumented plugin page exists (e.g. no plugin "notification filter" nor "templates" page).
- `https://github.com/noctalia-dev/official-plugins` — `README.md`, `noctalia.d.luau`, `catalog.toml`, and the
  `example/`, `screen_recorder/`, `world_clock/`, `bongocat/`, `timer/` plugin directories (directory listings via
  `https://api.github.com/repos/noctalia-dev/official-plugins/contents/<dir>`).
- `https://github.com/noctalia-dev/community-plugins` — repo root listing only (used to confirm third-party plugins live
  there, not to source claims).
- `https://luau.org` — referenced by the docs as the scripting language; not otherwise consulted.
