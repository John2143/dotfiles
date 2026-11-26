# Noctalia 5.6.0 bar widgets: complete inventory, config keys, actions

Scope: Noctalia **5.6.0** (`noctalia-dev/noctalia`, tag `v5.6.0` = commit `a5444b9a2c2bc7c1aed5c59298a268e45de14055`), the version pinned in the user's nixpkgs. All config keys below are quoted verbatim from the official docs. Where the docs site's unversioned pages differ from the `v5.6.0` pages, I used the `v5.6.0` pages and say so.

## Bottom line

- **5.6.0 ships exactly 32 built-in bar widget types.** There is **no generic "run this command and render its stdout" widget** — not in the built-in set, not in the action vocabulary, not in IPC. Waybar's `custom/script` module has no direct equivalent in core.
- `text` and `custom_button` render **static** strings only (`text` / `label`), set at config load; nothing re-evaluates them.
- `sysmon` is not a generic script surface: it exposes a fixed set of 15 numeric stats.
- The three closest things to a Waybar custom module in 5.6.0 are, in increasing order of suitability:
  1. `noctalia msg osd-show <icon> [value]` — a **transient** OSD popup (appears, hides after ~1.4 s). Not a bar element.
  2. the **dmenu launcher provider** (`[shell.launcher.dmenu.<id>]`, `command` → stdout lines become launcher entries) — command output, but in the launcher, not the bar.
  3. a **plugin bar widget** — the only way to get persistent, periodic command output *on the bar*. `tordex/stdout` from the community source does exactly this ("Run a command periodically and display its output as bar widget text") and is API-compatible with 5.6.0.
- Click/scroll behaviour is not baked in: every widget takes an `[widget.<name>.actions]` table binding the nine fixed gestures to either an IPC command (`noctalia msg` vocabulary) or `exec <shell command line>`.

## Shared configuration model

Every widget, built-in or plugin, is configured through a named table. Keys in this block are from the v5.6.0 widget index and apply to all 32 types (`[widgets index](https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/)`):

```toml
[widget.<name>]
type = "<widget-type>"   # defaults to <name> when omitted
scale = 1.0              # multiplies all content by the owning bar's scale
font_scale = 1.0         # additional text-only multiplier
enabled = true           # show or hide this widget on the bar
custom_label = ""        # optional text shown with the widget; leave empty to hide it
show_glyph = true        # false hides the widget's icon glyphs
```

Additional shared per-widget keys (`Per-widget overrides`, `[bar page](https://docs.noctalia.dev/noctalia/v5.6.0/bar/)`): `anchor`, `font_family`, `font_weight`, `capsule`, `capsule_radius`, `capsule_fill`, `capsule_foreground`, `capsule_padding`, `capsule_opacity`, `capsule_border`, `capsule_border_width`, `color`, `icon_color`, `interactive`, `show_tooltip`, `scroll_repeat`.

Peek settings shared by widgets that show a glyph next to a value: `glyph_position` (`"before"` | `"after"`), `peek` (bool, default `false`), `peek_delay_ms` (int, default `100`, range 0–2000).

A widget type can also be instantiated multiple times under different names, e.g. `[widget.clock-seconds] type = "clock"`.

## Action vocabulary (identical in 5.6.0 and current docs)

Source: `[Widget Actions](https://docs.noctalia.dev/noctalia/v5.6.0/bar/actions/)`. I diffed the v5.6.0 page against the unversioned page: no content differences.

Gestures (fixed; "Any other key is a config error"):

| Key | Gesture |
|---|---|
| `left` | Left click |
| `right` | Right click |
| `middle` | Middle click |
| `back` | Thumb button, back |
| `forward` | Thumb button, forward |
| `scroll_up` / `scroll_down` / `scroll_left` / `scroll_right` | Wheel or touchpad, quantized into whole detent steps |

Action forms ("An action is one of three things"):

| Form | Meaning |
|---|---|
| `<command> [arguments]` | Run an IPC command, exactly as `noctalia msg` would |
| `exec <command line>` | Run a shell command |
| `none` | Unbind the gesture |

Resolution order ("later layers win, one gesture at a time"): built-in defaults (every widget gets `middle` → its own settings) → widget-type defaults → `[bar.<name>.actions]` → `[widget.<name>.actions]`. There are explicitly **no modifier combinations**: "The bar never takes keyboard focus, so it cannot know which modifiers are held."

