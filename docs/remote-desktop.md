# Remote desktop into arch and office (RustDesk behind SSH)

`rd office` on arch (or `rd arch` on office, or either from the MacBook) opens an SSH tunnel
and starts a RustDesk session to that host's screen. RustDesk is not reachable from any network:
the only way in is the SSH tunnel, so getting to the RustDesk password prompt first costs an SSH
key and a pinned host key.

The Mac is a **client only**. Nothing connects into the Mac.

## What runs where

| Where | What | Defined in |
|---|---|---|
| arch, office | Portal routing: ScreenCast and RemoteDesktop go to `xdg-desktop-portal-luminous`, everything else stays on Hyprland/gtk | `nixos/modules/remote-desktop.nix`, `nixos/shared-configuration.nix` |
| arch, office | `luminous-autopick` user service: answers luminous's monitor picker after 30 s without physical input | `nixos/modules/remote-desktop.nix` |
| arch, office | `rustdesk` user service: RustDesk with no arguments, policy re-pinned before every start | `nixos/modules/remote-desktop.nix` |
| arch, office | Firewall: TCP 21118 dropped on every interface except `lo` | `nixos/modules/remote-desktop.nix` |
| arch, office | tmpfiles: `/tmp/RustDesk-service` (root, 0711) and `/tmp/RustDesk-1000` (john, 0700) exist from boot | `nixos/modules/remote-desktop.nix` |
| arch, office, Mac | `rd` helper | `nixos/rustdesk-tunnel.nix` |
| Mac | Homebrew cask `rustdesk`, service declined, incoming off | `nixos/darwin-macbook.nix` + manual steps below |
| every NixOS host | sshd refuses keyboard-interactive (password) logins; keys only | `nixos/shared-cli-configuration.nix` |

Nothing runs as root. There is no RustDesk system service, no `/dev/uinput` access and no
rendezvous server.

## Why SSH is in the middle

RustDesk in direct-IP mode has no transport encryption or host authentication of its own, and
its login is a single password whose proof can be cracked offline. So its port is closed to the
network (loopback-only whitelist plus a firewall drop), and only an `ssh -L` tunnel reaches it:
the client needs an SSH key the host accepts, and the host must present the exact host key
pinned in `nixos/rustdesk-tunnel.nix`. The RustDesk password is the second factor.

What this does **not** fix: any process running as `john` on the host can read RustDesk's
stored password hash (which works in place of the password) and can reach `127.0.0.1:21118`
without SSH. RustDesk also still sends STUN probes to Cloudflare and Google; that cannot be
turned off.

## Decisions

| Decision | Reason |
|---|---|
| Portal config key is `hyprland`, lowercase | xdg-desktop-portal lowercases `XDG_CURRENT_DESKTOP` before looking for `<desktop>-portals.conf`. A `Hyprland` key generates `Hyprland-portals.conf`, which is never read. |
| Both ScreenCast and RemoteDesktop go to luminous | The Hyprland portal has no RemoteDesktop, and the portal frontend sends a RemoteDesktop session's source selection to the ScreenCast backend, so both must come from the same backend. InputCapture stays on Hyprland for the Deskflow server. |
| RustDesk never runs with `--server` or `--service` | Without them it uses portal capture and portal input. With them it switches to uinput, which needs RustDesk's root service. It decides by grepping `ps` for the literal `rustdesk --server`, so never `pgrep`/`grep` for that joined string either. |
| 30 s physical-input rule | Someone at the desk gets luminous's normal picker; nobody at the desk means a monitor is shared without a prompt. Only evdev input counts, so the remote session's own virtual input does not. Away from the desk the choice is `~/.config/luminous-autopick/monitor` when that names a connected output, else the focused monitor — focus is worthless right after a reboot, which is why the file exists. |
| Whitelist `127.0.0.1/32,::1/128` plus a drop of 21118 outside `lo` in the **raw** table | SSH is the gate. An empty whitelist means "allow everyone", so the value is re-pinned on every start. Never widen it to the tailnet: that restores password-only access from every tailnet node. The drop lives in `raw/PREROUTING` because Tailscale's `ts-input` chain accepts every tailnet packet before `nixos-fw` is reached, so a filter-table rule for 21118 never matches. |
| `/etc/xdg` is first in `XDG_CONFIG_DIRS` | Setting that variable at all removes the implicit `/etc/xdg` default, and the portal routing file lives in `/etc/xdg/xdg-desktop-portal/`. Without it the frontend ignores the routing file entirely: ScreenCast stays on Hyprland and the RemoteDesktop portal is never exported. |
| Rendezvous, relay and API servers on `127.0.0.1` ports 9, 10, 7 | They are unused. Ports under 1024 cannot be bound by another local uid, so nobody can impersonate them. The GUI's "not ready" status is therefore permanent and expected. |
| 23 pinned options in `RustDesk2.toml`, 1 in `RustDesk_local.toml` | Terminal, TCP tunnel, camera, remote restart, recording, LAN discovery and remote config changes off; keyboard, clipboard, file transfer, file copy-paste and audio on; permanent password only; idle sessions end after 10 minutes; update check off. RustDesk's own setters need root, so the files are edited before each start instead. |
| sshd `KbdInteractiveAuthentication = false` on every NixOS host | With `UsePAM yes`, keyboard-interactive accepts the account password even though `PasswordAuthentication` is off, which would make the gate only as strong as a login password. |

