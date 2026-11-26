# Quickshell notification centre

Replaces `dunst` on the Hyprland desktops with a Quickshell 0.3.2 notification
daemon (`org.freedesktop.Notifications`) plus a right-anchored history centre.
Toasts keep dunst's geometry and mouse behaviour; history survives restarts and
lives in a 440 px panel instead of fuzzel.

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
| `.config/quickshell/notifs/services/Notifs.qml` | `pragma Singleton`: the single `NotificationServer`, live toasts, history list, JSON persistence, DND, `LHB-*` filter, stack-tag coalescing |
| `.config/quickshell/notifs/services/Theme.qml` | `pragma Singleton`: `palette.json` reader, `col()` / `alpha()`, font family and size |
| `.config/quickshell/notifs/components/ToastCard.qml` | one card: urgency colours, icon/image, markup body, progress bar, action buttons, hover pause, mouse parity |
| `.config/quickshell/notifs/components/ToastStack.qml` | top-right overlay `PanelWindow`, 300 px, click-through `Region` mask |
| `.config/quickshell/notifs/components/HistoryPanel.qml` | 440 px right-anchored `PanelWindow`, `HyprlandFocusGrab`, keyboard nav, DND pill, Clear All |
| `nixos/modules/quickshell-notifs.nix` | HM module `local.quickshellNotifs.enable`: `programs.quickshell`, unit hardening, dunst off, layerrules, SUPER+SHIFT+N |
| `nix/checks/quickshell-notifs.nix` | offline `qmllint` derivation |
| `~/.local/state/quickshell-notifs/history.json` | persisted history (200 entries, 14-day prune, 1 s debounce) |
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
is a quick liveness check. `SUPER+SHIFT+N` runs
`qs ipc -c notifs call notifs toggle`, and no `hyprctl dispatch` wrapper is
needed because the IPC call is instantaneous and side-effect free.

## Panel keys and mouse

| Input | Effect |
|---|---|
| `SUPER+SHIFT+N` | open/close the history panel |
| `Esc` | close the panel |
| `j` / `↓`, `k` / `↑` | move selection |
| `Enter` | invoke the selected entry's default action |
| `x` / `Delete` | remove the selected entry from history |
| `d` | toggle Do Not Disturb |
| `C` | clear all history |
| left click on a toast | default action (dunst `mouse_left_click = do_action`) |
| middle click on a toast | open the first `http(s)://` URL in the body, then hide the toast |
| right click on a toast | hide every toast, history untouched |
| click outside the panel | close it |

## Parity with the old dunst setup, and what changed

| dunst | now |
|---|---|
| `origin = top-right`, `width = 300`, `offset = 10x40`, `gap = 8`, radius 12, frame 2 | identical, `ToastStack.qml` + `ToastCard.qml` |
| `follow = keyboard` | `Hyprland.focusedMonitor` picks the screen that renders the stack |
| `font = JetBrainsMono Nerd Font 11`, `markup = full` | same family and `pointSize: 11`; `bodyMarkupSupported = true`, `Text.StyledText` with escaped fallback |
| `urgency_low/normal` 10 s, `critical` sticky | 10 000 / 10 000 / 0 ms; `-1` → default, `0` → never auto-hide, `> 0` honoured as client ms |
| `progress_bar = true` (`-h int:value:N`) | `progress >= 0` draws the bar; absence of the hint draws nothing |
| `stack_duplicates`, `x-dunst-stack-tag` | matching tag replaces the live card and its history slot; otherwise identical app+summary+body inside 10 s increments a duplicate counter |
| `[base-station-connect]` `summary = "LHB-*"`, `skip_display`, `history_ignore` | suppressed synchronously in `onNotification` with `dismiss()`: no card, no history row |
| `notification_limit = 20` | same cap, sorted critical → normal → low, newest first within a class |
| `mouse_left/middle/right` | table above |
| `history_length = 20` in memory + fuzzel | 200 entries, 14-day age prune, persisted across restarts and rebuilds |
| `dunstctl reload` from `theme-switch` | `FileView` watch plus `qs ipc -c notifs call theme refresh` |
| `dunstify` in `screenrec.sh`, `juush.bash` | `notify-send` (`-p`, `-r`, `-h int:value:` all exist in libnotify) |

Intentional differences:

