# Noctalia as the notification layer

Noctalia 5.6.0 replaces dunst as the Wayland notification daemon
(`org.freedesktop.Notifications`) and supplies two surfaces: desktop toasts and the
Control Center's **Notifications** tab. Nothing else changes owner. The branch is
`agent-n/noctalia-notifications`; it is built against pinned nixpkgs `93a9ed0a8660`
and Hyprland 0.57.2.

Status: PR [#32](https://github.com/John2143/dotfiles/pull/32) (pushed 2026-11-26, rebased
on `master`). It is one of three parallel comparison branches — `agent-q/quickshell` (custom
Quickshell) and `noctalia-full-shell` (full Noctalia shell replacing Waybar) live in their own
worktrees — so this branch exists to be evaluated against them before anything merges.

Noctalia is capable of being a full desktop shell (bar, dock, wallpaper, lock screen,
clipboard, OSD, widgets). Every one of those is disabled here, because each already has
an owner on these hosts and two owners means two writers to the same surface.

```sh
SUPER+SHIFT+N              # open the Control Center on the Notifications tab
SUPER+CTRL+SHIFT+N         # toggle Do Not Disturb
theme-switch toggle        # still the light/dark switch; Noctalia follows it
notify-send "hi" "there"   # unchanged client path
```

## Scope

| Kept as-is | Owner |
|---|---|
| top bar, workspaces, clock, every status module | waybar (`nixos/modules/waybar.nix`) |
| desktop widgets, hello panel | eww (`nixos/modules/eww.nix`) |
| lock screen, manual-only policy | hyprlock (`nixos/modules/theme.nix`) |
| wallpaper | hyprpaper, themed unit in `nixos/modules/theme.nix` |
| clipboard history | cliphist + wofi (`SUPER+V`) |
| launcher, menus | wofi / fuzzel |
| night colour | gammastep |
| PolicyKit dialogs | lxqt-policykit-agent (autostarted at `nixos/home.nix:577`) |
| light/dark palette, every rendered app config | `theme-switch` (`nixos/theme-switch.sh`) |

What Noctalia adds on top of dunst: a persistent, encrypted notification history that
survives dismissals, grouped by app, browsable in a panel that is also reachable with a
keybind.

## Layout

| Path | Role |
|---|---|
| `nixos/modules/noctalia-notifications.nix` | options (`enable`, `storageKeyFile`, `historyRetentionHours`), `noctalia-sync-settings` `ExecStartPre`, the declarative `config.toml` baseline, the Catppuccin palette JSON, dunst + swaync exclusivity assertions, the Hyprland layer rule, the unit stop timeout |
| `nixos/modules/theme.nix` | `myTheme.palettes` (the single palette source), `theme-switch`'s `runtimeInputs` now include the Noctalia package; the dunst render and theme drop-in are gone |
| `nixos/theme-switch.sh` | `apply` calls `noctalia msg theme-mode-set "$mode"` where it used to call `dunstctl reload` |
| `nixos/home.nix` | module import, the two notification binds, `services.noctalia-notifications.enable = true`, removal of the `dunst/dunstrc` symlink and the dunst unit timeout |
| `.config/juush.bash` | switched line 87 from `dunstify` to `notify-send` (matching line 90; `pkgs.dunst` is no longer on interactive `PATH`) |
| `.config/dunst/dunstrc` | historical reference only — no longer linked into `~/.config` |
| `.config/screenrec.sh` | unchanged; still drives `dunstify` (via its own `runtimeInputs`) as a plain D-Bus client |
| `docs/noctalia-notifications.md` | this file |

## Architecture and decision log

### One owner per surface

Noctalia's own defaults have most of these **on** (`noctalia config export full`), so
each has to be turned off explicitly. A key that is merely absent from our
`config.toml` falls back to the upstream default, not to "off".

