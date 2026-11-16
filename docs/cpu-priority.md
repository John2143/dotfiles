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
| 2 | `app.slice` | 60 | waybar, portals, TeamSpeak, Steam client |
| 3 | `discord.slice` | 30 | Discord |
| 4 | `games.slice` | 10 | the game, firefox |

`CPUWeight=40` goes on `user@.service`, which is what puts **everything the user
manager launches** below the compositor. At full saturation the session branch
takes 100/140 ≈ 71 %, `app.slice` ≈ 17 %, `discord.slice` ≈ 9 %, `games.slice` ≈ 3 %.

Tune in one place: the `tiers` attrset at the top of the module.

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

## Verify after a rebuild

```
grep CPUWeight /etc/systemd/system/user@.service.d/overrides.conf  # CPUWeight=40
systemctl show user@1000.service -p CPUWeight                      # after reboot: 40
systemctl --user show app.slice -p CPUWeight                       # 60
cat /proc/$(pgrep -x Xwayland)/cgroup                              # …/session-c1.scope
systemctl --user show 'app-steam-*.scope' -p CPUWeight              # [not set] — by design
```

Stall counters show the real effect better than load average:
`/sys/fs/cgroup/user.slice/user-1000.slice/session-c1.scope/cpu.pressure`
against the `app.slice` equivalent while a game runs.

## Known limitation / next step

The per-app tiers (3 and 4) are inert because of the self-adoption above. What
this module actually delivers is **compositor above everything**, with firefox
genuinely last (it is a plain `exec` and does not self-adopt). To get
`compositor > services > discord/game`, invert the design instead of moving the
apps: put the plain units (waybar, hyprpaper, portals, TeamSpeak — they never
self-adopt) in a `services.slice` weighted above `app.slice`, and let `app.slice`
be the low catch-all that self-adopting apps land in. Separating Discord from
the game on top of that needs a watcher that calls
`systemctl --user set-property 'app-discord-*.scope' CPUWeight=…`.

## Related

- The original diagnosis: Hyprland aborts on `GL_GUILTY_CONTEXT_RESET`
  (`OpenGL.cpp:745`) after a GPU context reset; separate from CPU pressure, and
  weights do nothing about it.
- Memory was the other half of that night: a 27 h boot ended at 26 GiB used and
  16 GiB of 31 GiB swapped. Reboot clears it; bounding it is unaddressed.
