# Quickshell notification centre

Replaces `dunst` on the Hyprland desktops with a Quickshell 0.3.2 notification
daemon (`org.freedesktop.Notifications`) plus a right-anchored history centre.
Toasts keep dunst's geometry and mouse behaviour; history lives in RAM (as it did
under dunst) and is browsed in a 440 px panel instead of fuzzel.

```sh
notify-send -u normal "Summary" "Body"         # ordinary toast
qs ipc -c notifs call notifs toggle            # SUPER+SHIFT+N
qs ipc -c notifs call notifs toggleDnd         # Do Not Disturb on/off
qs ipc -c notifs call notifs isDnd             # prints true|false
qs ipc -c notifs call notifs clearToasts       # hide every toast, keep history
qs ipc -c notifs call theme refresh            # after touching palette.json by hand
```

Design record with evidence and rejected alternatives:
`docs/plans/2026-11-25/quickshell-notifications.md`.

## Layout

| Path | Role |
|---|---|
| `.config/quickshell/notifs/shell.qml` | `ShellRoot`; per-screen `ToastStack`, one `HistoryPanel`, the `notifs` and `theme` `IpcHandler` targets |
| `.config/quickshell/notifs/services/Notifs.qml` | `pragma Singleton`: the single `NotificationServer`, live toasts, RAM-only history, DND, `LHB-*` filter, stack-tag coalescing, D-Bus lifecycle (`expire()` / `dismiss()`) |
| `.config/quickshell/notifs/services/PrefsStore.qml` | persists only `dnd` and `grouped` to `prefs.json`; never writes notification content |
| `.config/quickshell/notifs/services/LiveWatcher.qml` | one per live notification: expiry timer, `replaces_id` change coalescing, hover pause |
| `.config/quickshell/notifs/services/Theme.qml` | `pragma Singleton`: `palette.json` reader, `col()` / `alpha()`, font family and size |
| `.config/quickshell/notifs/components/ToastCard.qml` | one card: urgency colours, icon/image, markup body, progress bar, action buttons, hover pause, mouse parity |
| `.config/quickshell/notifs/components/ToastStack.qml` | top-right overlay `PanelWindow`, 300 px, click-through `Region` mask |
| `.config/quickshell/notifs/components/HistoryPanel.qml` | 440 px right-anchored `PanelWindow`, `HyprlandFocusGrab`, keyboard nav, DND pill, Clear All |
| `.config/quickshell/notifs/components/Pill.qml` | shared 22 px toggle/indicator pill (DND, Grouped/Flat) |
| `.config/quickshell/notifs/components/IconButton.qml` | shared small glyph button (`✕`, per-group clear) |
| `nixos/modules/quickshell-notifs.nix` | HM module owning `custom.notificationDaemon` (`"quickshell"` / `"dunst"`): `programs.quickshell`, unit hardening, layerrules, SUPER+SHIFT+N, and the dunst branch while it is the active daemon |
| `nix/checks/quickshell-notifs.nix` | offline `qmllint` derivation plus Mocha palette parity check against `nixos/modules/theme.nix` |
| `~/.local/state/quickshell-notifs/prefs.json` | only `{ dnd, grouped }`; the directory is created `0700` by activation |
| `nixos/modules/theme.nix` | now also renders `~/.local/state/theme/current/palette.json` |
| `nixos/theme-switch.sh` | adds `qs ipc --any-display -c notifs call theme refresh` after the palette swap |

The `qs` binary comes from the same `programs.quickshell` package that runs the
service, so `qs ipc` always talks to the running version. Because the config is
registered as a named config (`activeConfig = "notifs"`), pass `-c notifs` on
`qs ipc` calls — without `-c`, `qs` defaults to `"default"`.

## IPC surface

Two handler targets, both registered in `shell.qml`.

| Target | Functions |
|---|---|
| `notifs` | `toggle()`, `open()`, `close()`, `toggleDnd()`, `setDnd(enabled)`, `isDnd()`, `count()`, `unread()`, `clearToasts()`, `clearHistory()`, `reload()` |
| `theme` | `refresh()` |

`qs ipc -c notifs show` prints both trees; `qs ipc -c notifs call notifs count`
is a quick liveness check. `unread()` returns the number of new non-transient
history rows added since the panel was last opened; it is an IPC-only counter
(there is no on-screen badge) and stack-tag replacements or duplicate-stack bumps
do not increment it. `SUPER+SHIFT+N` runs
`qs ipc -c notifs call notifs toggle`, and no `hyprctl dispatch` wrapper is
needed because the IPC call is instantaneous and side-effect free.

## Panel keys and mouse

