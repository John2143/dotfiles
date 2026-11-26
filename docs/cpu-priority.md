# CPU priority tiers for the desktop session

`nixos/modules/cpu-priority.nix` weights the graphical session with cgroup v2
`CPUWeight` so the compositor cannot be starved by a game or a runaway app.
Imported by `arch-configuration.nix`; safe to import on any host that runs
`home-manager.users.john`.

## The tiers

Weights are **proportional, not quotas**. While cores are idle nothing is
throttled; the numbers only decide who waits when every thread is runnable.

| tier | cgroup | weight | holds |
|---|---|---|---|
| 1 | `session-c1.scope` (default, untouched) | 100 | Hyprland, Xwayland, tmux, terminals |
| — | `session.slice` (inside `user@1000.service`, default 100) | 100 | `xdg-desktop-portal*`, `dbus-broker`, permission store |
| 2 | `app.slice` | 60 | waybar, hyprpaper, quickshell (dunst on VMs), eww, TeamSpeak proxy, Steam client |
| 3 | `discord.slice` | 30 | Discord — empty in practice, see below |
| 4 | `games.slice` | 10 | the game, firefox — empty in practice, see below |

`CPUWeight=40` goes on `user@.service`, which is what puts **everything the user
manager launches** below the compositor. At full saturation the session scope
takes 100/140 ≈ 71 % and the whole user-manager branch 29 %. Inside that branch
`session.slice` (100) is a sibling of the app tiers, so it takes half of it;
`app.slice` gets ≈ 9 % of the machine, `discord.slice` ≈ 4 %, `games.slice` ≈ 1 %.

The module never names `session.slice`, but it matters: systemd puts the portal
stack there, so it keeps the default 100 and outranks `app.slice` inside the user
manager. Anything the portal spawns inherits it (third trap below).

Tune in one place: the `tiers` attrset at the top of the module.

Deployed on `arch` and verified live 2026-11-17 (generation 764): `cpu.weight`
reads 100 / 40 / 60 / 30 / 10 for the session scope, `user@1000.service`,
`app.slice`, `discord.slice` and `games.slice` respectively.

## Three things that cost time to learn

1. **`environment.etc` cannot write under `/etc/systemd/system`.**
   `environment.etc."systemd/system"` is a single entry whose `source` is the
   generated `system-units` derivation, activated as
   `/etc/systemd/system -> /etc/static/systemd/system` (mode `dr-xr-xr-x`). Any
   nested `environment.etc` entry fails at build time with
   `ln: failed to create symbolic link …: Permission denied` and takes the whole
   `etc` derivation down. Use the systemd module instead:
   `systemd.services."user@".serviceConfig.CPUWeight`. `systemd.units` has no
   `serviceConfig`; that option lives on `systemd.services`, and both feed the
   same generated unit. `user@.service` is already defined with
   `overrideStrategy = "asDropinIfExists"`, so a contribution merges into the
   existing `overrides.conf` and does not shadow the packaged unit.

2. **Discord and Steam games re-home themselves into `app.slice`.**
   Both adopt themselves into a transient `app-<name>-<pid>.scope` through
   systemd's D-Bus `StartTransientUnit`, *after* they start, ignoring the cgroup
   they were launched in:
   - Discord: `StartTransientUnit` is in the Discord binary itself; its parent
     `bwrap` ends up outside the scope with PPID 1.
   - Steam: `pressure-vessel-wrap` creates `app-steam-app<appid>-<pid>.scope`;
     the leader `reaper`'s parent (`steam-runtime-supervisor`) stays outside.

   Consequence: a desktop-entry wrapper (`systemd-run --slice=…`) or a Steam
   launch option (`systemd-run --user --scope --slice=games.slice -- %command%`)
   is erased a moment later. `discord.slice` and `games.slice` stay empty and
   both apps land at `app.slice`'s weight. Processes forked *before* adoption
   (e.g. Discord zygotes) are left behind in `session-c1.scope`, i.e. tier 1 —
   one app can occupy two tiers at once.

