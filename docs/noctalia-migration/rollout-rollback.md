# Rollout, verification and rollback

**The migration was written, not applied.** Agent NF did not run
`nixos-rebuild`, did not switch a generation, did not restart Hyprland and did
not start Noctalia. Everything below is for the user to run when ready.

Two rules before starting:

1. Build from `~/dotfiles` (`/home/john/repos/dotfiles`), not from the
   `worktrees/dotfiles-noctalia-full` checkout. The theme module links app
   configs with `mkOutOfStoreSymlink ../.config/...`, so a generation built in
   the worktree bakes worktree paths into the session.
2. Expect a **full re-login**, not a live reload. Bar ownership, notification
   daemon, tray, wallpaper, lock screen and the compositor's layer rules all
   change; `systemctl --user restart noctalia` alone does not apply the Hyprland
   side.

---

## 1. Preflight (no system change)

```fish
cd ~/dotfiles
git status --short
git branch --show-current
```

Merge the migration branch first:

```fish
git switch master
git merge --no-ff noctalia-full-shell
```

If you want to evaluate before merging, build directly from the worktree but do
not switch from it. Flakes only see files tracked by Git, so stage the new tree
first (`status-helpers.nix`, `noctalia.nix`, `noctalia-plugins/`, the docs) or
the evaluation fails with "is not tracked by Git":

```fish
cd ~/repos/worktrees/dotfiles-noctalia-full
git add -A
nixos-rebuild build --flake .#office
```

Check the plugin manifests and the generated config before touching the system:

```fish
cd ~/dotfiles
nix shell nixpkgs#noctalia -c noctalia plugins lint noctalia-plugins
```

Expected: `0 errors, N warnings` and exit 0. An error almost always means an
`entry = "…luau"` path that no longer exists or a `getConfig` key with no
`[[setting]]` declaration.

Build the system closure and inspect the closure diff (packages that disappear
are the old stack):

```fish
nixos-rebuild build --flake ~/dotfiles#office
nix store diff-closures /run/current-system ./result
```

Look for removals of `waybar`, `eww`, `dunst`, `wofi`, `cliphist`, `hyprlock`,
`hyprpaper`, `gammastep`, `lxqt-policykit`, `grim`, `swappy`, and confirm
`noctalia-5.6.0` appears.
On `arch`/`office`, also confirm `deskflow-ctl` and `ipad-display` are still in
the closure.

The Nix module sets `programs.noctalia.checkConfig = true`, so the build above
already ran `noctalia config validate` against the generated TOML and would
have failed on an unknown 5.6.0 key. To validate the live file later:

```fish
nix shell nixpkgs#noctalia -c noctalia config validate ~/.config/noctalia/config.toml
```

`nixos-rebuild test` is **not** a safe side-by-side trial: it activates the new
generation until reboot, which removes Waybar and starts Noctalia in the current
session. Use a full `switch` with the rollback command from §5 ready.

---

## 2. Switch

```fish
cd ~/dotfiles
sudo nixos-rebuild switch --flake ~/dotfiles#office
```

Then restart the graphical session:

```fish
hyprctl dispatch exit
```

Log back in through the display manager. On first login verify the unit:

```fish
systemctl --user status noctalia
journalctl --user -u noctalia -b --no-pager | tail -50
```

`theme-switch refresh` runs during Home Manager activation, before Noctalia
exists, so its `theme-mode-set`/`wallpaper-set` calls are best-effort. Run it
once after login to push the saved mode and wallpaper:

```fish
theme-switch refresh
noctalia msg theme-mode-get
noctalia msg wallpaper-get
```

Host notes: `arch` and `office` get the Deskflow and iPad widgets; the other
hosts do not install those helpers, so the entries are not placed in their bar.
Night light keeps the old gammastep gating: `enabled = compName != "secu" &&
compName != "arch"`, with coordinates in `[location]`.

---

## 3. Post-switch verification (16 checks)

Run these in order. Each has a concrete expected result; a failure note points
at the likely cause.

