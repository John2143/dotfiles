# Quickshell Notification Centre — Design & Decision Record (Agent Q)

- **Date:** 2026-11-25
- **Branch:** `agent-q/quickshell` (worktree `~/repos/worktrees/dotfiles-quickshell`, branched from `origin/master` @ `c07fd69`)
- **Status:** Design frozen → implementing on branch (user will build and switch).
- **Scope:** Replace `dunst` with a hand-written Quickshell 0.3.2 notification daemon and wider right-anchored notification centre, wired into the existing Catppuccin `theme-switch` pipeline and gated by an offline `qmllint` flake check. Waybar, eww, fuzzel, wofi, cliphist, hyprlock, hyprpaper, gammastep stay untouched.

---

## 1. Decisions and rationale

Every decision below is backed by direct reads of Quickshell v0.3.2 source/docs, nixpkgs pin `93a9ed0a8660` (2026-11-21), home-manager module source, and three upstream reference shells (`caelestia-dots/shell`, `duxlabs-dev/dux-shell`, `end-4/dots-hyprland`).

| # | Decision | Rationale & evidence |
|---|---|---|
| D1 | **One `NotificationServer` in a `Singleton` (`services/Notifs.qml`), `keepOnReload: false`.** | Second server re-runs `switchGeneration()` (`qml.cpp:16-30`); `keepOnReload: false` gives clean reload semantics because our own state file holds history (`server.cpp:59-95`). |
| D2 | **Capabilities:** advertise `body`, `body-markup`, `body-hyperlinks`, `image`, `actions`, `persistence`, plus `extraHints: ["x-dunst-stack-tag"]`. Do **not** advertise `inlineReplySupported` or `actionIconsSupported`. | Matches parity scope; advertising `inline-reply` without an input box causes clients to hide their own reply affordance (dux bug). `hints` retains `x-dunst-stack-tag` automatically (`notification.cpp:167`). |
| D3 | **Live notifications vs. inert history records.** Active toasts bind to live `Notification` objects (so `replaces_id` updates like `screenrec` flow in-place without re-firing `onNotification`, `server.cpp:196-215`). History is an inert JS/JSON record list updated *both* on receipt and whenever a tracked notification's summary/body/urgency/progress changes, persisted via `FileView` + `JsonAdapter` with 1 s debounce to `$XDG_STATE_HOME/quickshell-notifs/history.json`. | Avoids two upstream bugs: caelestia/end-4 lose notifications on dismiss; dux snapshots only at receipt so 40× progress updates save stale text. Persisted rows never show inert action buttons (actions only rendered when a live `Notification` is still attached). Cap: 200 entries, 14-day age prune on load. |
| D4 | **Timeouts in milliseconds** (Quickshell docstring says seconds, `notification.cpp:118` passes D-Bus ms verbatim). | `-1` → server default (low 10 s, normal 10 s, critical 0 = sticky, matching `dunstrc:316,321,326`); `0` → never auto-hide; `>0` → honour client ms. Timeout sets `popup = false` only (never `dismiss()`), preserving the entry in history. Hover pauses using remaining-time arithmetic (`remaining = deadline - now`), not a full timer restart. |
| D5 | **Dunst parity rules in `services/Notifs.qml`:** (a) suppress `summary` matching `/^LHB-/` completely (`skip_display` + `history_ignore`, matching `dunstrc:453-462`), calling `n.dismiss()` synchronously; (b) `x-dunst-stack-tag` coalescing (`keybind.nix:18` `hass-*` toasts replace the prior card/history slot with the same tag); (c) `int:value` progress bar (`screenrec.sh:31`); (d) `transient` skips history persistence; (e) `notify-send -A` actions + left-click default action, middle-click open first URL + close toast, right-click close all toasts (`dunstrc:298-300`). | Every existing caller in the repo keeps working without regression. `screenrec.sh` and `juush.bash` switch from `dunstify` to `notify-send` (`-p`/`-r` verified present in libnotify), dropping the `pkgs.dunst` runtime dependency. |
| D6 | **Theming via `palette.json` in `nixos/modules/theme.nix`.** Add 4 lines to `render` emitting `{ flavor, colors }`. `Theme.qml` reads `~/.local/state/theme/current/palette.json` directly via `FileView` (`blockLoading: true`, `watchChanges: true`, `onFileChanged: reload()`), plus belt-and-braces `IpcHandler` target `theme` (`qs ipc call theme refresh` in `theme-switch.sh`). | `FileView` watches both file and parent dir (`fileview.cpp:494-548`), so `theme-switch.sh`'s `install` + `mv -f` atomic rename triggers live re-evaluation with zero palette duplication. Pointing at the real state path (not a config symlink) ensures inotify sees the rename. |
| D7 | **Packaging: `programs.quickshell` + unit merge in `nixos/modules/quickshell-notifs.nix`.** | Reuses HM's package, `configs.notifs = ../../.config/quickshell/notifs`, `activeConfig = "notifs"` (stable `shellId` on 0.3.0+), and systemd skeleton, while merging `PartOf`, `StartLimit*`, `RestartSec=3`, `TimeoutStopSec=10`, `QS_NO_RELOAD_POPUP=1`, and a `home.activation.quickshellRestart` hook. Gated off on `vm-*` hosts (`!lib.hasPrefix "vm-" compName`). Disables `services.dunst` when enabled so only one process owns `org.freedesktop.Notifications`. |
| D8 | **Stay on nixpkgs pin + offline `qmllint` flake check.** | `nixos-unstable` hits `cache.nixos.org` (zero compile cost); a separate flake input breaks the cache hash (`DISTRIBUTOR=Official-Nix-Flake`). Catch 0.x API breaks at eval/build time via `checks.x86_64-linux.quickshell-notifs` running `qmllint -I <qt>/lib/qt-6/qml -I <qs>/lib/qt-6/qml -I <synth-qs-root> --import=error --missing-property=error`. Escape hatch: `overrideAttrs` pin documented in upgrade runbook. |
| D9 | **Surface geometry & focus:** Toasts in a `top`+`right` `PanelWindow` (300 px wide, margins 40 top / 10 right, gap 8, radius 12, frame 2, `WlrLayer.Overlay`, `exclusionMode: Ignore`, `focusable: false`, `mask: Region { item: toastCol }`, `namespace: "qs-notifs-toasts"`, rendered on the Hyprland-focused monitor). History centre in a wider right-anchored `PanelWindow` (440 px card inside full-screen click-outside backdrop or right-edge panel + `HyprlandFocusGrab` with `WlrKeyboardFocus.OnDemand`, `WlrLayer.Overlay`, `namespace: "qs-notifs-panel"`). | Matches dunst's `follow = keyboard`, width/offset/radius/font (`JetBrainsMono Nerd Font`, `pointSize: 11`), while delivering the requested 440 px right-anchored centre with reliable keyboard focus (Esc close, j/k/arrows navigate, Enter invoke default action, x/Del remove, d toggle DND, C clear all). `HyprlandFocusGrab` solves Hyprland's re-map focus quirk (`LayerSurface.cpp:212-227`). |

