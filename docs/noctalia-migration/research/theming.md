# Noctalia v5.6.0 — Theming End-to-End: `[theme]`, palettes, templates, and generated app configs

Research target: Noctalia **v5.6.0**. Doc citations use the version-pinned prefix
`https://docs.noctalia.dev/noctalia/v5.6.0/...` (probed 2026-11-25: `theming/`, `theming/palette/`,
`theming/app-theming/`, `theming/templates/`, `ipc/media-and-ui/`, `configuration/` all return HTTP 200; the pinned
`theming/` page is byte-identical in rendered text to the rolling page). Structural claims that a doc page could not
settle are answered from the v5.6.0 source tree (`noctalia-dev/noctalia`, tag `v5.6.0`, commit
`29c2209467d339a6456515593b26103fad33bd6c` per `git ls-remote --tags`). Local evidence about the *existing* pipeline
comes from this repo's `nixos/modules/theme.nix` and `nixos/theme-switch.sh`.

## Summary

Noctalia v5 theming has three independent layers, and separating them is the whole migration decision:

1. **Palette selection** — a `[theme]` table in TOML choosing one of four sources (`builtin`, `wallpaper`,
   `community`, `custom`), a `mode` (`dark`/`light`/`auto`), and an independent `shell_mode` for the shell's own
   surface. Ten palettes are compiled in, including **Catppuccin** = Mocha dark + Latte light.
2. **Template rendering** — a built-in catalog of **21 app/compositor templates** (`alacritty`, `btop`, `cava`,
   `emacs`, `foot`, `ghostty`, `gtk3`, `gtk4`, `helix`, `kcolorscheme`, `kitty`, `labwc`, `luciole`, `niri`,
   `hyprland`, `mango`, `qt`, `scroll`, `sway`, `umbriel`, `wezterm`) plus opt-in community templates and
   user-declared TOML entries. Templates do not only write files: several **run shell hooks that edit the
   application's own config** (inject an Alacritty `import`, append `require("noctalia").apply_theme()` to
   `hyprland.lua`, append `@import` to `gtk.css`, rewrite `kdeglobals`) and several **write GSettings/dconf state**.
3. **Deep, opt-in, and global.** Nothing in layer 2 happens until you name templates: the two catalog flags
   (`enable_builtin_templates`, `enable_community_templates`) actually default to **`true`** in the binary
   (`TemplatesConfig` in `src/config/config_types.h`), but `builtin_ids`/`community_ids` default empty and are
   whitelists, so an empty array means "render nothing". Disabling is therefore one global flag per catalog plus
   per-app membership in the id list — there is no per-entry `enabled` flag for built-ins.
   One thing is **not** part of templates and cannot be gated by them: `sync_color_scheme` writes
   `org.gnome.desktop.interface color-scheme` on every theme application.

For this repo the practical finding is that Noctalia's template layer would fight the existing `theme-switch`
pipeline at four concrete points — the Alacritty hook writes through a symlink into the git checkout, the GTK hook
creates/edits `gtk.css` and writes `gtk-theme` + `color-scheme` through dconf, Qt/`kdeglobals` would replace the
current portal/Breeze path rather than complement it, and the Hyprland hook appends a `require` to `hyprland.lua` —
plus two systemic ones: Waybar/Eww/Wofi/Dunst/Hyprlock have no Noctalia template at all, and a GUI-written
`settings.toml` outranks the Home-Manager-owned `config.toml`. The palette layer alone is harmless, though duplicative
of the repo's own Catppuccin data. Details in Finding 11.

## Findings

### 1. The `[theme]` table — every key, verbatim

From the Theme page (`https://docs.noctalia.dev/noctalia/v5.6.0/theming/`) and confirmed against the schema in
`src/config/schema/config_schema_theme.cpp` (`themeSchema()`, which registers exactly these keys plus the
`templates` sub-table):

```toml
[theme]
mode              = "dark"        # dark | light | auto
shell_mode        = "follow"      # follow | dark | light | auto
source            = "builtin"     # builtin | wallpaper | community | custom
builtin           = "Noctalia"    # bundled palette name when source = "builtin"
community_palette = "Oxocarbon"   # palette name when source = "community"
custom_palette    = "MyPalette"   # file name without .json when source = "custom"
wallpaper_scheme  = "m3-content"  # generator used when source = "wallpaper"
pure_black_dark   = false         # replace dark-mode backgrounds with pure black
terminal_colors   = "palette"     # palette | standard
sync_color_scheme = true          # sync the GNOME color-scheme preference with mode
```

Semantics that matter for a migration:

- **`mode`** is the layer that apps see: it selects the palette variant written by templates *and* the GNOME
  `color-scheme` preference *and* the value reported to `theme_mode_changed` hooks. `auto` resolves through the
  shared sunrise/sunset schedule in `[location]` (same rules as Night Light; `custom_schedule = true` uses explicit
  `sunset`/`sunrise`); if the schedule cannot be resolved it **falls back to light**.
- **`shell_mode`** styles only Noctalia's own UI (bars, panels, launcher, greeter). `follow` tracks `mode`
  (default); `dark`/`light` pin the shell while `mode` still drives apps; `auto` uses the schedule independently.
  Changing only `shell_mode` repaints the shell and rewrites **no** template.