| Input | Effect |
|---|---|
| `SUPER+SHIFT+N` | open/close the history panel |
| `Esc` | close the panel |
| `j` / `↓`, `k` / `↑` | move selection |
| `Enter` | invoke the selected entry's default action (or its first action) when a live notification still has actions; otherwise open the first URL in its text |
| `x` / `Delete` | remove the selected entry from history |
| `d` | toggle Do Not Disturb |
| `g` | toggle Grouped / Flat view |
| `Shift+C` | clear all history |
| left click on a toast | run its default action; with no actions, hide the toast (dunst `mouse_left_click = do_action`) |
| middle click on a toast | search body and summary for the first `http(s)://` URL, open it, then hide the toast |
| right click on a toast | hide every toast, history untouched |
| click outside the panel | close it |

## Parity with the old dunst setup, and what changed

The evidence-backed matrix with rejected alternatives lives in the design record
(`docs/plans/2026-11-25/quickshell-notifications.md`); this is the operator-facing
summary.

| dunst | now |
|---|---|
| `origin = top-right`, `width = 300`, `offset = 10x40`, `gap = 8`, radius 12, frame 2 | identical, `ToastStack.qml` + `ToastCard.qml` |
| `follow = keyboard` | `Hyprland.focusedMonitor` picks the screen that renders the stack |
| `font = JetBrainsMono Nerd Font 11`, `markup = full` | same family and `pointSize: 11`; `bodyMarkupSupported = true`, `Text.StyledText` over a safe tag subset |
| `urgency_low/normal` 10 s, `critical` sticky | 10 000 / 10 000 / 0 ms; `-1` → default, `0` → never auto-hide, `> 0` honoured as client ms |
| expiry closes on D-Bus | `expire()` on timeout, `dismiss()` on hide/evict, so `NotificationClosed` fires at once |
| `progress_bar = true` (`-h int:value:N`) | `progress >= 0` draws the bar; absence of the hint draws nothing |
| `stack_duplicates`, `x-dunst-stack-tag` | matching tag (and app) replaces the live card and its history slot; otherwise identical app+summary+body inside 10 s increments a duplicate counter |
| `[base-station-connect]` `summary = "LHB-*"`, `skip_display`, `history_ignore` | suppressed synchronously in `onNotification` with `dismiss()`: no card, no history row |
| `notification_limit = 20` | same cap, sorted critical → normal → low, newest first within a class |
| `mouse_left/middle/right` | table above |
| `history_length = 20` in memory + fuzzel | 200 entries in RAM (newest kept), browsed in the panel; lost on restart, as under dunst |
| `dunstctl reload` from `theme-switch` | `FileView` watch plus `qs ipc -c notifs call theme refresh` |
| `dunstify` in `screenrec.sh`, `juush.bash` | `notify-send` (`-p`, `-r`, `-h int:value:` all exist in libnotify) |

## Lifecycle and persistence

- **Timeouts.** Each live notification has a `LiveWatcher` owning its expiry
  timer. When it fires the toast is removed and the notification is `expire()`d,
  so the client receives `NotificationClosed` with reason *Expired* immediately;
  `notify-send --wait` and `-A` never hang. The history row stays in RAM with its
  live handle dropped, so it is readable but inert (no action buttons, no image
  handle) until cleared or the daemon restarts.
- **Hiding and eviction.** Left-click with no action, right-click-all,
  `clearToasts`, the 20-toast cap, and the `LHB-*` filter all `dismiss()` (reason
  *Dismissed*) instead of only unmapping the surface. Hidden rows keep their text
  in history.
- **`replaces_id`.** Updating a live notification rebuilds its row (never mutates
  the old object) and restarts the expiry timer with the new timeout. A hovered
  card stays paused and receives the full refreshed timeout when the pointer
  leaves.
- **Watcher cap.** At most 50 live notifications are tracked FIFO; when a 51st
  arrives the oldest is expired and dropped, so a client that never closes its
  notification cannot leak watchers.
- **History is RAM-only.** 200 entries, cleared on restart — the
  same forgetfulness as dunst, and no notification content is ever written to
  disk. Only the `dnd` and `grouped` preferences persist, to
  `~/.local/state/quickshell-notifs/prefs.json` (directory `0700`, created by
  activation). Missing or corrupt JSON boots with DND off and grouped on.
- **Do Not Disturb** suppresses low/normal toast popups but still records history;
  critical bypasses it. The flag survives restarts because it lives in
  `prefs.json`.

## Markup, URLs, and image validation

- **Body markup** is a safe subset: `b`, `i`, `u`, `s`, `small`, `big`, `tt`,
  `br`, and `a` with `href`. Any other tag, and any unexpected attribute, is
  escaped and shown literally.