| Subsystem | Default | Here | Why |
|---|---|---|---|
| `bar.default` | `enabled = true` | off | Waybar owns the bar; a second bar claims the same layer edges |
| `lockscreen` (`enabled`, `lock_before_suspend`) | both `true` | both off | `nixos/home.nix:699-702` locks manually only, deliberately (no idle lock, no DPMS listener). `lock_before_suspend` would add a second, suspend-triggered lock path |
| `wallpaper` | `true` | off | hyprpaper is started by `theme.nix` with the themed config; Noctalia would repaint over it |
| `desktop_widgets` | `true` | off | eww owns the desktop surface |
| `osd` | `true` | off | Noctalia would only show it for its own volume/brightness commands; the keys call `pamixer` directly, and voxtype already owns a native OSD at bottom-centre |
| `weather` | `true` | off | waybar's `custom/weather` |
| `system.monitor` | `true` | off | waybar's CPU/memory/temperature modules |
| `calendar` | false | off (pinned) | waybar's clock calendar; pinned so an upgrade that flips the default cannot enable it |
| `dock` | false | off (pinned) | Unused layer surface on every output |
| `nightlight` | false | off (pinned) | gammastep |
| `hot_corners` | false | off (pinned) | Nothing here uses corner triggers |
| `shell.clipboard_enabled` | `true` | off | cliphist + wofi already own history and `SUPER+V` |
| `shell.polkit_agent` | false | off (pinned) | `lxqt-policykit-agent` is the session's agent |
| `shell.setup_wizard_enabled` | `true` | off | Nothing to configure at first start; a wizard would rewrite `config.toml` |
| `shell.telemetry_enabled`, `screen_time_enabled`, `external_ip_enabled` | false | off (pinned) | No telemetry, no screen-time DB, no external IP lookup |
| `shell.offline_mode` | false | `true` | No network calls for weather/wallpaper/marketplace |
| `theme.templates.*` | both `true` | both off | See below — a template would append to the Hyprland config, which is a read-only HM symlink |
| `plugins.auto_update` | `"all"` | `"none"` | Updates would rewrite the store-provided plugin set at runtime; valid enum: `all`, `official`, `none` |
| `plugins.enabled`, `plugins.source` | `[]`, default git repos (`official`, `community`) | `[]`, `[]` | No plugins and no upstream git plugin repos (`shell.offline_mode = true` only blocks HTTP, not git fetches; explicit `source = []` stops Noctalia from seeding default repos) |
| `control_center` other tabs | visible | hidden (except Home) | The panel exists only to show notifications: `sidebar = "compact"`, `width = 600`, `show_session_button = false`, and `hidden_tabs` hides media, audio, monitor, system, network, bluetooth, weather, calendar, screen-time and power (Noctalia 5.6.0 does not allow hiding the Home tab) |

The Control Center is `floating` at `center` on the `overlay` layer
(`shell.panel.control_center_placement/position/floating_layer`). With the bar off there
is nothing to anchor a docked panel to, and the panel must not reserve layout space.

### Palettes: one source, 16 roles

`nixos/modules/theme.nix` now exposes `myTheme.palettes` — a read-only option holding
the two Catppuccin attr sets (dark = Mocha, light = Latte, bare 6-hex strings). Noctalia
does not carry its own copy of the hex values; `paletteFor` in the module maps them onto
the 16 Material 3 role names Noctalia's palette format expects:

| Noctalia role | Catppuccin key |
|---|---|
| `primary` / `on_primary` | `mauve` / `base` |
| `secondary` / `on_secondary` | `teal` / `base` |
| `tertiary` / `on_tertiary` | `green` / `base` |
| `error` / `on_error` | `red` / `base` |
| `surface` | `base` |
| `on_surface` | `text` |
| `surface_container` | `surface0` |
| `on_surface_variant` | `subtext0` |
| `outline_variant` | `surface1` |
| `shadow` | `crust` |
| `hover` / `on_hover` | `surface0` / `text` |

The palette is exported as format version 2 with `base = "Catppuccin"`, so the picker
groups it with the built-in Catppuccin schemes. There is deliberately **no `terminal`
block**: alacritty is themed by `theme.nix` through its own import, and templates are
off.

Templates must stay off. Noctalia's Hyprland template (`share/noctalia/assets/templates/hyprland/apply.sh`)
appends `require("noctalia").apply_theme()` to `~/.config/hypr/hyprland.lua`, and that
path is a home-manager store symlink — the write fails, and if it ever succeeded it
would give Noctalia and `theme.nix` two writers for one file.

`theme.mode` defaults to `dark` in `config.toml` (`source = "custom"`,
`custom_palette = "Catppuccin"`), while `theme-switch` remains the source of truth:
`noctalia-sync-settings` (`ExecStartPre`) seeds `~/.local/state/noctalia/settings.toml`
from `~/.local/state/theme/mode` before `noctalia` launches, and `theme-switch` updates
a running daemon live with `noctalia msg theme-mode-set <mode>`.