- **`source`** — four values, each with its own companion key: `builtin` (compiled-in palettes), `wallpaper`
  (generated from the current default wallpaper, re-resolved when the wallpaper changes), `community` (fetched from
  `https://api.noctalia.dev/palette/<name>`, cached under `~/.local/state/noctalia/community-palettes/` and
  md5-refreshed from the catalog), `custom` (a JSON file in `~/.config/noctalia/palettes/`).
- **`wallpaper_scheme`** is honoured only when `source = "wallpaper"`. Values:
  `m3-tonal-spot`, `m3-content`, `m3-fruit-salad`, `m3-rainbow`, `m3-monochrome` (Material 3 variants) and the
  custom set `vibrant`, `faithful`, `soft`, `dysfunctional`, `muted`.
- **`terminal_colors`** affects **only wallpaper-generated** palettes: `palette` (default) takes ANSI colours from
  accent roles, `standard` keeps recognizable red/green/yellow/blue and nudges them toward the primary. Built-in,
  community, and custom palettes "keep their own terminal colors", so this key is a no-op for a Catppuccin setup.
  `noctalia theme --terminal-colors standard` previews it.
- **`pure_black_dark`** replaces dark-mode background roles with black, preserving foreground/accent; no effect in
  light mode; forced on by accessibility high contrast.
- **`sync_color_scheme = true`** (default) makes Noctalia write `org.gnome.desktop.interface color-scheme` as
  `prefer-dark` / `prefer-light` through `gsettings` or `dconf` "whenever templates are applied for mode", so it
  fires **even with zero templates enabled**. This is the single most easily overlooked side effect: it is a writer
  of session-wide desktop state, not a template.
- Palette changes apply live on config change (Settings **or** edits to `~/.config/noctalia/*.toml`, hot-reloaded).

### 2. Colour roles: 28 roles, 16 set by a palette file, the rest derived

From `https://docs.noctalia.dev/noctalia/v5.6.0/theming/palette/`:

Set directly by a palette file (16): `primary`, `on_primary`, `secondary`, `on_secondary`, `tertiary`,
`on_tertiary`, `error`, `on_error`, `surface`, `on_surface`, `on_surface_variant`, `surface_container`,
`outline_variant`, `shadow`, `hover`, `on_hover`.

Derived: `primary_container` / `on_primary_container` (from `primary`), `secondary_container` /
`on_secondary_container`, `tertiary_container` / `on_tertiary_container`, `error_container` /
`on_error_container`, `surface_container_high` and `surface_container_highest` (from `surface_container`), and
`surface_container_low` (between `surface` and `surface_container`). `scrim` is literally black.

Role renames in v5: `surface_variant` → `surface_container` and `outline` → `outline_variant` "with the same
colors"; Noctalia rewrites them on load and warns. The new names need **plugin API 43**. Templates are unaffected and
keep the full Material token set, where `surface_variant` and `outline` retain their Material meaning — so a template
can use `{{ colors.surface_variant.default.hex }}` (Material role) while a palette file must use `surface_container`.

Templates expose **48 Material tokens plus `hover`/`on_hover`** and 22 flattened terminal tokens; full list in
`https://docs.noctalia.dev/noctalia/v5.6.0/theming/templates/`.

### 3. Built-in palettes, and what "Catppuccin" means here

The `builtin` list is exactly: **Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa, Noctalia, Nord, Rosé Pine,
Tokyo-Night**. Unknown names fall back to `Noctalia`.

Catppuccin is compiled into the binary (`src/theme/builtin_palettes.cpp`, entry `.name = "Catppuccin"` with `dark`
and `light` variants). The dark variant is **Mocha** and the light variant is **Latte**, with this exact 16-role
mapping (read from source, not inferred):

| role | dark (Mocha) | light (Latte) |
|---|---|---|
| `primary` | `#cba6f7` (mauve) | `#8839ef` (mauve) |
| `on_primary` | `#11111b` (crust) | `#eff1f5` (base) |
| `secondary` | `#fab387` (peach) | `#fe640b` (peach) |
| `on_secondary` | `#11111b` | `#eff1f5` |
| `tertiary` | `#94e2d5` (teal) | `#40a02b` (green) |
| `on_tertiary` | `#11111b` | `#eff1f5` |
| `error` | `#f38ba8` (red) | `#d20f39` (red) |
| `on_error` | `#11111b` | `#dce0e8` (crust) |
| `surface` | `#1e1e2e` (base) | `#eff1f5` (base) |
| `on_surface` | `#cdd6f4` (text) | `#4c4f69` (text) |
| `surface_container` | `#313244` (surface0) | `#ccd0da` (surface0) |
| `on_surface_variant` | `#a3b4eb` | `#6c6f85` (subtext0) |
| `outline_variant` | `#4c4f69` (text!) | `#a5adcb` (off-palette blend) |
| `shadow` | `#11111b` (crust) | `#dce0e8` (crust) |
| `hover` | `#94e2d5` (teal) | `#40a02b` (green) |
| `on_hover` | `#11111b` | `#eff1f5` |

Two observations worth flagging for this repo:

- `on_surface_variant` dark = `#a3b4eb` is **not** a Catppuccin colour (it is a blended periwinkle), and
  `outline_variant` dark = `#4c4f69` is Catppuccin *text* rather than an outline; `hover` is teal in both flavours.
  Noctalia's Catppuccin is a hand-tuned interpretation, not a mechanical 1:1 of the upstream palette. Any visual
  diff against the repo's `palettes` map in `nixos/modules/theme.nix` is expected, not a bug.