| # | Check | Command / action | Expected |
|---|---|---|---|
| 1 | **Bar layout** | `noctalia msg status`; look at the top edge | `barVisible: true`; start = workspaces, `✚` newworkspace, optional bluetooth, active window, media; centre = empty; end = privacy, screenrec, optional iPad, tailscale, optional Deskflow, voxtype, hardware capsule group (cpu/ram/temp, plus gpu/vram/gpu-temp on arch/office), clock capsule group (clock/date), updates, optional thermostat, vast, weather, theme, battery, autoclicker, tray, volume, notifications, control-center. Plugin capsules render text, not blank; exactly one tray. |
| 2 | **Deskflow toggle + panel** (arch/office) | Left-click the `DF` pill; right-click it; middle-click it | Left runs `deskflow-ctl toggle` and the pill changes class; middle re-polls on the spot. Right opens the Deskflow panel, which has one row per connected client with route/address, its latency and a graph of the last two minutes plus a `min / avg / max` caption. There are no per-client pills on the bar. `deskflow-ctl status` agrees with the pill, `deskflow-ctl clients` with the panel. |
| 3 | **Voxtype stream** | Hold `SUPER+A`, speak, release; watch the mic capsule | `recording` while held, `transcribing` after release, then back to idle. `voxtype status --format json` reports the same state. If the capsule never changes, the `--follow` stream died: `noctalia msg plugin john/voxtype:bar focused refresh`. |
| 4 | **Notifications, history, LHB filter** | `notify-send "Noctalia test" "hello"`; then `noctalia msg panel-toggle control-center notifications` | A toast appears top-right; the notification tab lists it in history; `noctalia msg notification-dnd-toggle` suppresses **toasts** while history keeps filling; toggle DND back off. For the LHB filter, connect/pair an `LHB-*` basestation: `[notification.filter.base_station_connect]` (`match = "blueman"`, `match_content = "^LHB-"`, `show_toast = save_history = play_sound = false`) must keep the pairing popup out of both toast and history. A non-LHB Bluetooth notification still shows. |
| 5 | **Lock screen + `hypr-blank` guard** | `CTRL+ALT+L`; unlock with the password; then lock again and press `CTRL+ALT+M` | The Noctalia lock surface appears on every output and unlocks through PAM (`login` service). While locked, `hypr-blank` refuses with "session is locked (LockedHint=yes, noctalia=true)" instead of DPMS-off. No auto-lock occurs after idling, and `systemctl suspend` does not lock (`lock_before_suspend = false`). |
| 6 | **Wallpaper + `theme-switch toggle`** | `SUPER+SHIFT+T` (or the theme widget), twice | Palette, Alacritty, Fuzzel, GTK/dconf, tmux, nvim and Hyprland borders flip dark↔light, and the wallpaper follows `wallpaper-path`. `noctalia msg theme-mode-get` matches `theme-switch status`. Nothing flips back a few seconds later (that would mean `sync_color_scheme` or a template is still on). |
| 7 | **Screenshots + juush** | `CTRL+SHIFT+1` (region → clipboard), then `CTRL+SHIFT+2` (annotate → upload) | Region select freezes the screen and the clipboard receives a PNG. The annotated capture opens the editor and pipes the result to `juush` (stdin → `screenshot_location`), which prints an upload URL; `CTRL+SHIFT+3/4` do the same without annotation. Verify the upload landed in the expected Temporal pipeline. |
| 8 | **Clipboard history** | Copy text, copy an image, press `SUPER+V`, select an entry, paste | The clipboard panel lists both entries with previews; selecting pastes into the focused window (auto-paste needs the Hyprland `keyboard` permission). Pinned entries survive `clipboard-clear`. |
| 9 | **Launcher** | `SUPER+Space`, type an app name, Enter; in a terminal run `printf 'a\nb\n' \| noctalia dmenu -p test` | The launcher opens with recents and categories; the app starts. `noctalia dmenu` prints the picked line. With Noctalia stopped, dmenu must fail gracefully (it needs the running shell). |
| 10 | **Polkit** | `pkexec true` (or any privileged GUI action) | Exactly one authentication prompt appears, styled as a Noctalia panel. `pgrep -a lxqt-policykit` returns nothing; a second agent would make one prompt silently never appear. |
| 11 | **Night light** | `noctalia msg nightlight-enable`; then `noctalia msg nightlight-force-toggle` | The screen warms to `temperature_night = 3500`; force pins it regardless of schedule; toggling again returns to the schedule. Skip on `secu`/`arch`, where the module disables it (`enabled = false`, matching the old gammastep rule). `[location]` is coordinate-based, so no geolocation lookup is needed. |
| 12 | **Media panel** | Right-click the media capsule; play/pause a player; pin one; change a Firefox tab's volume/mute | The panel lists every MPRIS player and Firefox-family tab; pinning makes the bar follow that player; per-tab volume/mute/focus works. |
| 13 | **Tailscale panel** | Left-click the Tailscale capsule; use connect and exit-node | The panel shows tailnet, self node, peers (online/total) and the current exit node; connect/disconnect works through `/run/wrappers/bin/sudo`; the exit-node picker is a `noctalia dmenu`. |
| 14 | **Autoclicker panel** | Right-click the autoclicker capsule; change mode, interval, button, target | The daemon follows immediately (`autoclicker status` agrees), the `autoclicker watch` capsule updates, and "Pick with mouse" runs slurp. |
| 15 | **TeamSpeak SNI tray** | Start TeamSpeak; inspect the tray widget and its menu | The TeamSpeak icon appears in Noctalia's tray (it owns `org.kde.StatusNotifierItem-5-1`), left-click opens its window/menu, and the tray context menu renders. Other SNI apps (tailscale, voxtype if any) also appear. |
| 16 | **GPU card in the control-center system tab** (arch/office) | Left-click any hardware pill, or `noctalia msg panel-toggle control-center system` | The CPU, RAM, temperature and GPU cards are all there immediately, and the GPU card no longer appears a few seconds late. Its history is in-memory, so it starts empty at every shell start and fills over ~4 minutes (120 slots x 2 s); an empty graph right after login is expected, a missing card is not. A missing card means `hw_gpu`/`hw_vram`/`hw_gpu_temp` are gone from the bar — their probes are refcounted per series and the system tab is the only other consumer. |