- **Links.** `<a href>` values, and every URL handed to `openUrl()`, must match
  `^https?://` or `^mailto:` with no control characters; anything else is
  rejected and nothing is spawned. Middle-click auto-detection in body/summary
  only looks for `http(s)://` URLs; `mailto:` works when a client supplies it as
  a link.
- **Icons.** `image://qsimage/` (a live pixmap) is kept verbatim.
  `image://icon/<name>` and bare names go through
  `Quickshell.iconPath(name, true)`, which returns an empty string for a missing
  icon, so a bad name renders nothing instead of the magenta/black checkerboard.
  Names containing `?`, `/`, or `..` are rejected outright, closing the
  `?path=` file-read vector.
- **Local files.** `file://` URLs (and absolute paths given as app icons) are
  accepted only when they resolve under `/tmp/`, `/run/user/`, `/nix/store/`,
  `/usr/share/`, `/run/current-system/sw/share/`, `~/.cache/`, or
  `$XDG_CACHE_HOME`, with no `..` segment and no control bytes.
- **Sizes.** Summary is capped at 512 characters, body at 4096, app name at 128.
  A toast elides its summary to 2 lines and caps the body at 8 lines; a history
  card shows 1 summary line and 4 body lines.

Intentional differences:

- **Wider surface.** History is a 440 px right-anchored panel with an app-grouped
  view (the default) and a flat chronological view; `g` toggles between them and
  the choice is persisted. `d` is reserved for DND. The toast itself stays 300 px.
- **Live vs. inert rows.** A visible toast binds to the live `Notification`
  object, so `replaces_id` (as `screenrec` uses with `notify-send -r`) updates the
  text in place. Rows whose notification has closed are plain records and never
  show action buttons.
- **No `inline-reply` and no `action-icons` in the capability list.** Advertising
  `inline-reply` without a text input makes clients hide their own reply UI
  (observed in dux-shell), and `action-icons` has no consumer here. Both are one
  line each if ever wanted.
- **`x-dunst-stack-tag` is still honoured** even though the daemon is not dunst:
  `nixos/modules/keybind.nix:18` sends `hass-*` `notify-send` calls with that hint,
  and clients keep passing it.
- **Unread counter is IPC-only.** `unread()` counts genuinely new non-transient
  history rows since the panel was last opened; opening the panel zeroes it, and
  there is no on-screen badge.

## Theme integration

`nixos/modules/theme.nix`'s `render` now also emits `palette.json` next to
`waybar.css` (and `dunst.conf` while dunst is the active daemon):

```json
{ "flavor": "dark", "colors": { "base": "#1e1e2e", "red": "#f38ba8", … } }
```

`Theme.qml` reads `~/.local/state/theme/current/palette.json` directly through a
`FileView` with `blockLoading: true` and `watchChanges: true`, and calls
`reload()` in `onFileChanged`. The path is the real state directory, **not** a
`mkOutOfStoreSymlink`, deliberately: `theme-switch` writes the new file and then
`mv -f`s it into place, and `FileView` watches the parent directory as well as the
file, so the atomic rename produces the event that a store symlink would not.

`theme-switch.sh` keeps the dunst reload (`command -v dunstctl` guarded, so the
script still works with the daemon gone) and adds

```sh
timeout 5 qs ipc --any-display -c notifs call theme refresh >/dev/null 2>&1 || true
```

as belt and braces. `col(name)` falls back to the Catppuccin Mocha hex table when
the file is missing, so a first boot before the first `theme-switch refresh` cannot
render an invisible card. `alpha()` goes through `Qt.rgba`, avoiding QML's
`#AARRGGBB` ordering trap.

## Maintenance and upgrades

The flake stays on the nixpkgs pin; `quickshell` comes from
`cache.nixos.org` and costs no compile time there. Quickshell is 0.x, so minor
bumps can break QML APIs. The offline lint gate is what turns that into a build
error instead of a blank panel.

1. `nix build .#checks.x86_64-linux.quickshell-notifs` on the current pin; it must
   pass before you touch anything. The check builds only `quickshell` and
   `qtdeclarative` from cache and runs `qmllint --import=error
   --missing-property=error` over every `.qml` file, with `-I` pointing at Qt's QML
   directory, Quickshell's QML directory, and a synthesized `qs.*` module root so
   `import qs.services` / `import qs.components` resolve.
2. Read the upstream release notes for breaking changes, especially
   `NotificationServer`, `PanelWindow` / `WlrLayershell`, `FileView`, `JsonAdapter`,
   `HyprlandFocusGrab`, `IpcHandler` and `Region`.