### Notification baseline

The toast surface loosely mirrors the old dunst geometry (width widens from 300 to 360 px):

| Setting | Value | Was |
|---|---|---|
| `position` | `top_right` | `origin = top-right` |
| `offset_x` / `offset_y` | `10` / `40` | `offset = 10x40` |
| `width` | `360` | `width = 300` (fixed) |
| `border` / `border_width` | `true` / `2` | `frame_width = 2` |
| `max_visible` | `20` | `notification_limit = 20` |
| `follow_focused_output` | `true` | `follow = keyboard` |
| `show_app_name`, `show_actions`, `show_progress_bar` | `true` | dunst defaults |
| `newest_on_edge`, `collapse_on_dismiss`, `group_by_app` | `true` | dunst sorted by urgency (`sort = yes`) with no app grouping and no collapsed dismissals |
| `keep_dismissed_in_history` | `true` | dunst kept history except where a rule set `history_ignore` |
| `background_opacity` | `0.97` | — |
| `layer` | `overlay` | dunst default (`overlay`; keeps alerts visible over fullscreen windows) |

### Filter chain

First match wins, so the order is load-bearing. Both `filter_order` and `filter` are
derived from a single ordered `filterDefs` list so they cannot drift:

| Order | Filter | Effect | Why here |
|---|---|---|---|
| 1 | `base-stations` | `match_content = "^LHB-"`: `show_toast = false`, `save_history = false` | Blueman announces every base-station connect/disconnect. Must precede the catch-all or it gets toasted |
| 2 | `ups` | `match_content = "^UPS$"`: `bypass_dnd = true`, `override_duration = 0` | `nixos/modules/nut-ups.nix` power/battery alerts break through DND and stay sticky until dismissed |
| 3 | `babysit` | `match_content = "^BABYSIT:"`: `bypass_dnd = true`, `override_duration = 0` | Blocking alerts from `.claude/skills/babysit/SKILL.md` break through DND and stay sticky |
| 4 | `silent-default` | `match_content = ".*"`: toast + history | Catch-all |

Every filter sets `play_sound = false`. Noctalia's per-filter default is `true`, so
without it the catch-all would ping on every notification — dunst never did, because it
had no sound configured.

**Do not set `allowed_urgencies` on a catch-all filter.** In Noctalia 5.6.0
(`src/notification/notification_filter.cpp`, `notification_manager.cpp:846-852`),
`resolveNotificationFilter()` selects the first filter matching `match`/`match_content`
without checking urgency, and `NotificationManager` then suppresses any non-matching
urgency with `fullySuppress = true` (no fallthrough to later filters). A catch-all with
`allowed_urgencies = ["critical"]` silently drops all `low` and `normal` notifications
even when DND is off. Because Noctalia also applies a uniform 6 s default timeout
(`kDefaultNotificationTimeout = 6000`) regardless of urgency, DND-bypass and sticky
duration are scoped to explicit sender filters (`ups`, `babysit`); ad-hoc critical
callers (`notify-send -u critical`) auto-dismiss after 6 s unless they pass `-t 0` or
are added as a sender filter.

### Daemon exclusivity: assertion, not `mkForce`

`services.noctalia-notifications` asserts both `!config.services.dunst.enable` and
`!config.services.swaync.enable`. `mkForce` would have "worked" too, but it would
silently discard an explicit enable somewhere else in the tree, and the resulting
failure (two processes claiming `org.freedesktop.Notifications`, the second one losing
the name) appears at runtime as missing notifications. The assertions fail the build
with a sentence that names the cause. `nixos/home.nix` therefore no longer sets
`services.dunst` at all.

The daemon enforces single-instance itself with `flock` on
`$XDG_RUNTIME_DIR/noctalia-$WAYLAND_DISPLAY.lock`, so a stray manual start exits instead
of fighting the unit.

### Storage key: keyring by default, file optional