---

## 2. Architecture & File Layout Contract

All paths are relative to the repository root (`~/repos/worktrees/dotfiles-quickshell`):

```
.config/quickshell/notifs/
  shell.qml                    # ShellRoot, IPC handlers ("notifs", "theme"), per-screen ToastStack + HistoryPanel
  services/
    Theme.qml                  # pragma Singleton; FileView on ~/.local/state/theme/current/palette.json + col()/alpha()
    Notifs.qml                 # pragma Singleton; NotificationServer, live wrappers, history list, JsonAdapter persistence,
                               #   DND state, LHB-* filter, x-dunst-stack-tag coalescing, timers, openUrl()
  components/
    ToastCard.qml              # Single toast card (urgency colours, icon/image, markup body, progress bar, actions,
                               #   hover-pause, left/middle/right mouse parity)
    ToastStack.qml             # Top-right overlay PanelWindow on focused screen, click-through Region mask
    HistoryPanel.qml           # 440 px right-anchored PanelWindow + HyprlandFocusGrab + keyboard nav,
                               #   app-grouped & chronological views, DND pill, Clear All, per-item remove/action

nix/checks/
  quickshell-notifs.nix        # Offline qmllint derivation with synthesized qs.* qmldir tree

nixos/modules/
  quickshell-notifs.nix        # HM module (local.quickshellNotifs.enable): programs.quickshell, unit hardening,
                               #   services.dunst = mkForce false, Hyprland SUPER+SHIFT+N bind + layerrules

docs/
  plans/2026-11-25/quickshell-notifications.md   # This decision record
  quickshell-notifications.md                    # Operator & maintenance reference (theme-toggle.md style)
```