3. `nix flake update` (nixpkgs input only; do not add a second quickshell input —
   an out-of-nixpkgs build loses the cache and flips `DISTRIBUTOR`).
4. Re-run the lint gate, then `nix eval` the `arch`, `office`, `secu` and
   `vm-arch` home-manager attributes, then rebuild.
5. If a bump breaks an API you cannot fix immediately, hold back just quickshell in
   the module with `overrideAttrs` rather than pinning the whole flake:

   ```nix
   programs.quickshell.package = pkgs.quickshell.overrideAttrs (o: {
     version = "0.3.2";
     # src + tags keep the old source
   });
   ```

6. Iterate locally without switching:

   ```sh
   systemctl --user stop quickshell
   qs -p ./.config/quickshell/notifs -v      # Ctrl-C to stop, watch the log inline
   ```

   Dunst must be stopped first or both processes will claim
   `org.freedesktop.Notifications`. `qs log -c notifs -t 50 -f` follows the
   daemonised instance's log, and `QS_NO_RELOAD_POPUP=1` (set by the unit) keeps
   the reload toast away.

## First deploy

```sh
cd ~/repos/dotfiles
nixos-rebuild switch --flake .#arch        # or .#office
systemctl --user status quickshell
qs list -c notifs                          # one instance, config "notifs"
qs ipc -c notifs show                      # both handler trees
```

Smoke tests, in order:

```sh
notify-send "hello" "normal toast"                                  # toast appears, 10 s
notify-send -u low "low" "low urgency"                              # same, low colour
notify-send -u critical "critical" "stays until dismissed"           # no timeout
notify-send -h int:value:40 "uploading" "40%"                        # progress bar at 40%
notify-send -h string:x-dunst-stack-tag:t "same slot" "first"
notify-send -h string:x-dunst-stack-tag:t "same slot" "replaced"     # one card, updated text
notify-send "LHB-TEST" "must be swallowed"                          # no card, no history row
notify-send -A "yes=Yes" -A "no=No" "actions" "click to act"        # buttons; -A implies
                                                                    # --wait, so the shell
                                                                    # blocks until you act
screenrec start                                                     # sticky progress card that
                                                                    # morphs through upload stages
theme-switch toggle                                                 # cards recolour in place
systemctl --user restart quickshell && notify-send "after" "restart" # history is RAM-only: panel starts empty, one new card
```

Check that the toast renders on the focused monitor when you switch workspaces to
another screen, that right-clicking a toast hides all of them while `SUPER+SHIFT+N`
still lists them, and that `qs ipc -c notifs call notifs clearHistory` empties the panel.

## Revert to dunst

One line in `nixos/home.nix`:

```nix
custom.notificationDaemon = "dunst";
```

`custom.notificationDaemon` is the single switch (`"quickshell"` on the desktops,
`"dunst"` on `vm-*` hosts). Setting it to `"dunst"` restores `services.dunst`, the
`dunstrc` symlink and the `dunstrc.d/50-theme.conf` drop-in, and drops the
quickshell unit, its Hyprland bind and its layerrules (`palette.json` continues to
be rendered harmlessly by `theme.nix`). `notify-send` keeps working because
`libnotify` replaced `pkgs.dunst` in `screenrec.runtimeInputs`.
`~/.local/state/quickshell-notifs/` (just `prefs.json`) can be deleted at leisure.

## Limits

- **Not exercised on the live session bus at design time.** The branch was gated
  by `qmllint`, `nix eval` and derivation builds; the behavioural checks in the
  design record's verification plan are run in an isolated `dbus-run-session`
  harness. On a real host, watch for a second server failing to acquire the name
  (`qs log -c notifs -t 50 | grep -i notifications`) and for the toast stack
  rendering on the wrong monitor.
- **Focus grab and layer blur.** `HistoryPanel` uses `HyprlandFocusGrab` with
  `WlrKeyboardFocus.OnDemand` because Hyprland re-maps layer surfaces in a way
  that can steal focus back; if `Esc` does not close the panel, that grab is the
  thing to look at. The layerrules that blur `qs-notifs-toasts` /
  `qs-notifs-panel` are likewise worth a first-run check.
- **`image://qsimage` URLs live only in memory.** Stored rows keep text, urgency,
  app and a validated icon name or local path; an in-memory image handle is
  cleared when the notification closes.
- **Action buttons only exist while the notification is live.** A consequence of
  storing records rather than D-Bus objects, and the price of history that matches
  dunst's in-memory lifetime.
- **Grouped view ordering is by app name then newest-first**, which is not
  dunst-comparable (dunst had no grouping at all).