- Terminal colours are curated per variant (16 ANSI + foreground/background/cursor/cursor-text/selection) and are
  close to, but not identical with, upstream Catppuccin terminal ports (e.g. bright red is `#f37799`, not `#f38ba8`).

### 4. `custom_palette`: file location, JSON format, required vs derived

- Selected by `source = "custom"` + `custom_palette = "MyPalette"`, which loads
  `~/.config/noctalia/palettes/MyPalette.json` (config dir honours `NOCTALIA_CONFIG_HOME`, then `XDG_CONFIG_HOME`).
  The GUI lists files found there. A missing or invalid file falls back to the Noctalia built-in palette.
- Key insight from source (`src/theme/fixed_palette_json.cpp`, `parsePaletteFile`): the file is a **directory of
  modes**, and `dark` is mandatory. `light` is optional — "If light is omitted, Noctalia uses the dark variant for
  both modes". A file with no `dark` object, or a non-object root, is rejected outright (`return std::nullopt`).
- **Undocumented strictness:** within each mode object, a `terminal` object is *required* — `readModeTerminalJson`
  returns `nullopt` when the key is absent or not an object, and `parsePaletteFile` propagates that as a rejected
  palette. A palette that supplies all 16 roles with no `terminal` block is therefore **invalid**, even though the
  docs present `terminal` as an opt-in convenience. (Verified by reading the parser, not by running the binary.)
- By contrast, missing *role* keys are not rejected: `readColorField` returns a default-constructed `Color{}` for a
  missing key, so an incomplete role set loads with empty/undefined colours. The doc's "sets 16 of these roles" is a
  contract, not a validation error.

Format-2 example, quoted in full from the Palette page (docs render this same JSON for both variants; every key
below is a real value, nothing elided):

```json
{
  "version": 2,
  "base": "Monokai",
  "dark": {
    "primary": "#a6e22e",
    "on_primary": "#272822",
    "secondary": "#66d9ef",
    "on_secondary": "#272822",
    "tertiary": "#f92672",
    "on_tertiary": "#272822",
    "error": "#f92672",
    "on_error": "#272822",
    "surface": "#272822",
    "on_surface": "#f8f8f2",
    "surface_container": "#3e3d32",
    "on_surface_variant": "#a6e22e",
    "outline_variant": "#75715e",
    "shadow": "#272822",
    "hover": "#3a3a32",
    "on_hover": "#f8f8f2",
    "terminal": {
      "background": "#272822",
      "foreground": "#f8f8f2",
      "cursor": "#f8f8f2",
      "cursor_text": "#272822",
      "selection_bg": "#f8f8f2",
      "selection_fg": "#272822",
      "normal": {
        "black": "#272822",
        "red": "#f92672",
        "green": "#a6e22e",
        "yellow": "#f4bf75",
        "blue": "#66d9ef",
        "magenta": "#ae81ff",
        "cyan": "#a1efe4",
        "white": "#f8f8f2"
      },
      "bright": {
        "black": "#75715e",
        "red": "#f92672",
        "green": "#a6e22e",
        "yellow": "#f4bf75",
        "blue": "#66d9ef",
        "magenta": "#ae81ff",
        "cyan": "#a1efe4",
        "white": "#f9f8f5"
      }
    }
  },
  "light": {
    "primary": "#a6e22e",
    "on_primary": "#f8f8f2",
    "secondary": "#66d9ef",
    "on_secondary": "#f8f8f2",
    "tertiary": "#f92672",
    "on_tertiary": "#f8f8f2",
    "error": "#f92672",
    "on_error": "#f8f8f2",
    "surface": "#f8f8f2",
    "on_surface": "#272822",
    "surface_container": "#e6e1dc",
    "on_surface_variant": "#272822",
    "outline_variant": "#a6e22e",
    "shadow": "#d8d8d8",
    "hover": "#e6e1dc",
    "on_hover": "#272822",
    "terminal": {
      "background": "#f8f8f2",
      "foreground": "#272822",
      "cursor": "#272822",
      "cursor_text": "#f8f8f2",
      "selection_bg": "#272822",
      "selection_fg": "#f8f8f2",
      "normal": {
        "black": "#f8f8f2",
        "red": "#f92672",
        "green": "#a6e22e",
        "yellow": "#f4bf75",
        "blue": "#66d9ef",
        "magenta": "#ae81ff",
        "cyan": "#a1efe4",
        "white": "#272822"
      },
      "bright": {
        "black": "#d8d8d2",
        "red": "#f92672",
        "green": "#a6e22e",
        "yellow": "#f4bf75",
        "blue": "#66d9ef",
        "magenta": "#ae81ff",
        "cyan": "#a1efe4",
        "white": "#1e1e19"
      }
    }
  }
}
```

Required JSON keys, exactly as the parser spells them (`kFixedPaletteJsonKeys`, `kVersion1RoleKeys`,
`kVersion1TerminalKeys` in `src/theme/fixed_palette_json.cpp`): mode objects `dark` (required) and `light` (optional,
cloned from `dark` when missing); inside each, the 16 role keys above and a `terminal` object with `foreground`,
`background`, `cursor`, `cursor_text`, `selection_fg`, `selection_bg`, plus `normal`/`bright` objects each carrying
`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`. No container/`scrim` keys appear anywhere in
the format — those are derived.

Other format rules:

- `version` is the palette format. `2` is current; a file **without** `version` is read as format `1`, which used
  `m`-prefixed camelCase keys (`mOnPrimary`, `mSurfaceVariant`, `mOutline`, terminal `selectionFg`). A version newer
  than the binary's is rejected with a warning. Format-1 files and v4 colour schemes keep working.
- Optional top-level `base` names the family (`"Monokai"`, `"Catppuccin"`) and is used only for grouping in the
  palette picker.
- v4 → v5 migration is a copy: `~/.config/noctalia/colorschemes/MyScheme/MyScheme.json` →
  `~/.config/noctalia/palettes/MyScheme.json`.
- The Home Manager module's `programs.noctalia.customPalettes` writes exactly these files as
  `~/.config/noctalia/palettes/<name>.json` (confirmed in `nix/home-module.nix`: `attrsOf (jsonFormat.type | str | path)`).

### 5. Theme IPC

From `https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/` (action names are verbatim; the CLI wraps them as
`noctalia msg <action> ...`):

| action | behaviour |
|---|---|
| `theme-mode-get` | prints the **resolved** mode (`dark`/`light`, including `auto` resolution) |
| `theme-mode-toggle` | switches dark↔light — "same as the bar control **when `[theme].mode` is not auto**" |
| `theme-mode-set dark` | persists `[theme].mode` (accepts `dark`, `light`, `auto`) in `settings.toml` and reloads |
| `color-scheme-get` | prints `<source> <name>`: `builtin Noctalia`, `wallpaper m3-content`, `community Oxocarbon`, `custom MyScheme` |
| `color-scheme-set builtin Noctalia` | persists `[theme].source` plus the matching palette key, then reloads |
| `templates-apply` | re-renders the enabled configured templates for the current palette **without** changing mode and **without** firing shell palette hooks |

Consequence for declarative config: `theme-mode-set` writes to `~/.local/state/noctalia/settings.toml`, which **wins
over** `~/.config/noctalia/*.toml` on load (see Finding 9). A GUI or IPC mode change therefore silently overrides a
declarative `theme.mode` until the state file is cleared or the value is made redundant.

### 6. Template engine: syntax, entries, and how templates are declared

The engine (`https://docs.noctalia.dev/noctalia/v5.6.0/theming/templates/`) renders text from a token map:

- Expressions `{{ ... }}`; blocks `<* for ... *>`, `<* if ... *>`, `<* else *>`, `<* endif *>`, `<* endfor *>`.
  A block tag alone on a line removes the whole line (whitespace-safe templates). **Deliberately not** matugen/Tera
  syntax — `{% %}` templates must be rewritten, and the docs say so explicitly.
- Data: `colors.<token>.<mode>.<format>` with modes `dark`/`light`/`default`, and formats `hex`, `hex_stripped`,
  `rgb`, `rgb_csv`, `rgba`, `hsl`, `hsla`, `red`, `green`, `blue`, `alpha`, `hue`, `saturation`, `lightness`.
- Interpolation: `mode`, `image`, `closest_color`, and (in hooks) `config_dir`, `config_file`.
- Filters: colour (`grayscale`, `invert`, `set_alpha`, `set_lightness`, `set_hue`, `rotate_hue`, `set_saturation`,
  `set_red/green/blue`, `lighten`, `darken`, `saturate`, `desaturate`, `auto_lightness`, `blend`, `harmonize`,
  `to_color`) and string (`replace`, `lower_case`, `camel_case`, `pascal_case`, `snake_case`, `kebab_case`).
- `palettes.<family>.<tone>.<format>` for Material tonal palettes (families `primary`, `secondary`, `tertiary`,
  `error`, `neutral`, `neutral_variant`; any tone 0–100, `_` prefix accepted for matugen compatibility), plus
  `0..10` ranges and `loop.index/first/last`.
- `[config.custom_colors]` expands named colours into M3-style roles (`{name}`, `on_{name}`, `{name}_container`,
  `on_{name}_container`, `{name}_source`, `{name}_value`) with `blend` (default `true`) and per-mode
  `color_dark`/`color_light`. In the main config these live at `[theme.templates.custom_colors]`.

Entry fields (schema: `userTemplateSchema()` in `src/config/schema/config_schema_theme.cpp`; prose in Template
Reference): `enabled`, `input_path`, `input_path_modes = { dark = ..., light = ... }`, `output_path` (string **or
array**), `output_path_dynamic` (shell command whose stdout lines become extra outputs), `colors_to_compare`,
`compare_to`, `pre_hook`, `post_hook`, `post_action`, `index` (processing order), `hook_async` (default `true`),
`requires_path`, and community-only `gtk_extension`.

Hook semantics worth knowing: `pre_hook` always runs synchronously before any output is written; `post_hook` runs
after a successful processing *even when the rendered output was unchanged*; async post hooks from different entries
may overlap (max 4 at a time) unless `hook_async = false`; on shell exit running hooks get 5 s then their process
group is killed. `post_action` is a Noctalia-owned native operation — the documented one is `kde-color-scheme`, which
"merges that generated KDE color scheme into `$XDG_CONFIG_HOME/kdeglobals`, and notifies running KDE applications
over the session bus".

### 7. How templates are applied and undone

Application:

- Templates are re-rendered whenever the resolved theme changes (palette change, `mode` change, wallpaper change for
  wallpaper-sourced themes). A `mode` change re-runs each entry's full hook, e.g. GTK's
  `bash '…/gtk/apply.sh' dark|light`.