`storageKeyFile` defaults to `null`, which renders
`storage.key_source = "secret-service"`. A logged-in session has gnome-keyring
unlocked, so history works with no provisioning. Set it to
`/run/agenix/noctalia-notifications-key` to read a 64-character lowercase hex key from a
file instead, which also works while the keyring is locked. See
[the agenix recipe](#persistent-encrypted-history-optional).

### `settings.toml` beats `config.toml`

Noctalia merges, in order: built-in defaults → `/etc/xdg` → `~/.config/noctalia/*.toml`
→ `~/.local/state/noctalia/settings.toml`. The last one wins, and it is written by the
running shell.

Our declarative file lands at `~/.config/noctalia/config.toml`, while `theme-switch`
persists `[theme].mode` into `settings.toml` at runtime via
`noctalia msg theme-mode-set`. Pointing `settings.toml` at `/dev/null` would break live
mode toggling; leaving it unmanaged would both start in `dark` mode on a `light`-mode
boot (because `home.activation.themeRefresh` runs before `noctalia.service` starts) and
let accidental Settings GUI or CLI edits override pinned keys (like `lockscreen.*` or
`plugins.*`) across restarts.

`systemd.user.services.noctalia.Service.ExecStartPre` therefore runs
`noctalia-sync-settings`, which reads `~/.local/state/theme/mode` (defaulting to `dark`)
and atomically rewrites `~/.local/state/noctalia/settings.toml` (mode `0600`) to contain
only `[theme]\nmode = "<mode>"` before Noctalia launches. Every daemon start and HM
rebuild (`X-Restart-Triggers`) boots directly in the active theme and wipes any non-theme
drift.

Upstream Home Manager sets `programs.noctalia.checkConfig = true` by default, which runs
`noctalia config validate` at build time. Note a Noctalia 5.6.0 caveat:
`noctalia config validate` exits non-zero **only on TOML syntax errors**; unknown
sections/keys, wrong types, and invalid enum values print warnings and still exit `0`.
Check the validator's text output for `warning` (and diff `noctalia config export full`)
when editing settings or upgrading Noctalia.

### Hyprland layer rules

One `hl.layer_rule` block matches `^noctalia-(notification|panel)$` with `no_anim = true`,
`blur = true`, `blur_popups = true`, and `ignore_alpha = 0.5`. It is declared via
`wayland.windowManager.hyprland.settings.layer_rule`, which the HM module turns into
`hl.layer_rule(...)` in the generated `hyprland.lua`.

Note that the pre-existing layer rule at `nixos/home.nix:370` (`"blur,waybar"`,
`"ignorezero,waybar"`) sits inside `settings.config`, i.e. it is emitted as
`hl.config({ layerrule = [...] })` — a config key Hyprland 0.57 does not have, so it is
probably inert. That is pre-existing and unrelated; the new rule uses the correct API.

### No waybar unread-count module

Noctalia exposes no unread-history count: `noctalia msg status` returns only
`barVisible / panelOpen / activePanelId / locked`, and `notification-dnd-status` returns
`on|off`. The count lives inside the process. There is an undocumented D-Bus extension,
`org.freedesktop.Notifications.GetNotifications`, which returns the *active toasts*
(`aa{sv}`) — not dismissed-but-unread history — and only on poll, with no change signal:

```sh
busctl --user --json=short call org.freedesktop.Notifications \
  /org/freedesktop/Notifications org.freedesktop.Notifications GetNotifications
```

Polling that from waybar would be busy-work for a number that is wrong anyway, so no
waybar module was added. Opening history is keybind-driven.

### `pkgs.dunst` is still installed

`screenrec` calls `dunstify` (`-a`, `-p`, `-t`, `-i`, `-r`, `-h`) to morph one toast
through its stages, and keeps `pkgs.dunst` in its `runtimeInputs`. `dunstify` is an
ordinary D-Bus client — it works against any server that implements
`org.freedesktop.Notifications` — so nothing there changed. `.config/dunst/dunstrc` is
retained as the reference for the old behaviour (geometry, mouse binds, markup); it is no
longer symlinked into `~/.config`.

## History store

Facts that matter when debugging the Notifications tab:

- Encrypted at rest in `~/.local/state/noctalia/notification_history.enc` (mode `0600`),
  with AEAD-encrypted 96 px WebP/RGBA previews (`.webp.enc`/`.rgba.enc`) in
  `notification_history_assets/` (mode `0700`).
- Hard cap of **100 entries**. Upstream constant
  `kNotificationHistoryMaxEntries = 100` (`src/notification/notification_history_store.h:12`);
  not documented in the user docs.
- `history_retention_hours` defaults to `0` = keep indefinitely, capped at those 100.
  Exposed as `services.noctalia-notifications.historyRetentionHours` (`0`–`8760`).
- If the key is missing or the keyring is locked: notifications still work, nothing is
  written in plaintext, the existing encrypted file is preserved, and new entries merge
  on unlock/retry.
- Opening the Notifications tab marks history seen and clears the unread marker.
- Dismissing a toast keeps it in history and unread (`keep_dismissed_in_history = true`).
- `Urgency::Low` and transient notifications are unconditionally excluded from history
  (`shouldTrackHistory()` in `src/notification/notification_manager.cpp:78-80`).
- **DND is not persisted.** It is a bool in `NotificationManager`; after a restart or
  reboot DND is off again.

## Keybinds and IPC

| Keybind | Command |
|---|---|
| `SUPER+SHIFT+N` | `noctalia msg panel-toggle control-center notifications` |
| `SUPER+CTRL+SHIFT+N` | `noctalia msg notification-dnd-toggle` |

Both are emitted as `hl.bind` lines in the generated `hyprland.lua`.

Useful commands (all from `noctalia msg`):

```sh
noctalia msg panel-toggle control-center notifications   # open/close history
noctalia msg notification-clear-active                   # close every toast (old right-click close_all)
noctalia msg notification-clear-history                  # wipe stored history
noctalia msg notification-dnd-status                     # on|off
noctalia msg notification-dnd-set on                     # or off
noctalia msg notification-invoke-latest                  # default action of newest toast
noctalia msg notification-show "summary" "body"          # Noctalia's own test notification
noctalia msg theme-mode-set dark|light                   # what theme-switch calls
noctalia msg theme-mode-get                              # resolved mode
noctalia msg status                                      # JSON: barVisible/panelOpen/activePanelId/locked
noctalia config validate                                 # build-time check, also runnable by hand
noctalia config export full                              # dump effective config incl. defaults
```

## Parity with dunst, and what regressed

Ported without visible change:

| dunst | Noctalia |
|---|---|
| top-right, `offset = 10x40`, 2 px frame, `overlay` layer (300 -> 360 px) | `notification.position/offset_*/border_width/layer/width` |
| `follow = keyboard` | `follow_focused_output = true` |
| `notification_limit = 20` | `max_visible = 20` |
| `[base-station-connect] skip_display/history_ignore` | `base-stations` filter |
| urgency-silent notifications | `silent-default` + `play_sound = false` |
| UPS and babysit alerts breaking DND + staying sticky | `ups` (`^UPS$`) and `babysit` (`^BABYSIT:`) filters (`bypass_dnd = true`, `override_duration = 0`) |
| actions (`-A key=Label`) | `show_actions = true` |
| `-i`/`string:image-path:` icons | supported |
| `dunstify` (`screenrec`), `notify-send` (`juush`) | `screenrec` unchanged (`dunstify` D-Bus client); `.config/juush.bash:87` switched to `notify-send` |

Regressions, in rough order of how much they matter:

| Lost | Consequence |
|---|---|
| generic `notify-send -u critical` timeout & DND | Noctalia defaults to 6 s regardless of urgency and cannot filter-select by urgency without dropping lower urgencies; known critical senders (`ups`, `babysit`) have explicit filters, while ad-hoc callers must pass `-t 0` for sticky toasts |
| `x-dunst-stack-tag:hass-$1` (`nixos/modules/keybind.nix:18`) | Rapid HASS macro presses no longer coalesce into one toast; each press adds a toast and a history entry. Standard `replaces_id` is the only coalescing mechanism Noctalia has |
| markup (`markup = full`, `format = "<b>%s</b>\n%b"`) | Noctalia does not advertise `body-markup`; standard HTML tags are stripped (`<br>` becomes a newline), so app-formatted bodies lose bold/links |
| `screenrec`'s `-h int:value:<pct>` (`.config/screenrec.sh:25-34`) | No percentage bar; Noctalia's progress bar is the timeout countdown. `-r <id>` maps to plain `replaces_id` and should still morph one toast, but was not exercised live here |
| `mouse_middle_click = open_url, close_current`, `dmenu = fuzzel --dmenu` | No URL/action menu on middle click |
| `mouse_right_click = close_all` | Right click dismisses one toast; use `noctalia msg notification-clear-active` for all |
| per-urgency colours (`theme.nix` had peach critical background, mantle low) | Noctalia uses palette roles plus a red critical border; urgency no longer changes the background |
| DND survives nothing | See history store: DND resets on restart |
| unlimited history | Hard cap of 100 entries (`Urgency::Low` and transient notifications excluded) |

## Persistent encrypted history (optional)

`storageKeyFile = null` is enough on a normal desktop session. Provision the agenix
secret only if history must also work while gnome-keyring is locked (or if you do not
want the key in the login keyring at all). Six steps, from the repo root:

The commands below use POSIX/bash syntax (from fish, run steps 1 and 3 inside `bash` or
translate `KEY=...` / `unset KEY` to `set -l KEY ...` / `set -e KEY`):

```sh
# 1. generate a 64-character lowercase hex key (32 bytes)
KEY=$(openssl rand -hex 32)

# 2. add it to secrets/agenix-rules.nix
#    "noctalia-notifications-key.age".publicKeys = [arch office];

# 3. encrypt it (TMPDIR=/dev/shm keeps the plaintext temp file off the root fs)
(cd secrets && printf '%s' "$KEY" | TMPDIR=/dev/shm agenix -e noctalia-notifications-key.age -i ~/.ssh/age)
unset KEY

# 4. declare the secret in nixos/shared-cli-configuration.nix
#    age.secrets."noctalia-notifications-key" =
#      lib.mkIf (builtins.elem config.networking.hostName ["arch" "office"]) {
#        file = ../secrets/noctalia-notifications-key.age;
#        mode = "0400";
#        owner = "john";
#        group = "users";
#      };

# 5. point the module at it — nixos/home.nix, services.noctalia-notifications
#    (gated to hosts that have the agenix secret, so secu stays on secret-service)
#    storageKeyFile = lib.mkIf (builtins.elem compName ["arch" "office"]) "/run/agenix/noctalia-notifications-key";

# 6. git add the .age file and rebuild
```

The file must contain exactly the hex key with no trailing newline (step 3 uses
`printf '%s'`, not `echo`).

**Losing the key loses the history, not the notifications.** A wrong or unreadable key
means the existing `notification_history.enc` cannot be decrypted; it is left in place
and new entries start a fresh store, which also means old entries never merge back. Back
up the `.age` file, and treat rotating the key as a history reset
(`noctalia msg notification-clear-history`).

## Verification performed and post-switch smoke tests

Checked on 2026-11-26 against pinned nixpkgs `93a9ed0a8660`, Noctalia 5.6.0 and Hyprland
0.57.2. No `nixos-rebuild switch` was run and Noctalia was never started, so everything
below is eval/build evidence, not runtime evidence.

| Check | Result |
|---|---|
| `nixosConfigurations.{arch,office,secu}.config.home-manager.users.john.services.noctalia-notifications.enable` | `true` |
| `…services.dunst.enable`, `…services.swaync.enable` (all 3 hosts) | `false`, `false` |
| failing assertions (all 3 hosts) | `0` |
| stale `dunst` `xdg.configFile` entries | `[]` |
| build of `xdg.configFile."noctalia/config.toml".source` (upstream `checkConfig = true`) | succeeded |
| `noctalia config validate` on rendered `config.toml` + `Catppuccin.json` | exact `✓ Config is valid` (0 errors, 0 warnings) |
| `noctalia config export full` | `[notification]` shows `layer = "overlay"`, `filter_order = ["base-stations", "ups", "babysit", "silent-default"]`, `allowed_urgencies = []` on all filters, `bypass_dnd = true` + `override_duration = 0` on `ups`/`babysit`; `[plugins]` shows `source = []` |
| `noctalia-sync-settings` against temp `XDG_STATE_HOME` | strips rogue `[lockscreen]`/`[plugins]` from `settings.toml`, writes mode `0600` `[theme]\nmode = "light"` (or `"dark"` when `theme/mode` is absent); `noctalia config export full` reflects synced mode and keeps `lockscreen.enabled = false` |
| `storageKeyFile.type.check` | rejects `""` and `"relative/path"`, accepts `null` and `"/run/agenix/x"` |
| `noctalia theme --theme-json <Catppuccin-palette.json> --both` | exit `0` |
| `theme-switch` + `noctalia-sync-settings` built through `pkgs.writeShellApplication` | succeeded (ShellCheck) |
| `bash -n .config/juush.bash` + grep `dunstify` | exit `0`, zero `dunstify` matches |
| `alejandra --check nixos/modules/noctalia-notifications.nix nixos/modules/theme.nix` | pass (`nixos/home.nix` is not pre-formatted on HEAD, so its unrelated lines were left untouched) |
| generated `hyprland.lua` | contains both binds (`SUPER + SHIFT + N`, `SUPER + CTRL + SHIFT + N`) and one merged `hl.layer_rule` block |
| `systemd.user.services.noctalia` | `WantedBy`/`After graphical-session.target`, `ExecStartPre = noctalia-sync-settings`, `TimeoutStopSec = 10`, `X-Restart-Triggers` on `noctalia-config.toml` and `Catppuccin-palette.json` |

After switching, run these in the session:

```sh
systemctl --user status noctalia            # active (running), no restart loop
notify-send "smoke" "toast"                 # top-right, 360 px, 2 px border, overlay layer
SUPER+SHIFT+N                               # Control Center opens on Notifications, floating, centred
SUPER+CTRL+SHIFT+N                          # DND toggles; normal toast suppressed, UPS alert breaks through + stays sticky:
notify-send -u critical "UPS" "smoke test"  # exercises ups filter (bypass_dnd + override_duration = 0)
theme-switch toggle                         # toasts/panel follow Latte <-> Mocha
notify-send "test" "LHB-TEST should not appear"   # base-stations filter
screenrec                                   # one toast morphs through the stages; check the progress area
busctl --user --json=short call org.freedesktop.Notifications \
  /org/freedesktop/Notifications org.freedesktop.Notifications GetNotifications
```

Open items specifically not proven here: the bar-less floating Control Center's
appearance, `screenrec`'s `-r` replace behaviour, and history unlock with a locked
keyring.

## Rollback

The clean path is `git revert` on this branch (or simply do not merge it). Flipping the
flag by hand is **not** sufficient, because dunst's support was removed in three places:

1. `services.noctalia-notifications.enable = false;` in `nixos/home.nix`, and restore
   `services.dunst.enable = true;` plus
   `systemd.user.services.dunst.Service.TimeoutStopSec = 10;`
2. restore the two `dunst` symlinks (`dunst/dunstrc` in `home.nix`, the
   `dunstrc.d/50-theme.conf` drop-in in `theme.nix`)
3. restore `dunstConf`, its `render` entry, and `config.services.dunst.package` in
   `theme-switch`'s `runtimeInputs` in `nixos/modules/theme.nix`, and restore
   `dunstctl reload` in `nixos/theme-switch.sh`

## Maintenance

- `settings.toml` drift: `systemctl --user restart noctalia` runs `noctalia-sync-settings`
  (`ExecStartPre`), which rewrites `~/.local/state/noctalia/settings.toml` to only
  `[theme]\nmode = "<mode>"` from `~/.local/state/theme/mode`. Keep the file writable —
  `theme-switch` updates `theme.mode` there live.
- On every Noctalia upgrade, run `noctalia config export full` and diff it against the
  baseline in the module: a subsystem that flips to `enabled = true` upstream is
  **not** disabled by our file, because our `config.toml` only sets keys it knows about.
  Then run `noctalia config validate` and verify **zero warnings** in its output
  (upstream's `checkConfig = true` only fails builds on TOML syntax errors, not schema
  warnings).
- If a palette edit looks ignored, activation runs `theme-switch refresh`, which re-runs
  `noctalia msg theme-mode-set`; a running shell that ignored it can be restarted with
  `systemctl --user restart noctalia`.

## Open questions

Decisions left for the user before merging:

1. **agenix key now or later?** `storageKeyFile = null` works on a normal session; the
   recipe above is only needed for history with a locked keyring.
2. **Waybar DND / active-toast indicator?** Currently nothing in the bar shows DND state;
   it is only visible in the panel. Polling `GetNotifications` is possible but noisy.
3. **`keybind.nix` stack-tag migration:** `hass_notify` still passes
   `string:x-dunst-stack-tag:...`, which Noctalia ignores. Replacing it means tracking a
   notification id and passing `replaces_id` — a change in `hass-macro`'s notification
   helper.
4. **Keep or delete `.config/dunst/dunstrc`?** It is now unreferenced; it is kept as the
   reference for the old behaviour.
5. **Fix the pre-existing `nixos/home.nix:370` `layerrule` block?** It emits a config key
   Hyprland 0.57 does not have; converting it to `settings.layer_rule` is a small,
   separable fix.