Optional extras if the host has them: iPad status/recover/create (arch/office),
VAST pill hidden when no instance, `updates` pill hidden until
`flake.lock` is older than 24 h, thermostat right/middle/scroll against Home
Assistant.

### If a check fails

| Symptom | First command | Likely cause |
|---|---|---|
| No bar at all | `systemctl --user status noctalia`; `journalctl --user -u noctalia -b` | unit failed, config validation error, or Hyprland layer rule missing |
| Bar up, no plugin widgets | `noctalia msg plugins list` | plugin source path wrong or ids not in `[plugins].enabled` |
| Plugin shows nothing | `noctalia msg plugin john/dotfiles-bar:<entry> all refresh`; run the helper by hand | helper not on PATH, or stream exited |
| Tray empty | `busctl --user list \| grep StatusNotifier` | another watcher won, or app is XEmbed-only |
| Toasts missing | `noctalia msg notification-dnd-status`; `pgrep -a dunst` | DND on, or a second daemon still owns the name |
| Lock fails every password | `journalctl --user -u noctalia \| grep -i pam` | `noctalia-pam-helper`/`libpam` mismatch (FAQ: `NOCTALIA_PAM_HELPER_PATH`) |
| Theme flips back | `noctalia msg config-get theme.sync_color_scheme`; `cat ~/.local/state/noctalia/settings.toml` | `sync_color_scheme`/templates not disabled, or a stale `theme.mode` override |
| Screenshots/auto-paste denied | `noctalia msg status`; Hyprland log | missing `screencopy`/`keyboard` permission rule |

---

## 4. `settings.toml` drift

Noctalia loads, in order: built-in defaults → `/etc/xdg/noctalia/` →
`~/.config/noctalia/*.toml` → `~/.local/state/noctalia/settings.toml`. The last
file is written by the Settings GUI, the setup wizard, wallpaper selection,
`config-set`, `theme-mode-set` and `color-scheme-set`, and it **wins**.

Expected legitimate overrides in this setup:

- `theme.mode` — written by `theme-switch` through `noctalia msg theme-mode-set`.
- `wallpaper.default.path`, `wallpaper.last`, and
  `wallpaper.monitors."<connector>"` — written by `wallpaper-set`.
- `plugins.enabled` — only if someone toggled a plugin in the GUI or with
  `noctalia msg plugins enable/disable`.

Everything else is accidental drift. Inspect and reconcile:

```fish
cat ~/.local/state/noctalia/settings.toml
noctalia msg config-get theme.mode
noctalia msg config-get theme.sync_color_scheme
```

Remove the whole file to return to the declarative config:

```fish
rm ~/.local/state/noctalia/settings.toml
noctalia msg config-reload
theme-switch refresh
```