### Modified existing files (minimal, localized edits)

| File | Change |
|---|---|
| `nixos/modules/theme.nix` | Add `"palette.json"` to `render` (4 lines); drop `dunst.conf` symlink/package only when `local.quickshellNotifs.enable` (so reverting the flag restores dunst cleanly); add `qs` package to `theme-switch` `runtimeInputs` when enabled. |
| `nixos/theme-switch.sh` | Keep `dunstctl reload` guarded (`command -v`), add `timeout 5 qs ipc --any-display call theme refresh >/dev/null 2>&1 || true`. |
| `nixos/home.nix` | Import `./modules/quickshell-notifs.nix`; set `local.quickshellNotifs.enable = !lib.hasPrefix "vm-" compName;`; replace `pkgs.dunst` with `pkgs.libnotify` in `screenrec.runtimeInputs`; gate `services.dunst` & `dunstrc` symlink on `!config.local.quickshellNotifs.enable` (single-line revert). |
| `.config/screenrec.sh` | Replace `dunstify` with `notify-send` (`-a -p -u -t -i -r -h` verified identical in libnotify). |
| `.config/juush.bash` | Replace `dunstify "Starting upload"` with `notify-send "Starting upload"`. |
| `flake.nix` | Expose `checks.x86_64-linux.quickshell-notifs`. |

---

## 3. Contracts (shared across implementation units)