## Connecting

- `rd arch` / `rd office`: opens the tunnel if it is not up, then opens the RustDesk session.
  Tick "remember password" the first time; later connects skip the prompt.
- `rd <host> --stop`: closes that host's tunnel. Otherwise it lasts until logout or until the
  network drops (keepalive every 15 s).
- If the session does not open by itself, connect RustDesk by hand to the address `rd` prints:
  `127.0.0.1:21201` (arch) or `127.0.0.1:21203` (office).
- The Mac cannot be connected into.
- A host that is not in `rd`'s map:
  `ssh -N -f -o ExitOnForwardFailure=yes -L 127.0.0.1:<any free port>:127.0.0.1:21118 <host>`,
  then connect RustDesk to `127.0.0.1:<that port>`.
- One monitor per session: luminous hands the portal a single monitor, so both desktops at once
  is not possible with this backend. To switch, focus the other monitor inside the session
  (SUPER+1 / SUPER+SHIFT+1), disconnect and reconnect.
- Which monitor is shared while nobody is at the desk is pinned in
  `~/.config/luminous-autopick/monitor` — one output name (`hyprctl monitors | grep Monitor`),
  e.g. `HDMI-A-2`. Write it once and the choice survives reboots; it is re-read per connection,
  so no restart is needed. Without it the focused monitor is used, which right after a reboot is
  the first output rather than the one used last time. An output named there but not connected
  is ignored, with a log line. At the desk, the picker still wins.
- After a reboot, nothing is reachable until someone logs in at the host.

## First-time setup

On each of arch and office, after switching **and logging out and back in** (the units are wanted
by `graphical-session.target`, which is already active right after a switch, so they do not start
by themselves, and the portal frontend only reads its routing at startup):

1. RustDesk window opens at login. Do the following, then close the window with SUPER+Q (this
   hides it; the server keeps running):
   - Settings → Security → unlock → set a permanent password: 40 random characters, unique per
     host, kept in the password manager. It is now the second factor and the only thing
     standing between a local `john`-level process and the session.
   - Settings → General: the update check must already be off. If the GUI shows it on, the pin
     script did not run; check `journalctl --user -u rustdesk`.
   - Confirm Security shows "Enable direct IP access" checked and the whitelist exactly
     `127.0.0.1/32,::1/128`.
   - If an "Install" daemon card appears, ignore it.
2. No root path: `pgrep -fa 'rustdesk' | grep -cE -- '--(server|service)'` prints `0`.
3. The tunnel path works. On office: `rd arch` prints
   `rd: opening RustDesk session to arch (127.0.0.1:21201)` and a RustDesk session window opens
   asking for arch's password; enter it and tick "remember password". Video, mouse and keyboard
   work. Close the session and run `rd arch` again: it reconnects without a password prompt and
   without a second ssh (`pgrep -fc -- '-L 127.0.0.1:21201:127.0.0.1:21118'` prints `1`). Check
   the reverse with `rd office` on arch.

On the MacBook (client only):

- `darwin-rebuild switch --flake .#macbook`.
- Open RustDesk. **Decline** the service/LaunchDaemon install prompt. Grant Accessibility or
  Input Monitoring only if RustDesk asks for them for keyboard capture as a client; it does not
  need Screen Recording.