- `noctalia msg templates-apply` forces a re-render of enabled templates without changing mode or firing palette hooks.
- Rendering creates parent directories, skips rewriting unchanged files (avoids timestamp churn), and reports failures
  per entry. Commands are available standalone too: `noctalia theme --list-templates`,
  `noctalia theme --builtin-config`, `noctalia theme <image> -c file.toml`, `noctalia theme --theme-json theme.json`.

Undo:

- Disabling a **built-in** template "removes its generated Noctalia theme file and undoes any Noctalia-owned include
  or theme selection that the template added to the application's config"; setting `enable_builtin_templates = false`
  performs that cleanup for every selected built-in template. Each catalog entry ships an `undo_hook` (verified in
  `assets/templates/builtin.toml`, e.g. `undo_hook = "bash '{{ config_dir }}/alacritty/undo.sh'"`).
- Disabling a **community** template (or `enable_community_templates = false`) runs each cached `undo_hook`; failures
  are retried on the next application; templates without an `undo_hook` leave files behind.
- Undo requires the app config to be **writable**: "For declaratively managed configs such as Home Manager symlinks
  into the Nix store, remove the Noctalia include or theme selection from the declarative source."
- Undo is partial by design. Read `assets/templates/gtk/undo-gtk3.sh`: it strips the `@import` line, deletes
  `noctalia.css`, `noctalia-extensions.css` and `noctalia-extensions/` — but **does not** restore
  `org.gnome.desktop.interface gtk-theme` or `color-scheme`. GSettings state written by the apply path survives undo.

### 8. Global vs per-app disabling

- **Global, per catalog:** `[theme.templates] enable_builtin_templates = false` (and the same for
  `enable_community_templates`). Both flags **default to `true`** in v5.6.0 (`TemplatesConfig`,
  `src/config/config_types.h`); what keeps templates from running is the empty id whitelist. Setting the flag to
  `false` also triggers removal of the generated files and includes for every previously selected id, which makes it
  the safer "never touch my configs" statement than an empty `builtin_ids`.
- **Per-app (built-ins):** `builtin_ids` is an **opt-in whitelist** —
  `builtin_ids = []` means no built-in templates are applied at all, and a given template runs only if its id is in
  the array. So "disable one app" = omit its id, and the undo hook then cleans up whatever it had done.
- **Per-app (user templates):** `[theme.templates.user.<id>] enabled = false` keeps an entry defined but inactive.
- **Per-app (community):** `community_ids` plays the same whitelist role.
- There is **no** per-app key for built-ins beyond membership in `builtin_ids`, and no per-entry `enabled` flag in
  the built-in catalog.
- `sync_color_scheme` is outside this system entirely: disabling every template still leaves Noctalia writing
  `prefer-dark`/`prefer-light` unless `sync_color_scheme = false`.

### 9. Config layering (why GUI/IPC writes can defeat declarative config)

From `https://docs.noctalia.dev/noctalia/v5.6.0/configuration/`, load order is: built-in defaults → `$XDG_CONFIG_DIRS/noctalia/`
(usually `/etc/xdg/noctalia/`) → every `*.toml` in `~/.config/noctalia/` (alphabetical, `[include]` support,
`autoload = false` to opt out) → **`~/.local/state/noctalia/settings.toml`**, which wins. Key details:

- `settings.toml` is written by the GUI, setup flows, and "IPC-backed controls" — i.e. by `theme-mode-set`,
  `color-scheme-set`, and friends.
- "If the file is a symbolic link, Noctalia writes through to the link target and keeps the link in place." A
  Home-Manager-managed `settings.toml` symlink would therefore be written *through* — into the store path if it
  points there, which cannot succeed.
- When Settings writes a value equal to the value from lower layers, it removes the redundant key instead of keeping
  an override; otherwise the override persists.
- Files under `~/.config/noctalia/` are never rewritten by migrations; legacy keys are normalized in memory and a
  warning points at file/line/column (`noctalia config validate` lists them).
- The HM module writes **`~/.config/noctalia/config.toml`** (a store symlink, `xdg.configFile."noctalia/config.toml"`)
  and builds it with `checkConfig` → `noctalia config validate <file>` at build time (`nix/home-module.nix`). So the
  declarative layer is safe from mutation but loses to `settings.toml` written by the GUI.

### 10. What templates physically write, and where