`scroll_repeat` (`auto` default | `gesture` | `steps`) decides whether a bound scroll action fires once per gesture or per scroll step.

Default bindings per type, read from the v5.6.0 source (`src/shell/bar/widget_gesture_defaults.cpp`) — these are the authoritative "what it does out of the box":

| Widget type | Default bindings |
|---|---|
| `battery` | `left` = `panel-toggle control-center power` |
| `bluetooth` | `left` = `panel-toggle control-center bluetooth`, `right` = `bluetooth-toggle` |
| `brightness` | `left` = `panel-toggle control-center monitor`, `scroll_up` = `brightness-up`, `scroll_down` = `brightness-down` |
| `caffeine` | `left` = `caffeine-toggle` |
| `clipboard` | `left` = `panel-toggle clipboard` |
| `clock` | `left` = `panel-toggle control-center calendar` |
| `control-center` | `left` = `panel-toggle control-center home` |
| `keyboard_layout` | `left` = `keyboard-layout-cycle` |
| `launcher` | `left` = `panel-toggle launcher` |
| `media` | `left` = `panel-toggle control-center media`, `right` = `media toggle`, `back` = `media previous`, `forward` = `media next`, `scroll_up` = `media next`, `scroll_down` = `media previous` |
| `network` | `left` = `panel-toggle control-center network`, `right` = `network-toggle` |
| `nightlight` | `left` = `nightlight-toggle`, `right` = `nightlight-force-toggle` |
| `notifications` | `left` = `panel-toggle control-center notifications`, `right` = `notification-dnd-toggle` |
| `power_profile` | `left` = `power-cycle next`, `right` = `power-cycle prev`, `scroll_up` = `power-cycle next`, `scroll_down` = `power-cycle prev` |
| `screenshot` | `left` = `screenshot-region` |
| `session` | `left` = `panel-toggle session` |
| `settings` | `left` = `settings-open` |
| `sysmon` | `left` = `panel-toggle control-center system` |
| `taskbar` | `scroll_up` = `taskbar-cycle prev`, `scroll_down` = `taskbar-cycle next` |
| `theme_mode` | `left` = `theme-mode-toggle` |
| `volume` (output) | `left` = `panel-toggle control-center audio`, `right` = `volume-mute`, `scroll_up` = `volume-up`, `scroll_down` = `volume-down` |
| `volume` (`device = "input"`) | `left` = `panel-toggle control-center audio`, `right` = `mic-mute`, `scroll_up` = `mic-volume-up`, `scroll_down` = `mic-volume-down` |
| `wallpaper` | `left` = `panel-toggle wallpaper` |
| `weather` | `left` = `panel-toggle control-center weather` |
| `workspaces` | `scroll_up` = `workspace-switch prev`, `scroll_down` = `workspace-switch next` |

Types with **no** default gesture binding beyond the universal `middle` → settings: `active_window`, `audio_visualizer`, `custom_button`, `privacy`, `spacer`, `text`, `tray`.

Reserved (unbindable per-item) gestures (`kTypeReserved`): `workspaces.left`, `taskbar.left` + `taskbar.middle`, `tray.left` + `tray.right`, `screenshot.right`.

The dead zone (bar area not covered by widgets) takes the same bindings under `[bar.default.dead_zone.actions]`; its built-in default is `right` = `panel-toggle control-center home`.

## The 32 built-in widget types

For each: keys verbatim (defaults in parens), what it renders, default gestures, and whether it can display arbitrary command output.

### Layout & windows

**`active_window`** — active window icon + title for the bar's output.
Keys: `colorize_icons` (`false`), `min_length` (`80`), `max_length` (`260`), `icon_size` (`16`), `title_scroll` (`"none"` | `"always"` | `"on_hover"`), `display` (`"icon_and_text"` | `"icon_only"` | `"text_only"`), `show_empty_label` (`false`), `empty_label` (`""`).
Actions: none by default (only `middle` → settings). Arbitrary output: no — title comes from the compositor.