3. **A GUI app inherits the cgroup of its launcher.**
   Anything started from a terminal or `hl.exec_cmd` (instead of a `.desktop`
   entry) lands in `session-c1.scope` — the *highest* tier. That is how firefox
   ends up at tier 1 unless it is launched through its desktop entry.

   A second variant, seen on `arch`: an app the desktop portal spawns (a link
   click, a dynamic launcher) inherits
   `user@1000.service/session.slice/xdg-desktop-portal.service`, so a
   portal-launched firefox never reaches `games.slice` even though its entry
   says it does. Read `cat /proc/<pid>/cgroup` on the running process before
   concluding a wrapper is broken.

## Verify after a rebuild

Read the weights out of `/sys/fs/cgroup`, not from `systemctl show`: the unit
configuration can report a weight that was never applied, while `cpu.weight` is
what the scheduler actually uses.

```
grep CPUWeight /etc/systemd/system/user@.service.d/overrides.conf  # CPUWeight=40
cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/cpu.weight      # 40
cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/cpu.weight  # 60
cat /sys/fs/cgroup/user.slice/user-1000.slice/session-c1.scope/cpu.weight       # 100
systemctl --user show 'app-steam-*.scope' -p CPUWeight              # [not set] — by design
```

A `nixos-rebuild switch` applies the `user@.service` drop-in to the user manager
that is already running, so this does **not** need a reboot: `arch` switched on
2026-11-16 at 15:10 and its boot predated that by 16 h, with the cgroup already
reading 40.

The desktop entries are **not** in `~/.local/share/applications`. Since
home-manager 26.11 `xdg.desktopEntries` contributes a `lib.hiPrio` *package* to
the profile (`modules/misc/xdg/desktop-entries.nix`), so check the profile:

```
rg -n '^Exec=' /etc/profiles/per-user/john/share/applications/{firefox,discord}.desktop
# Exec=systemd-run --user --scope --slice=games.slice -- firefox %U
```

Absence from `~/.local/share/applications` therefore means nothing; absence from
`/etc/profiles/per-user/john/share/applications` does. `/etc/profiles/per-user/john/share`
is in `XDG_DATA_DIRS` ahead of `/run/current-system/sw/share`, which is how the
wrapped entries win over the packaged ones.

Stall counters show the real effect better than load average:
`/sys/fs/cgroup/user.slice/user-1000.slice/session-c1.scope/cpu.pressure`
against the `app.slice` equivalent while a game runs.

## Known limitation / next step

The per-app tiers (3 and 4) are inert because of the self-adoption above. What
this module actually delivers is **compositor above everything**, with firefox
genuinely last (it is a plain `exec` and does not self-adopt). To get
`compositor > services > discord/game`, invert the design instead of moving the
apps: put the plain units (waybar, hyprpaper, quickshell — dunst on VMs — eww,
TeamSpeak proxy — they never self-adopt) in a `services.slice` weighted above
`app.slice`, and let `app.slice` be the low catch-all that self-adopting apps
land in. Portals need no moving: they are already in `session.slice` at 100.
Separating Discord from the game on top of that needs a watcher that calls
`systemctl --user set-property 'app-discord-*.scope' CPUWeight=…`.

Confirmed live on `arch` (2026-11-17): Discord launched through the wrapped entry
still ended at `app.slice/app-discord-195631.scope` with `cpu.weight=100`, while
`discord.slice` (weight 30) held no processes at all. The wrapper does its job;
the app then undoes it.

## Related

- The original diagnosis: Hyprland aborts on `GL_GUILTY_CONTEXT_RESET`
  (`OpenGL.cpp:745`) after a GPU context reset; separate from CPU pressure, and
  weights do nothing about it.
- Memory was the other half of that night: a 27 h boot ended at 26 GiB used and
  16 GiB of 31 GiB swapped. A reboot clears it — 2026-11-17, 16 h in: 15 GiB
  used, 3.3 GiB swap, against 26 GiB / 10 GiB at 25 h on the previous boot — but
  it grows back. Bounding it is unaddressed.