- Settings → Security: turn the service off ("Stop service" / "Enable service" unchecked),
  uncheck "Enable direct IP access", and still set the whitelist to `127.0.0.1/32,::1/128` (no
  spaces) as a backstop in case the service is ever re-enabled. Settings → General: turn off the
  update check. Settings → Network: turn off LAN discovery.
- Check nothing listens: `sudo lsof -nP -iTCP:21118 -sTCP:LISTEN` prints nothing, and
  `ls /Library/LaunchDaemons | grep -i rustdesk` prints nothing.
- From the Mac: `rd arch` opens a session to arch, `rd office` to office. Find the RustDesk
  binary name with `ls /Applications/RustDesk.app/Contents/MacOS/`; if it is not `RustDesk`, fix
  the path in `nixos/rustdesk-tunnel.nix`.

## Troubleshooting

Health checks (on the host):

- Portal routing and units:
  `busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep -c 'org.freedesktop.portal.RemoteDesktop'`
  prints ≥1; `systemctl --user is-active luminous-autopick rustdesk xdg-desktop-portal-luminous`
  prints `active` three times.
- Port closed to the network: from another machine, `nc -vz -w3 <host tailnet IP> 21118` times
  out (dropped, not refused). Testing from the host itself proves nothing: its own tailnet IP is
  reached over `lo`, which the rule allows. On the host,
  `sudo iptables -t raw -vnL PREROUTING | grep 21118` shows the DROP with a rising counter.
- sshd is keys only: `sudo sshd -T | grep -i kbdinteractive` prints
  `kbdinteractiveauthentication no`;
  `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=keyboard-interactive,password john@<host>`
  is refused with "Permission denied (publickey)".
- Picker responder: with nobody touching the host,
  `sleep 35; ls -l "$XDG_RUNTIME_DIR/luminus_selector.sock"` shows a socket with mode
  `srw-------`; after moving the mouse it is gone. `journalctl --user -u luminous-autopick -b`
  alternates `idle: answering the picker automatically` and `input seen: picker is interactive`.
- Policy cannot be weakened and stay weakened: `rustdesk --option enable-terminal Y` as john
  prints an administrative-privileges error; any edit to `~/.config/rustdesk/RustDesk2.toml` is
  undone by `systemctl --user restart rustdesk`.

Failures:

- **Portal routing ignored: no `org.freedesktop.portal.RemoteDesktop`, ScreenCast still on Hyprland.**
  Check `tr '\0' '\n' < /proc/$(pgrep -f 'libexec/xdg-desktop-portal$')/environ | grep XDG_CONFIG_DIRS`:
  it must start with `/etc/xdg:`. If it does not, the frontend never reads
  `/etc/xdg/xdg-desktop-portal/hyprland-portals.conf`; fix the systemd `DefaultEnvironment` and
  log out and back in. To see what a frontend resolves without touching the live one:
  `dbus-run-session -- env XDG_CURRENT_DESKTOP=Hyprland G_MESSAGES_DEBUG=all /run/current-system/sw/libexec/xdg-desktop-portal 2>&1 | grep 'Using .*portal for'`
  (the binary is wrapped and also lives under `/nix/store/*-xdg-desktop-portal-*/libexec/`).
- **Cursor vanished and nothing responds to the pointer, but the keyboard still works.**
  Deskflow had an `InputCapture` session open and the portal frontend that owned the session was
  restarted, leaving Hyprland's pointer confined with nobody to release it. Recovery, in order:
  `systemctl --user stop deskflow`, `systemctl --user restart xdg-desktop-portal-hyprland`, then
  `systemctl --user restart xdg-desktop-portal`. If the pointer is still gone, the compositor
  still holds the confinement: log out (the keyboard works) and back in.
  **Never restart `xdg-desktop-portal` while Deskflow is running** — that is what causes it.
- **Settings → Security → Unlock fails with `sudo: execvp error: Err(ENOENT)`.** RustDesk runs
  `sudo /bin/sh -c …` for that dialog (`execvp("sudo", …)`), and a systemd *service* gets the
  stock service PATH, not the manager's, so `sudo` in `/run/wrappers/bin` is invisible. The
  module sets `Environment = "PATH=…"` on the unit; if you hit it before re-switching, stop the
  unit and start it with `PATH=/run/wrappers/bin:$PATH rustdesk &`. `rustdesk --password` is not
  an alternative here: it requires the service IPC daemon, which this setup deliberately omits.