Or delete single keys; Noctalia drops a key itself only when the GUI writes a
value equal to the lower layer's, so hand edits are the reliable path. Do not
edit the file while the shell is running (it rewrites on the next change), and
never symlink it into the Nix store or a Home Manager path — Noctalia writes
through symlinks to their target.

If a GUI change is wanted permanently, move it into
`nixos/modules/noctalia.nix` and delete the state key.

---

## 5. Rollback

### 5.1 Instant (no git, no rebuild)

Activate the previous NixOS generation:

```fish
sudo nixos-rebuild switch --rollback
```

or, if `--rollback` cannot resolve the profile:

```fish
nixos-rebuild list-generations
sudo nixos-rebuild switch --switch-generation <N>
```

Then re-login (`hyprctl dispatch exit`). The previous generation restores
Waybar, Eww, dunst, wofi, cliphist, hyprlock, hyprpaper and gammastep, and
removes the Noctalia unit and its Home Manager symlinks. The Home Manager
activation also re-runs `theme-switch refresh`, which restarts Waybar/Eww/dunst
because that generation's script still has the old reload hooks.

Optional cleanup of Noctalia-only state (it is inert once Noctalia is gone):

```fish
rm -rf ~/.local/state/noctalia
```

Keep it if you intend to switch forward again — it holds clipboard/notification
history and any GUI preferences.

### 5.2 Git rollback

If the branch is not merged:

```fish
cd ~/dotfiles
git switch master
git branch -D noctalia-full-shell          # only if you want to discard it
```

If it is merged:

```fish
cd ~/dotfiles
git log --oneline --merges -3              # find the merge commit
git revert -m 1 <merge-commit>
sudo nixos-rebuild switch --flake ~/dotfiles#office
```

Or reset master to the pre-merge commit if nothing else landed on top:

```fish
git reset --hard <pre-merge-commit>
```

Do not use `--no-verify`; the pre-commit hooks are the only validation the
legacy Nix files get.

### 5.3 Emergency (no usable session)

1. Switch to a TTY: `Ctrl+Alt+F2`, log in as `john`.
2. `sudo nixos-rebuild switch --rollback`
3. `loginctl terminate-user john` (or reboot) and log in again.

If only Noctalia died but the compositor is alive:

```fish
systemctl --user restart noctalia
journalctl --user -u noctalia -b --no-pager | tail -100
```

If the unit will not start, `noctalia --daemon` in a terminal shows the same
errors on stderr; a schema error in `~/.config/noctalia/config.toml` is the most
common cause and `noctalia config validate` names file/line/column.

---

## 6. Known first-run failure modes

| Failure | Cause | Fix |
|---|---|---|
| Every lock-screen password rejected | `noctalia-pam-helper` built/linked against a different `libpam`, or the `login` PAM stack is not the expected one | use the NixOS package (helper uses the `login` service); if a foreign build, set `NOCTALIA_PAM_HELPER_PATH` per the FAQ |
| Two polkit prompts / one never shows | `lxqt-policykit-agent` still running alongside `polkit_agent = true` | remove the old agent (done in `home.nix`), `pkill lxqt-policykit-agent` |
| Clipboard history resets each boot | keyring holding the storage key is not the one PAM unlocks | switch `[storage] key_source = "file"` with an agenix key file |
| Screenshots/auto-paste silently denied | Hyprland `ecosystem.enforce_permissions` without rules | add `hl.permission("^<store-path>/bin/noctalia$", "screencopy", "allow")` and the `hl-virtual-keyboard-noctalia` keyboard rule; restart Hyprland (permissions are not reloaded) |
| Bar/lock/OSD tearing or double animations | missing `no_anim` layer rule | add the `^noctalia-(bar-.+\|notification\|dock\|panel\|attached-panel\|osd\|window-switcher)$` rule |
| `noctalia dmenu` prints nothing | shell not running, or no `WAYLAND_DISPLAY` | start Noctalia first; export the session env for scripts/timers |
| Wallpaper missing after switch | `theme-switch refresh` ran before Noctalia existed | run `theme-switch refresh` once after login |
| GUI settings revert on rebuild | `settings.toml` still has the override | delete the key or the file (§4) |
| Plugin badged incompatible | `plugin_api` > 56 | lower the level (see `custom-components.md` §1) |
| `deskflow`/`ipad` entries missing on a host | helpers installed only on `arch`/`office` | expected; do not place those widgets on other hosts |