**`clock`** — current time, formatted.
Keys: `format` (`{:%H:%M}`), `vertical_format` (`""`), `tooltip_format` (`""`), `timezone` (`""`, e.g. `Europe/Berlin`).
Actions: `left` = control-center calendar. Arbitrary output: no — strftime-style tokens only (`[date format tokens](https://docs.noctalia.dev/noctalia/v5.6.0/configuration/date-format-tokens/)`).

**`spacer`** — empty space.
Keys: `length` (`20`), `expand` (`false`), `interactive` (`false`).
Actions: click-through by default; set `interactive = true` to make it a hot zone and bind gestures. Arbitrary output: no (renders nothing).

**`taskbar`** — icon-only running-app list, optional pins, optional workspace grouping. No text output.
Keys: `colorize_icons` (`false`), `pinned` (`[]`), `pinned_opacity` (`0.5`), `show_running` (`true`), `group_by_workspace` (`false`), `show_all_outputs` (`false`), `only_active_workspace` (`false`), `hidden_workspaces` (`[]`), `icon_scale` (`1.0`), `prefer_symbolic_icons` (`false`), `item_spacing` (`4`), `show_window_title` (`false`), `window_title_max_width` (`100`), `taskbar_max_width` (`8192`), `show_workspace_label` (`true`), `label_source` (`"name"`), `minimal` (`false`), `workspace_label_placement` (`corner`), `hide_empty_workspaces` (`false`), `workspace_group_capsule` (`true`), `workspace_group_content` (`icons`), `workspace_group_active_border_color` (`"primary"`), `workspace_group_inactive_border_color` (`"outline_variant"`), `group_single_icon_per_app` (`false`), `show_active_indicator` (`true`), `active_indicator_color` (`"primary"`), `active_opacity` (`1.0`), `inactive_opacity` (`1.0`), `focused_color` (`"primary"`), `occupied_color` (`"secondary"`), `empty_color` (`"secondary"`), `urgent_color` (`"error"`), `focused_output_only` (`false`).
Actions: scroll cycles tasks; `left`/`middle` are reserved per icon (activate / close). Arbitrary output: no.

**`text`** — fixed text.
Keys: `text` (`""`). Requires a named `[widget.<name>]` entry.
Actions: none by default. Arbitrary output: **no** — the docs describe it as "Fixed text on the bar" with a single literal string key; there is no command, script, format or interval key.

**`workspaces`** — workspace switcher, `style` = `"regular"` | `"minimal"` | `"focus_hint"`.
Keys: `colorize_icons` (`false`), `style` (`"regular"`), `show_labels` (`true`), `show_icons` (`true`), `separator` (`""`), `separator_color` (`"on_surface"`), `label_source` (`"id"`), `max_label_chars` (`1`), `pill_scale` (`1.0`), `active_pill_size` (`2.2`), `inactive_pill_size` (`1.0`), `focused_color` (`"primary"`), `occupied_color` (`"secondary"`), `empty_color` (`"secondary"`), `urgent_color` (`"error"`), `change_color_on_hover` (`true`), `focused_output_only` (`false`), `labels_only_when_occupied` (`false`), `hide_when_empty` (`false`), `monitors` (`[]`). Former `show_all_outputs` is auto-migrated to `monitors = ["*"]`.
Actions: scroll switches workspace; `left` reserved per pill. Arbitrary output: no — labels come from compositor workspace names/ids.

### Audio, media & information

**`audio_visualizer`** — horizontal PipeWire monitor spectrum.
Keys: `width` (`56`), `bands` (`16`), `mirrored` (`true`), `centered` (`true`), `show_wave` (`false`), `show_when_idle` (`false`), `color_1` (`"primary"`), `color_2` (`"primary"`).
Actions: none. Arbitrary output: no.