### 3.1 `palette.json` schema (`~/.local/state/theme/current/palette.json`)
```json
{
  "flavor": "dark",
  "colors": {
    "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7", "mauve": "#cba6f7",
    "red": "#f38ba8", "maroon": "#eba0ac", "peach": "#fab387", "yellow": "#f9e2af",
    "green": "#a6e3a1", "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
    "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4", "subtext1": "#bac2de",
    "subtext0": "#a6adc8", "overlay2": "#9399b2", "overlay1": "#7f849c", "overlay0": "#6c7086",
    "surface2": "#585b70", "surface1": "#45475a", "surface0": "#313244",
    "base": "#1e1e2e", "mantle": "#181825", "crust": "#11111b"
  }
}
```
`Theme` singleton exposes:
- `dark: bool`, `flavor: string`
- `col(name: string): color` (falls back to Catppuccin Mocha defaults if file absent on first boot)
- `alpha(name: string, a: real): color` (via `Qt.rgba`, avoiding QML's `#AARRGGBB` trap)
- `fontFamily: string` (`"JetBrainsMono Nerd Font"`), `fontSize: int` (`11`)
- `reload(): void` (calls `paletteFile.reload()`)

### 3.2 `Notifs` singleton contract (`services/Notifs.qml`)
Properties:
- `panelOpen: bool` (writable; setting true marks unread count 0)
- `dnd: bool` (persisted in state JSON; suppresses toast popups for non-critical notifications while still recording history; critical bypasses DND)
- `grouped: bool` (persisted toggle between app-grouped and flat chronological history view, default `true`)
- `unreadCount: int`
- `toasts: list<var>` (active toast entry objects, sorted critical → normal → low then newest-first, capped at 20)
- `history: list<var>` (inert persisted records, newest-first, capped at 200, max age 14 days)

Entry object shape (both toast wrappers and history records share fields; only live toasts have `liveNotif != null`):
```js
{
  uid: string,          // monotonic string key for Repeater/ListView
  dbusId: int,          // live notification.id (0 once closed/restored)
  stackTag: string,     // hints["x-dunst-stack-tag"] ?? ""
  appName: string,
  appIcon: string,      // icon theme name
  image: string,        // image URL/path (cleared if image://qsimage on persistence)
  summary: string,
  body: string,
  urgency: int,         // 0 Low, 1 Normal, 2 Critical
  progress: int,        // hints["value"] 0..100, or -1 if absent
  timestamp: real,      // Date.now() ms
  duplicateCount: int,  // >= 1
  transient: bool,
  actions: list,        // [{ identifier, text }] — interactive only while liveNotif != null
  liveNotif: var        // Notification* while tracked, null for persisted/closed history
}
```
Methods on `Notifs`:
- `togglePanel(): void`, `openPanel(): void`, `closePanel(): void`
- `toggleDnd(): void`, `setDnd(v: bool): void`
- `hideToast(uid: string): void` (hides toast, keeps in history)
- `hideAllToasts(): void` (right-click parity: hides all toasts, keeps history)
- `dismissEntry(uid: string): void` (dismisses live notif if any AND removes from toasts)
- `removeHistory(uid: string): void` (removes from history + dismisses live if still tracked)
- `clearHistory(): void` (clears history + hides all toasts + dismisses live tracked in batches)
- `invokeAction(uid: string, identifier: string): void` (invokes action on live notif; default action if `identifier === ""`)
- `openFirstUrl(uid: string): void` (extracts first `https?://` URL from body/summary, spawns `xdg-open` via `Quickshell.execDetached`)
- `pauseToast(uid: string): void`, `resumeToast(uid: string): void` (true remaining-time pause)

### 3.3 IPC contract (`IpcHandler` in `shell.qml`)
- Target `"notifs"`:
  - `toggle(): void` — toggles history panel (`SUPER+SHIFT+N` runs `qs ipc call notifs toggle`)
  - `open(): void` / `close(): void`
  - `toggleDnd(): void` / `setDnd(enabled: bool): void` / `isDnd(): bool`
  - `count(): int` (history count) / `unread(): int`
  - `clearToasts(): void` / `clearHistory(): void`
  - `reload(): void` (`Quickshell.reload(false)`)
- Target `"theme"`:
  - `refresh(): void` (`Theme.reload()`)

### 3.4 Parity matrix vs. current dunst setup

| Current dunst feature | Quickshell implementation |
|---|---|
| `origin = top-right`, `offset = 10x40`, `width = 300`, `gap = 8`, `radius = 12`, `frame = 2` | `ToastStack.qml` + `ToastCard.qml` exact metrics |
| `follow = keyboard` | `Hyprland.focusedMonitor` selects which screen renders `ToastStack` |
| `font = JetBrainsMono Nerd Font 11`, `markup = full` | `font.family` + `font.pointSize: 11`, `bodyMarkupSupported: true`, `Text.StyledText` with sanitized/escaped fallback |
| `urgency_low/normal` 10 s, `critical` sticky (0) | Spec-correct ms resolver with 10000 / 10000 / 0 defaults |
| `progress_bar = true` (`screenrec.sh -h int:value:N`) | `progress >= 0` draws Catppuccin progress bar inside `ToastCard` |
| `stack_duplicates = true` + `x-dunst-stack-tag` (`keybind.nix:18`) | Replaces existing live toast/history slot matching `stackTag` (or identical app+summary+body within 10 s, incrementing `duplicateCount`) |
| `[base-station-connect] summary = "LHB-*"` skip + history_ignore | Suppressed synchronously in `onNotification` (`n.dismiss()`) |
| `mouse_left = do_action`, `middle = open_url + close`, `right = close_all` | `MouseArea` in `ToastCard.qml` (`acceptedButtons: Qt.LeftButton \| Qt.MiddleButton \| Qt.RightButton`) |
| `dunstify -r` (`screenrec.sh:33`) | `notify-send -r` (standard `replaces_id`, updates live entry in place) |
| `history_length = 20` in-memory + fuzzel | Persistent 200-entry / 14-day history in wider 440 px right-anchored `HistoryPanel.qml` |
| `theme-switch` light/dark Catppuccin | `palette.json` + `FileView` `watchChanges` + `qs ipc call theme refresh` |

---

## 4. Verification plan (no NixOS rebuild / switch)

1. **Offline `qmllint` gate:** `nix build .#checks.x86_64-linux.quickshell-notifs` — builds only `quickshell` + `qtdeclarative` from cache and lints every `.qml` file with `--import=error --missing-property=error`.
2. **Nix evaluation gate (no system build):** `nix eval` the `arch`, `office`, and `vm-arch` home-manager attributes (`programs.quickshell`, `services.dunst.enable`, `systemd.user.services.quickshell`, `xdg.configFile`, Hyprland binds) and build only the small generated `theme-assets` and `theme-switch` derivations (which runs `shellcheck` on `theme-switch.sh` and `screenrec.sh`).
3. **Formatting:** `nix fmt -- --check` (alejandra) on every modified `.nix` file.
4. **Live smoke test:** left for the user after they build/switch (`docs/quickshell-notifications.md` documents exact test commands and one-line revert).