- **Wider surface.** History is a 440 px right-anchored panel with an app-grouped
  view (the default) and a flat chronological view; the header control toggles
  between them and the choice is persisted. `d` is reserved for DND. The toast
  itself stays 300 px.
- **Persistence.** Dunst forgot everything on restart; the centre writes
  `history.json` 1 s after the last change, so a screenrec progress storm costs one
  write, not forty. `transient` notifications are deliberately not persisted.
- **Live vs. inert rows.** A visible toast binds to the live `Notification`
  object, so `replaces_id` (as `screenrec` uses with `notify-send -r`) updates the
  text in place. Persisted rows are plain records and never show action buttons
  after the notification is gone.
- **No `inline-reply` and no `action-icons` in the capability list.** Advertising
  `inline-reply` without a text input makes clients hide their own reply UI
  (observed in dux-shell), and `action-icons` has no consumer here. Both are one
  line each if ever wanted.
- **`x-dunst-stack-tag` is still honoured** even though the daemon is not dunst:
  `nixos/modules/keybind.nix:18` sends `hass-*` `notify-send` calls with that hint,
  and clients keep passing it.
- **Do Not Disturb** suppresses toast popups for low and normal urgency but still
  records the entry in history; `critical` bypasses DND. Dunst exposed
  `dunstctl set-paused true`, but nothing in this repo bound it; the flag here is
  persisted in `history.json`, so a quiet desktop stays quiet across a rebuild.
- **Unread badge.** `unreadCount` counts entries received since the panel was last
  opened; opening the panel zeroes it.

## Theme integration

`nixos/modules/theme.nix`'s `render` now also emits `palette.json` next to
`dunst.conf` and `waybar.css`:

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
4. Re-run the lint gate, then `nix eval` the `arch`, `office` and `vm-arch`
   home-manager attributes, then rebuild.
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
   `org.freedesktop.Notifications`. `qs log -t 50 -f` follows the daemonised
   instance's log, and `QS_NO_RELOAD_POPUP=1` (set by the unit) keeps the reload
   toast away.

## First deploy

```sh
cd ~/repos/dotfiles
nixos-rebuild switch --flake .#arch        # or .#office
systemctl --user status quickshell
qs list                                    # one instance, config "notifs"
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
systemctl --user restart quickshell && notify-send "after" "restart" # history survives, still one card
```

Check that the toast renders on the focused monitor when you switch workspaces to
another screen, that right-clicking a toast hides all of them while `SUPER+SHIFT+N`
still lists them, and that `qs ipc -c notifs call notifs clearHistory` empties the panel.

## Revert to dunst

One line in `nixos/home.nix`:

```nix
local.quickshellNotifs.enable = false;
```

That restores `services.dunst`, the `dunstrc` symlink and the `dunst.conf` theme
drop-in, and drops the quickshell unit and its Hyprland bind and layerrules
(`palette.json` continues to be rendered harmlessly by `theme.nix`).
`notify-send` keeps working because `libnotify` replaced `pkgs.dunst` in
`screenrec.runtimeInputs`. `~/.local/state/quickshell-notifs/history.json` can
be deleted at leisure.

## Limits

- **Not exercised on the live session bus.** `dunst` owns
  `org.freedesktop.Notifications` on the machine where this was written, so the
  branch is gated only by `qmllint`, `nix eval` and derivation builds — nothing has
  talked to a real notification bus. The first switch is the first real run: watch
  for a second server failing to acquire the name (`qs log -t 50 | grep -i
  notifications`) and for the toast stack rendering on the wrong monitor.
- **Focus grab and layer blur are unobserved.** `HistoryPanel` uses
  `HyprlandFocusGrab` with `WlrKeyboardFocus.OnDemand` because Hyprland re-maps
  layer surfaces in a way that can steal focus back; if `Esc` does not close the
  panel on the first switch, that grab is the thing to look at. The layerrules that
  blur `qs-notifs-toasts` / `qs-notifs-panel` are also first-run observations.
- **`image://qsimage` URLs are not persisted.** Stored entries keep text, urgency,
  app and icon name; a raw image path is kept, an in-memory image handle is cleared.
- **Action buttons only exist while the notification is live.** This is a
  consequence of storing records rather than D-Bus objects, and it is the price of
  history that survives restarts.
- **Grouped view ordering is by app name then newest-first**, which is not
  dunst-comparable (dunst had no grouping at all).