Catalog outputs, verbatim from `assets/templates/builtin.toml` at tag `v5.6.0` (21 entries; "generated file" is the
render target, "mutation" is what the hook does to the app's own config):

| id | generated file | hook / mutation of app config |
|---|---|---|
| `alacritty` | `$XDG_CONFIG_HOME/alacritty/themes/noctalia.toml` | `apply.sh` adds `import = [ ... ]` under `[general]` in `~/.config/alacritty/alacritty.toml` (or creates that file) |
| `btop` | `$XDG_CONFIG_HOME/btop/themes/noctalia.theme` | `apply.sh` (selects theme) |
| `cava` | `$XDG_CONFIG_HOME/cava/themes/noctalia` | `apply.sh` |
| `emacs` | dynamic (`output-path.sh`) | `apply.sh` |
| `foot` | `$XDG_CONFIG_HOME/foot/themes/noctalia` | `apply.sh`; skips creating `foot.ini` if one exists elsewhere |
| `ghostty` | `$XDG_CONFIG_HOME/ghostty/themes/noctalia` | `apply.sh` |
| `gtk3` | `$XDG_CONFIG_HOME/gtk-3.0/noctalia.css` | `gtk/apply.sh <mode>`: appends `@import url("noctalia.css");` to `gtk-3.0/gtk.css`, **creates `gtk.css` if absent**, and sets `gtk-theme` to `adw-gtk3` / `adw-gtk3-dark` via `gsettings` (falls back to `dconf`) |
| `gtk4` | `$XDG_CONFIG_HOME/gtk-4.0/noctalia.css` | same script; `hook_async = false` because gtk3/gtk4 share it and it rewrites both `gtk.css` files |
| `helix` | `$XDG_CONFIG_HOME/helix/themes/noctalia.toml` | `apply.sh` |
| `kcolorscheme` | **`$XDG_DATA_HOME/color-schemes/noctalia.colors`** | `post_action = "kde-color-scheme"`: merges the scheme into `$XDG_CONFIG_HOME/kdeglobals` and notifies KDE apps on the session bus |
| `kitty` | `$XDG_CONFIG_HOME/kitty/themes/noctalia.conf` | `apply.sh` |
| `labwc` | `$XDG_CONFIG_HOME/labwc/noctalia.conf` | `apply.sh`; also installs `$XDG_DATA_HOME/themes/noctalia/openbox-3/themerc` |
| `luciole` | `$XDG_CONFIG_HOME/luciole/colors.toml` | — |
| `niri` | dynamic | `apply.sh` adds `include "…/niri/noctalia.kdl"` to `niri/config.kdl` |
| `hyprland` | `$XDG_CONFIG_HOME/hypr/noctalia.lua` **or** `noctalia.conf` (input and output both dynamic) | `apply.sh apply` appends `require("noctalia").apply_theme()` to `hyprland.lua`, or `source = …/noctalia.conf` to `hyprland.conf` |
| `mango` | `$XDG_CONFIG_HOME/mango/noctalia.conf` | `apply.sh` adds `source=` line |
| `qt` | **two** files: `$XDG_CONFIG_HOME/qt5ct/colors/noctalia.conf` and `qt6ct/colors/noctalia.conf` | none — `undo_hook` only deletes them |
| `scroll` | `$XDG_CONFIG_HOME/scroll/noctalia` | `apply.sh` |
| `sway` | `$XDG_CONFIG_HOME/sway/noctalia` | `apply.sh` adds `include` |
| `umbriel` | `$XDG_CONFIG_HOME/umbriel/noctalia.toml` | `apply.sh` appends to `[include.optional].files` |
| `wezterm` | `$XDG_CONFIG_HOME/wezterm/colors/Noctalia.toml` | `apply.sh` |

Plus, independent of templates: `sync_color_scheme` → `org.gnome.desktop.interface color-scheme`.

GTK specifics for this repo:

- What lands in `~/.config` is `gtk-3.0/noctalia.css` and `gtk-4.0/noctalia.css` (a `@define-color` sheet that also
  `@import`s `noctalia-extensions.css`), plus one appended line in each `gtk.css`. `settings.ini` is **not**
  touched by Noctalia; the `gtk-theme` name goes to GSettings/dconf instead.
- If `gtk.css` is a **read-only symlink** (the Home Manager/Nix store pattern), `apply.sh` does not fail — it
  `rm`s the symlink and writes a fresh local file:

  ```
  if [ -L "$gtk_css" ]; then
      resolved=$(readlink -f "$gtk_css")
      if [ -w "$resolved" ]; then target="$resolved"
      else rm "$gtk_css"          # Read-only symlink (e.g. NixOS): convert to a local file
      fi
  fi
  ```

  That silently de-symlinks a declaratively managed file; the next `home-manager switch` then has to fight a
  foreign regular file at that path.

Qt specifics:

- Noctalia only writes *scheme files*. Nothing selects them: the user must set `QT_QPA_PLATFORMTHEME=qt6ct` (or
  `qt5ct`) and pick `noctalia` in qt6ct's "Color scheme" dropdown. Under any other platform theme the files are inert.
- `kcolorscheme` is the KDE-native path: `~/.local/share/color-schemes/noctalia.colors` + a merge into
  `~/.config/kdeglobals`. That merge is a direct rewrite of an app config file Noctalia does not own.

### 11. Interaction with this repo's existing Catppuccin pipeline

The existing pipeline (`nixos/modules/theme.nix`, `nixos/theme-switch.sh`) prebuilds both flavours at build time into
`theme-assets/{dark,light}/`, copies the active one into `~/.local/state/theme/current/`, and points apps at the
runtime copy with `mkOutOfStoreSymlink`. Apps currently covered: Alacritty, Wofi, Fuzzel, Eww, Dunst, Waybar,
Hyprlock, Hyprland (border colours), Hyprpaper, tmux, nvim. GTK/Qt are handled as follows: `theme-switch` writes
`~/.config/gtk-{3,4}.0/settings.ini` (`gtk-theme-name=adw-gtk3[-dark]`, `gtk-application-prefer-dark-theme`) and does
`dconf write` on both `color-scheme` and `gtk-theme`; Qt is delegated to `QT_QPA_PLATFORMTHEME=xdgdesktopportal` with
Breeze schemes (`pkgs.kdePackages.breeze`), i.e. **no qt5ct/qt6ct and no `kdeglobals`**.

Collision analysis:

1. **Alacritty — active corruption risk.** `~/.config/alacritty/alacritty.toml` is
   `config.lib.file.mkOutOfStoreSymlink ../.config/alacritty/alacritty.toml`, i.e. a symlink into this git checkout.
   Noctalia's `alacritty/apply.sh` treats an existing file as editable and writes through it (`cat "$tmp" > "$target"`),
   so enabling the built-in `alacritty` template would **rewrite a tracked file in the dotfiles repo** with an added
   `[general] import`. `undo.sh` is the only thing that removes it again.
2. **GTK — two competing authors.** Noctalia appends to `gtk.css` and writes `gtk-theme` via GSettings/dconf;
   `theme-switch` writes `settings.ini` and writes the same two dconf keys (`color-scheme`, `gtk-theme`). Because
   both pick `adw-gtk3`/`adw-gtk3-dark` they agree on the theme *name*, but they disagree on the *trigger*: whichever
   runs last wins, and Noctalia only re-writes on a Noctalia theme change, so a `theme-switch` toggle followed by a
   Noctalia startup can flip `color-scheme` back. `gtk.css` does not currently exist, so enabling the GTK template
   would newly create it (a file this repo never managed) — the least destructive GTK outcome available.
3. **Qt — inert today, dangerous if adopted.** With `QT_QPA_PLATFORMTHEME=xdgdesktopportal`, both the `qt` scheme
   files and `kcolorscheme`'s `kdeglobals` merge are dead weight; switching to `qt6ct` to make them work would mean
   replacing the Breeze/portal path wholesale.
4. **Hyprland — config mutation.** `apply.sh` appends `require("noctalia").apply_theme()` to `hypr/hyprland.lua`
   (the repo renders `hyprland.lua` content into `~/.local/state/theme/current/hyprland.lua` and `dofile`s it), so
   the Hyprland built-in would edit an app config the pipeline owns — with the extra caveat that the appended require
   only works if the `noctalia` Lua module is resolvable from Hyprland's Lua path.
5. **Apps with no built-in template.** Waybar, Eww, Wofi, Dunst, Hyprlock, Hyprpaper have no built-in entry in
   `builtin.toml`. Grepping the community catalog
   (`https://api.github.com/repos/noctalia-dev/community-templates/contents`, listing fetched 2026-11-25) shows
   `fuzzel`, `rofi`, `walker`, `thunar`, `tmux`, `zed`, `neovim`, `discord`, `pywalfox` and many more, but **no
   `waybar`, `wofi`, `dunst`, `eww`, `hyprlock` or `hyprpaper` directories** — those would stay on the existing
   pipeline even with templates fully enabled.
6. **Palette-level duplication.** `source = "builtin"` + `builtin = "Catppuccin"` reproduces the repo's
   Mocha/Latte intent with *different* hexes for `on_surface_variant`, `outline_variant`, `hover` and the terminal
   ANSI set (Finding 3). Running both is possible (Noctalia themes only its own UI if every template is off), but
   produces two subtly different "Catppuccin" palettes on screen.
7. **Precedence trap.** HM writes `~/.config/noctalia/config.toml`, but the GUI/IPC writes
   `~/.local/state/noctalia/settings.toml`, which loads last and wins. `theme-mode-toggle` is documented as acting
   "when `[theme].mode` is not auto" — under `mode = "auto"` it is not the switch you want — while
   `theme-mode-set dark` persists a `[theme].mode` override that beats the declarative file until the state file is
   cleared or the value happens to equal the lower layer's (Noctalia drops redundant keys only in that case).

Lowest-risk migration shape, given the above: pin `enable_builtin_templates = false` and
`enable_community_templates = false` explicitly (they default to `true`, so this is a real statement, not a no-op),
set `theme.mode` declaratively, consider
`sync_color_scheme = false` while `theme-switch` remains the owner of `color-scheme`, and drive Noctalia's own mode
through `theme-mode-set`/`theme-mode-toggle` only if the state-file override is acceptable (or if
`~/.local/state/noctalia/settings.toml` is deleted/ignored on switch).

## Gaps, uncertainties, and things to verify against the installed binary

- **Not verified by execution.** No `noctalia` binary was built or run here: `noctalia theme --list-templates`,
  `noctalia config validate`, and the actual set of built-in template ids on the packaged 5.6.0 could not be captured.
  The catalog above is read from `assets/templates/builtin.toml` at tag `v5.6.0`, which is what the package ships
  (`noctalia theme --builtin-config` reads `assets/templates/builtin.toml`).
- **`terminal` required-ness** is inferred from `parsePaletteFile` returning `nullopt` when a mode lacks a `terminal`
  object. The docs never say this; a real run with a terminal-less palette would settle it.
- **What a missing role key resolves to** (`Color{}` in `readColorField`) is a code-level default whose visual result
  (transparent vs black) was not verified.
- The doc pairs `surface_container` with `on_surface_variant` as the "16 roles" — the source's `kVersion1RoleKeys`
  array confirms exactly those 16 names, but I did not confirm whether the *light* variant is derived from dark when
  `light` is present but partial.
- Whether the Hyprland Lua `require("noctalia")` resolves without extra setup (module path) was not verified.
- Community template ids were enumerated from the repo listing, not from a running `Browse Templates` catalog; ids
  may differ from directory names.

## Conclusions

- Theming is cleanly separable: palette selection (safe, declarative) vs. template rendering (invasive, hook-driven,
  writes GSettings and app configs). A migration can adopt the palette and refuse the templates.
- "Catppuccin" in Noctalia is Mocha/Latte with a hand-tuned role mapping; expect small but visible differences from
  the repo's own Catppuccin tables, notably `on_surface_variant`, `outline_variant`, `hover`, and terminal ANSI.
- The two hard blockers for this repo are the **Alacritty hook** (writes through a symlink into the git checkout) and
  the **GTK hook** (creates/edits `gtk.css` and writes `gtk-theme`/`color-scheme`), followed by the **Hyprland hook**
  (appends a `require` to `hyprland.lua`). Qt is currently inert under `xdgdesktopportal`.
- Disabling is genuinely available at two granularities — `enable_builtin_templates = false` for everything, or
  omitting an id from `builtin_ids` for one app — and undo hooks exist, but undo does not restore GSettings state and
  requires writable app configs.
- `settings.toml` beating `~/.config/noctalia/*.toml` is the systemic hazard for a Home-Manager-managed setup: any
  GUI or IPC write becomes a persistent override that a rebuild will not clear.

## Source Evaluation

1. **Official docs, version-pinned** — `theming/`, `theming/palette/`, `theming/app-theming/`, `theming/templates/`,
   `ipc/media-and-ui/`, `configuration/`, `templates/official/gtk-qt/` under `https://docs.noctalia.dev/noctalia/v5.6.0/`.
   Primary and authoritative for intended behaviour and key names; occasionally loose about validation (see the
   `terminal` requirement), and prose-heavy where a schema would be clearer. All quoted claims above were read from
   the fetched pages, not from search snippets.
2. **`noctalia-dev/noctalia` source at tag `v5.6.0`** — `assets/templates/builtin.toml` (catalog + output paths +
   hooks), `assets/templates/gtk/apply.sh` and `undo-gtk3.sh`, `alacritty/apply.sh`, `hyprland/apply.sh`,
   `qt/qtct.conf`, `src/theme/builtin_palettes.cpp` (Catppuccin hexes), `src/theme/fixed_palette_json.cpp` (palette
   JSON validation), `src/config/schema/config_schema_theme.cpp` (exact key names and defaults), `nix/home-module.nix`
   (what the HM module writes). Strongest evidence class here — it is the shipped artefact, not a description of it.
3. **`noctalia-dev/community-templates` directory listing** via the GitHub contents API — used only for the negative
   claim that waybar/wofi/dunst/eww/hyprlock/hyprpaper templates do not exist. Self-reported by the project; a
   community repo, so tarball freshness is not guaranteed.
4. **This repo** — `nixos/modules/theme.nix`, `nixos/theme-switch.sh`, `nixos/home.nix` (Alacritty symlink). Not an
   external source, but the only evidence for the "would fight the existing pipeline" conclusions; treated as fact
   about the current system, with the caveat that these files may change after this report.

Weakest link: everything about *runtime* behaviour of the packaged 5.6.0 binary (actual template ids, palette
fallbacks, hook successes on a Nix-managed tree) rests on source and docs rather than execution.

## Bibliography

- Noctalia docs — Theme: `https://docs.noctalia.dev/noctalia/v5.6.0/theming/`
- Noctalia docs — Palette: `https://docs.noctalia.dev/noctalia/v5.6.0/theming/palette/`
- Noctalia docs — App Theming: `https://docs.noctalia.dev/noctalia/v5.6.0/theming/app-theming/`
- Noctalia docs — Template Reference: `https://docs.noctalia.dev/noctalia/v5.6.0/theming/templates/`
- Noctalia docs — IPC / Media & UI: `https://docs.noctalia.dev/noctalia/v5.6.0/ipc/media-and-ui/`
- Noctalia docs — How configuration works: `https://docs.noctalia.dev/noctalia/v5.6.0/configuration/`
- Noctalia docs — GTK and Qt Applications: `https://docs.noctalia.dev/noctalia/v5.6.0/templates/official/gtk-qt/`
- Noctalia docs — NixOS / Home Manager module: `https://docs.noctalia.dev/noctalia/v5.6.0/getting-started/nixos/`
- Source — built-in template catalog: `https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.6.0/assets/templates/builtin.toml`
- Source — GTK apply/undo: `.../assets/templates/gtk/apply.sh`, `.../gtk/undo-gtk3.sh`, `.../gtk/gtk3.css`, `.../gtk/gtk4.css`
- Source — Alacritty apply: `.../assets/templates/alacritty/apply.sh`
- Source — Hyprland apply: `.../assets/templates/hyprland/apply.sh`
- Source — Qt scheme template: `.../assets/templates/qt/qtct.conf`
- Source — built-in palettes: `https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.6.0/src/theme/builtin_palettes.cpp`
- Source — palette JSON parser: `https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.6.0/src/theme/fixed_palette_json.cpp`
- Source — theme config schema: `https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.6.0/src/config/schema/config_schema_theme.cpp`
- Source — Home Manager module: `https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.6.0/nix/home-module.nix`
- Community templates listing: `https://api.github.com/repos/noctalia-dev/community-templates/contents`
- Local — `nixos/modules/theme.nix`, `nixos/theme-switch.sh`, `nixos/home.nix` (in this worktree)