- **The port answers from the tailnet although the rule exists.**
  `sudo iptables -vnL nixos-fw | grep 21118` showing 0 packets while another host connects means
  the drop is in the wrong table: `-A INPUT -j ts-input` runs first. Check
  `sudo iptables -t raw -vnL PREROUTING`.
- **Tunnel opens, RustDesk says connection refused.** The forward is fine; the host is not
  listening. `systemctl --user status rustdesk`, then `journalctl --user -u rustdesk`. A failed
  `ExecStartPre` means a RustDesk TOML was unparseable, and RustDesk deliberately did not start.
- **Tunnel does not open.** `ssh -v <host>.ts.2143.me`. It is an SSH fault (key, host key, or
  the host asleep), not a RustDesk one. Do not weaken the firewall to work around it.
- **"Host key verification failed" from `rd`.** The host was reinstalled or its key rotated.
  Confirm out of band (at the host: `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), then
  replace that host's line in `nixos/rustdesk-tunnel.nix` and rebuild. Never add
  `StrictHostKeyChecking=no`.
- **`rd` opens an empty window, an "invalid ID" error or nothing, while the tunnel is up.** The
  `--connect` handoff does not work with this RustDesk version. Remove the launcher block from
  `nixos/rustdesk-tunnel.nix` so `rd` only prints the address, and connect from the GUI.
- **Video works, input is dead.** `pgrep -fa 'rustdesk' | grep -cE -- '--(server|service)'` must
  print `0`. If a `--server` process exists, find what launched it and remove it. Never start
  RustDesk's root service as a workaround.
- **RemoteDesktop missing from the portal after relogin.**
  `journalctl --user -u xdg-desktop-portal -u xdg-desktop-portal-luminous -b`. If luminous failed
  to start or the frontend ignored it, roll back (below) and keep the log. Do not try other
  portal backends.
- **Firefox/OBS screen sharing broken or black.** Roll back. All ScreenCast then returns to
  Hyprland and remote desktop is unavailable until fixed. OBS re-asking for the screen on every
  launch is expected (luminous ignores restore tokens).
- **Black or stuttering capture on arch only (NVIDIA).** Remove `./nixos/modules/remote-desktop.nix`
  from arch's module list in `flake.nix` and switch arch. Remote desktop then works only into
  office.
- **`luminous-autopick` keeps restarting with `libinput debug-events exited`.** Check `id` for
  the `input` group. If missing, add `"input"` to `users.users.john.extraGroups` in
  `nixos/modules/user-john.nix`. The picker stays interactive meanwhile, which is safe.
- **Every screencast fails at once.** A stale `$XDG_RUNTIME_DIR/luminus_selector.sock` with the
  daemon not running. `rm -f "$XDG_RUNTIME_DIR/luminus_selector.sock"`.
- **Too many wrong passwords.** All tunnelled logins share the `127.0.0.1` lockout bucket: more
  than 6 failures in a minute blocks for that minute, more than 30 blocks until
  `systemctl --user restart rustdesk`.
- **Session stuck.** `rd <host> --stop` on the client, `systemctl --user restart rustdesk` on the
  host. Idle sessions end on their own after 10 minutes.
- **Sessions hang at "waiting for image", or typed characters use the wrong layout.** Known in
  RustDesk 1.5.0, fixed in 1.5.1 (#16542, #16462). Wait for nixpkgs to ship ≥ 1.5.1; do not
  write an override.
- **A host refuses SSH key login.** Not caused by this setup (it only removes
  keyboard-interactive). Use the host's console and `sudo nixos-rebuild switch --rollback`.

## Rollback

Linux hosts:

- Quick undo: `sudo nixos-rebuild switch --rollback` on the affected host.
- Permanent undo: `git revert <feat(remote-desktop) commit>` in `~/repos/dotfiles`, then switch.
  This removes the portal routing, the units, the firewall drop, the tmpfiles rules and `rd`.
  The sshd keys-only change is its own commit (`fix(sshd): …`) and stays unless reverted
  separately.
- Then log out and back in, because the portal frontend reads routing only at startup.
- Leftover user state is harmless: `~/.config/rustdesk/`, any `rd` tunnel (dies at logout).

Mac: `brew uninstall --cask rustdesk`, remove the `"rustdesk"` cask line and the
`rustdesk-tunnel.nix` import from `nixos/darwin-macbook.nix`, then
`darwin-rebuild switch --flake .#macbook`. Optionally revoke RustDesk's grants in System
Settings → Privacy & Security.