**`media`** — MPRIS artwork + track text.
Keys (**v5.6.0**): `album_art_only` (`false`), `rotate_album_art` (`false`), `hide_album_art` (`false`), `hide_artist` (`false`), `artist_first` (`false`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `min_length` (`80`), `max_length` (`220`), `art_size` (`16`), `title_scroll` (`"none"`), `hide_when_no_media` (`false`), `hide_when_idle` (`false`).
Inference flagged: the unversioned (post-5.6.0) docs add `circular_album_art`; it is **not** in the v5.6.0 page or the v5.6.0 tree, so do not use it.
Actions: see default table (left = control-center media tab, right = play/pause, thumb buttons = prev/next, scroll = next/prev). Arbitrary output: no.

**`volume`** — PipeWire sink/source volume + mute.
Keys: `device` (`"output"` | `"input"`), `show_glyph` (`true`), `glyph` (`""`), `mute_glyph` (`""`), `effects_profile_glyphs` (`{}`), `custom_image` (`""`), `custom_image_colorize` (`false`), `show_label` (`true`), `hide_label_when_muted` (`false`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `mute_color` (`"error"`), `hide_when_inactive` (`false`, input only).
Actions: left = audio tab, right = mute, scroll = ±5% steps. Arbitrary output: no.

**`weather`** — configured weather condition/temperature.
Keys: `max_length` (`160`), `show_condition` (`true`), `show_temperature` (`true`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`). Requires `[weather]`.
Actions: left = control-center weather tab. Arbitrary output: no.

### System & hardware

**`battery`** — UPower charge level/state.
Keys: `display_mode` (`"glyph"` | `"none"` | `"graphic"`), `show_label` (`true`), `label_content` (`"percent"` | `"time"` | `"rate"`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `hide_when_plugged` (`false`), `hide_when_full` (`false`), `device` (`"auto"`), `warning_color` (`"error"`).
Actions: left = control-center power tab. Arbitrary output: no.

**`bluetooth`** — adapter state + connected device.
Keys: `show_label` (`false`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `hide_when_adapter_off` (`false`), `hide_when_no_connected_device` (`false`).
Actions: left = Bluetooth tab, right = adapter power toggle. Arbitrary output: no.

**`brightness`** — monitor brightness.
Keys: `show_glyph` (`true`), `show_label` (`true`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `show_when_unavailable` (`false`).
Actions: left = display tab, scroll = brightness up/down. Arbitrary output: no.

**`keyboard_layout`** — active XKB layout (or fcitx5 input method).
Keys: `hide_when_single_layout` (`false`), `show_glyph` (`true`), `glyph` (`"keyboard"`), `custom_image` (`""`), `custom_image_colorize` (`false`), `show_label` (`true`), `display` (`"short"` | `"full"`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`). Layout-name aliases live globally in `[shell.keyboard_layout.custom_labels]`.
Actions: left cycles layouts ("Bind `left` to an `exec` action to run a custom command instead"). Arbitrary output: no — text is the layout name.

**`lock_keys`** — Caps/Num/Scroll Lock indicators.
Keys: `display` (`"short"` | `"full"`), `show_caps_lock` (`true`), `show_num_lock` (`true`), `show_scroll_lock` (`false`), `hide_when_off` (`false`).
Actions: none by default. Arbitrary output: no.

**`network`** — Wi-Fi/wired/cellular + VPN status via NetworkManager.
Keys: `show_label` (`true`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `vpn_status` (`"replace"` | `"both"` | `"hidden"`), `show_vpn_label` (`false`).
Actions: left = Network tab, right = disconnect/reconnect. Arbitrary output: no.

**`power_profile`** — glyph only.
Keys: none of its own ("This widget has no settings of its own beyond the shared ones").
Actions: left = next profile, right = previous, scroll = same. Arbitrary output: no.

**`privacy`** — mic/camera/screen-capture indicators from PipeWire + V4L2.
Keys: `hide_inactive` (`false`), `icon_spacing` (`4`), `active_color` (`"primary"`), `inactive_color` (`"outline_variant"`). Global filters in `[shell.privacy]`.
Actions: none by default (hover lists apps). Arbitrary output: no.

**`sysmon`** — one system statistic, with glyph + gauge/graph + value.
Keys: `stat` (`"cpu_usage"`), `path` (`"/"`), `interface` (`""`), `network_speed_unit` (`"auto"` | `"kb"` | `"mb"`), `network_speed_compact` (`false`), `network_speed_decimal_places` (`1`), `visualization` (`"gauge"` | `"graph"` | `"none"`), `show_cpu_cores` (`false`), `show_value` (`true`), `label_show_units` (`true`), `label_min_width` (`0`), `show_glyph` (`true`), `glyph` (`""`), `custom_image` (`""`), `custom_image_colorize` (`false`), `custom_label` (`""`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `highlight_color` (`"error"`).
The `stat` value is a closed set of 15 (`[System Monitor](https://docs.noctalia.dev/noctalia/v5.6.0/services/system-monitor/)`): `cpu_usage`, `cpu_temp`, `cpu_freq`, `gpu_temp`, `gpu_usage`, `gpu_vram`, `ram_used`, `ram_pct`, `swap_pct`, `disk_used_pct`, `disk_used`, `disk_free_pct`, `disk_free`, `net_rx`, `net_tx`. Sampling cadence is global (`[system.monitor]`, `cpu_poll_seconds` etc.), not per widget.
Actions: left = control-center system tab. Arbitrary output: **no** — `stat` is an enum, there is no command key.

**`tray`** — StatusNotifierItem icons / drawer.
Keys: `colorize_icons` (`false`), `hidden` (`[]`), `pinned` (`[]`), `hide_passive` (`true`), `match_adjacent_spacing` (`false`), `drawer` (`false`), `glyph` (`""`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `drawer_columns` (`3`), `drawer_item_size` (*inherit*), `drawer_background_opacity` (*inherit*), `detached_panel` (`false`), `icon_override_blacklist` (`[]`), `icon_type` (`default` | `desktop` | `symbolic`).
Actions: `left`/`right` reserved per item; `middle` → settings. Arbitrary output: no.

### Quick toggles

**`caffeine`** — coffee glyph, toggles idle inhibitor. No configurable settings. `left` = `caffeine-toggle`. Arbitrary output: no.
**`nightlight`** — moon glyph, three states (off/scheduled/forced). No configurable settings. `left` toggles, `right` toggles the force override. Arbitrary output: no.
**`theme_mode`** — moon/sun glyph, toggles dark/light. No configurable settings. `left` = `theme-mode-toggle`. Arbitrary output: no.

### Buttons & panels

All of these share the same three appearance keys — `glyph`, `custom_image` (`""`), `custom_image_colorize` (`false`) — plus, for `custom_button`, `label`/`tooltip`/peek.

**`clipboard`** — `glyph` (`"clipboard"`). Left = `panel-toggle clipboard`.
**`control-center`** — `glyph` (`"noctalia"`). Left = control-center home.
**`custom_button`** — `glyph` (`"heart"`), `custom_image`, `custom_image_colorize`, `label` (`""`), `glyph_position` (`"before"`), `peek` (`false`), `peek_delay_ms` (`100`), `tooltip` (`""`). Renders a glyph/image "and an optional label". **No default gestures** — "What it does on click and scroll is set with widget actions", so a `custom_button` without `[widget.<name>.actions]` does nothing but open settings on middle click. Arbitrary output: **no** — `label` is a static string; there is no command key.
**`launcher`** — `glyph` (`"search"`). Left = launcher.
**`notifications`** — `hide_when_no_unread` (`false`). Left = notifications tab, `right` = DND.
**`screenshot`** — `glyph` (`"screenshot"`). Left = `screenshot-region`, `right` (reserved) = capture menu. Output policy is global under `[shell.screenshot]`.
**`session`** — `glyph` (`"shutdown"`). Left = session menu.
**`settings`** — `glyph` (`"settings"`). Left = `settings-open`.
**`wallpaper`** — `glyph` (`"wallpaper-selector"`). Left = wallpaper picker.

## Critical question: is there a "run this command, show its stdout" widget?

**No. Not in 5.6.0 core.** Evidence, in order of strength:

1. **Exhaustive widget registry.** The v5.6.0 factory (`src/shell/bar/widget_factory.cpp` at tag `v5.6.0`) registers exactly these type keys: `active_window, audio_visualizer, battery, bluetooth, brightness, caffeine, clipboard, clock, control-center, custom_button, debug_indicator, keyboard_layout, launcher, lock_keys, media, network, nightlight, notifications, power_profile, privacy, screenshot, session, settings, spacer, sysmon, taskbar, test, text, theme_mode, tray, volume, wallpaper, weather, workspaces` — 34 keys, of which `debug_indicator` and `test` are internal. There is no `custom`, `script`, `exec`, `command`, or `cmd` type. Docs list the same 32 user-facing types (`[widgets index, v5.6.0](https://docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/)`).
2. **`text` is literal.** Its only key is `text` (string). The page calls it "Fixed text on the bar" and requires a named entry.
3. **`custom_button`'s `label` is literal.** Only `label`, `tooltip`, `glyph`, `custom_image*`, peek keys. No interval, no command, no format.
4. **No IPC path pushes text into a widget.** The complete bar IPC surface is `bar-show`, `bar-hide`, `bar-toggle`, `bar-auto-hide-set`, `bar-layer-set`, `bar-reserve-toggle` (`[Surfaces](https://docs.noctalia.dev/noctalia/ipc/surfaces)`); none of them sets a widget's text. Only plugin entries accept runtime state events (`noctalia msg plugin <author/plugin:entry> <target> <event> [payload]`).
5. **`sysmon` is not a script surface** — `stat` is a 15-value enum, and cadence is global.

What does exist, in order of how close it gets:

- **`noctalia msg osd-show <icon> [value]`** (`[System Controls → OSD](https://docs.noctalia.dev/noctalia/ipc/system-controls)`) — "Show a custom popup with a glyph and optional text", and it accepts a JSON payload (`{"icon":"brightness-low","value":"40%","progress":0.4}`) plus `inactive` for a muted look. This is the "custom OSD" — **transient only** (`[osd] hide_delay_ms`, default `1400`). `[osd.kinds] custom` gates "custom popups sent by plugins or scripts". It is not a bar element and cannot stay on screen.
- **dmenu launcher provider** (`[Launcher → Providers](https://docs.noctalia.dev/noctalia/v5.6.0/launcher/)`): `[shell.launcher.dmenu.<id>]` with `command` ("Shell command run through `/bin/sh -lc`; each stdout line becomes a launcher result"), `label`, `prefix`, `glyph`, `global`, `exec`. This is a Waybar-custom-style command surface, but its output lands in the launcher list, not the bar. There is also `noctalia dmenu` for ad-hoc script menus.
- **A plugin bar widget — the only way to get periodic command output on the bar.** The `stdout` community plugin (`tordex/stdout`, version 1.1.0, `plugin_api = 28`) is literally "Run a command periodically and display its output as bar widget text", with settings `cmd`, `interval` (int, 1–59), `interval_units` (`seconds`/`minutes`/`hours`), `json` (bool) and `hide_on_error`. Right-click forces an update; `noctalia msg plugin tordex/stdout:bar all update` refreshes by IPC. In JSON mode the command returns `{"visible":true,"glyph":"mouse","text":"26%","fontWeight":"bold","textColor":"#00FF00","glyphColor":"error","tips":[...]}` — i.e. a full Waybar `custom`-module equivalent including glyph, colour, weight and tooltip.
  - Its README states "Noctalia plugin API 28 or newer"; 5.6.0 supports plugin API levels 3–59 (`[Plugins](https://docs.noctalia.dev/noctalia/plugins/)`), so it is compatible. I did not run it.
- **Writing your own plugin widget** is viable: the plugin runtime API has `noctalia.runAsync(cmd, cb)` ("Runs a process with output capture, then calls `cb(result)`"), `noctalia.runStream(cmd, onLine)` ("calls `onLine(line)` for each stdout line"), plus `noctalia.commandExists(name)` (`[Runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api)`). A bar-widget entry can render that text.

Consequence for a Waybar migration: every `custom/<name>` module that displayed text must become either (a) one of the 32 built-ins if a built-in covers the data, (b) the `stdout` plugin widget (one widget instance per command, `cmd` + `interval`), or (c) a purpose-written plugin. A `custom` module used only for a click action maps cleanly to `custom_button` + `actions`/`exec`.

## Version-control checks I ran

- `git ls-remote --tags https://github.com/noctalia-dev/noctalia` shows `refs/tags/v5.6.0` → `29c22094…`, dereferenced `a5444b9a2c2bc7c1aed5c59298a268e45de14055`. All source quotes above are from that commit.
- Doc-set comparison: the `v5.6.0` widget index lists 32 widget pages; the unversioned (next-release) index lists 33, the extra one being `color-picker`. The v5.6.0 source tree has no `color_picker` bar widget. **So `color-picker` is a post-5.6.0 widget — do not use it in a 5.6.0 config.**
- 5.6.0 vs unversioned doc bodies: two real content differences found — `media.circular_album_art` (newer only) and reworded `privacy` V4L2 detection text. Everything else is link-path noise.

## Source Evaluation

1. `docs.noctalia.dev/noctalia/v5.6.0/bar/widgets/` and the 32 child pages — primary, versioned official docs; the basis for every "Settings" table quoted. Limitation: prose defaults are sometimes omitted, which is why bindings come from source.
2. `docs.noctalia.dev/noctalia/v5.6.0/bar/actions/` — primary; gesture list, three action forms, resolution layers. Byte-identical (modulo link prefix) to the unversioned page.
3. `docs.noctalia.dev/noctalia/v5.6.0/bar/` — primary; bar-level and per-widget override keys.
4. `src/shell/bar/widget_factory.cpp` @ `v5.6.0` — primary source, definitive type registry. Strongest evidence for the absence of a custom/exec widget.
5. `src/shell/bar/widget_gesture_defaults.cpp` @ `v5.6.0` — primary source; default gesture bindings and reserved gestures.
6. `docs.noctalia.dev/noctalia/v5.6.0/services/system-monitor/` — primary; the 15 allowed `stat` values.
7. `docs.noctalia.dev/noctalia/ipc/system-controls` — primary; `osd-show` signature and JSON fields, `osd-enable/-disable/-toggle`.
8. `docs.noctalia.dev/noctalia/ipc/surfaces` — primary; bar IPC commands (show/hide/toggle only).
9. `docs.noctalia.dev/noctalia/v5.6.0/launcher/` — primary; dmenu provider `command` → stdout lines.
10. `docs.noctalia.dev/noctalia/plugins/` — primary; plugin API range 3–59, enablement model.
11. `github.com/noctalia-dev/community-plugins` — `stdout/plugin.toml`, `stdout/README.md`, plus a directory listing used to locate `shell-command`, `cmd-runner`. Community, third-party, MIT; not audited by me and not run. `shell-command` is launcher-only (`/sh`, `/shb` prefixes); `cmd-runner` runs saved commands from a panel, with only `show_label` as widget config — neither shows command stdout on the bar.
12. `docs.noctalia.dev/noctalia/plugins/development/runtime-api` — primary; `runAsync(cb)` / `runStream(onLine)` confirm plugin-side output capture.

## Bibliography (read, not relied on)

- `https://docs.noctalia.dev/noctalia/bar/widgets/` (unversioned; used only for the diff)
- `https://docs.noctalia.dev/noctalia/configuration/shell/` (OSD block, `[osd.kinds] custom`, keyboard-layout aliases)
- `https://docs.noctalia.dev/noctalia/plugins/official-plugins/` (9 official plugins: example, screen_recorder, translator, timer, bongocat, wallhaven, wallpaper_depth, mpvpaper, world_clock — none shows command output)
- `https://docs.noctalia.dev/noctalia/ipc/`, `/ipc/media-and-ui/`, `/ipc/shell-and-ui/`, `/ipc/system-controls/`
- `https://raw.githubusercontent.com/noctalia-dev/noctalia/main/README.md`
- `https://github.com/noctalia-dev/noctalia/issues/3516` ("[FEATURE] Custom OSD", found via search; not fetched — mentioned for context only, **unverified**)

## Conclusions

For a Waybar → Noctalia 5.6.0 migration, the portfolio splits three ways. Everything Waybar expressed as a built-in covers itself: clock/format strings, battery, network, volume, brightness, tray, taskbar, workspaces, media, weather, keyboard layout, lock keys, power profile. Everything Waybar expressed as `custom/<name>` showing *text* has no in-core replacement — `text` and `custom_button` are static, `sysmon` is a 15-stat enum, and no IPC call writes widget text — so it must become a plugin widget (`stdout` for the common case, or a hand-written Luau widget using `runStream`) or be dropped/relocated to `osd-show` or the dmenu provider. Everything Waybar expressed as a click-only `custom/script` maps exactly onto `custom_button` with `[widget.<name>.actions]` bindings, since `exec` actions accept arbitrary shell command lines and every gesture is rebindable.

Two migration traps worth stating plainly: the action vocabulary is IPC-command-first and only falls back to `exec` on explicit opt-in ("A misspelled command … is never silently treated as a shell command"), so a copied Waybar `on-click` string will not work as-is; and the pinned nixpkgs version 5.6.0 predates `color-picker` and `media.circular_album_art`, both of which the current docs site documents — configuring them on 5.6.0 is a config error, not a silent no-op.
