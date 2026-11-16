# Autoclicker

Scroll-to-click daemon and its Waybar widget. Code lives in `autoclicker/src/main.rs`, the
service and helper commands in `nixos/modules/autoclicker.nix`, the widget in
`nixos/modules/waybar.nix`, and the overlay menu in `eww/eww.yuck`.

Wheel notches become clicks in one of two modes: `scroll-left` injects left clicks,
`scroll-right` injects right clicks. The wheel itself is swallowed while a mode is on. With a
target window set, clicks only fire while that window has keyboard focus (the tooltip says
`Target: any` when unrestricted).

| Action | Result |
|---|---|
| left-click the bar icon | toggle off ↔ `scroll-left` |
| middle-click the bar icon | cycle off → `scroll-left` → `scroll-right` |
| right-click the bar icon | open the `autoclicker-menu` overlay |
| `SUPER+Escape` | off |
| `autoclicker get mode` / `autoclicker status` | current mode / the Waybar JSON |

The mode is never persisted, so the daemon always starts `off` after a restart; the timer
settings are persisted in `$XDG_RUNTIME_DIR/autoclicker/state`.

## How it works

It is a grab-and-forward daemon, not a set of Hyprland binds. Each host gets an explicit
VID:PID allowlist (`--device`, set in `nixos/modules/autoclicker.nix`), so the office volume
knob on the AKKO keyboard can never be grabbed. A node must also advertise both `BTN_LEFT`
and `REL_WHEEL`, because one receiver exposes a mouse node and a keyboard node under the same
VID:PID. The daemon `EVIOCGRAB`s the mouse, re-emits its events through a uinput device named
`autoclicker-scroll` (tagged `INPUT_PROP_POINTER`), drops the wheel codes on the way through,
and pushes press/release pairs to a click thread.

The keyboard is never grabbed, which is the escape hatch: if the daemon misbehaves,
`systemctl --user stop autoclicker` releases the kernel grab (it dies with the file
descriptor) and typing still works.

## Invariants

**Never grab or ungrab while a button is held.** A press that reaches the compositor before
the grab has its release delivered through the passthrough, which never pressed that button;
the compositor discards it and keeps the button down. While a button is down the compositor
keeps pointer focus on the surface that received the press — the Waybar widget — so every
later click is routed there. The visible symptoms are right-clicks anywhere opening the
overlay menu, and clicks in applications appearing dead. `start_scroll` therefore reads the
device key state (`EVIOCGKEY`) before grabbing, returns `StartOutcome::Deferred` while any
button is down, retries every 25 ms (`Ctl::next_attempt`, versus a 2 s rescan when no device
matches), and undoes the whole attempt if a button went down between the check and the grab.
`stop_scroll` still ungrabs immediately: destroying the uinput device releases the buttons it
held, and delaying the off switch would stall a drag.

**Injected clicks must look like hardware.** Press and release go in separate SYN frames,
30 ms apart, with `InputEvent::new_now()` timestamps. A same-frame or zero-duration pair is
ignored by the compositor — this was the cause of "the counter goes up but nothing gets
clicked".

**The Waybar module must be a streaming `exec`.** `exec = "${autoclicker} watch"` with
`restart-interval = 2` and no `interval`, no `signal`. A `signal` plus no `interval` makes
Waybar wait for the command to exit, and `watch` never does, so the widget never renders.

The click budget is 30 clicks/s (`ClickBudget`, capacity 30, refill 30/s); notches over it are
counted as `Dropped` in the tooltip rather than queued.

## Reading the tooltip

`Notches` counts wheel notches seen, `Clicks` injected press/release pairs, `Dropped` notches
over budget. `No mouse device matched` means either that nothing matched the allowlist or that
a start attempt is being deferred because a button is held — the second case clears within one
control-loop tick of the release. A slow click on the bar icon therefore shows it briefly, and
the mode engages about 120 ms after the release (one tick plus uinput device creation), so a
notch inside that window still scrolls instead of clicking.

## Testing

Pure functions, no hardware:

```bash
nix build ./autoclicker#default && ./result/bin/autoclicker selftest
```

Live, without a second mouse: create a synthetic uinput mouse with a VID:PID the daemon is told
to accept, run the daemon under a private `XDG_RUNTIME_DIR` (so it cannot collide with the real
one), and then observe it from outside.

- `EVIOCGRAB` on the event node succeeds only when nobody else holds it — that is how you see
  whether the daemon has the device.
- Reading the *real* node while the daemon holds the grab yields nothing (grabs are exclusive),
  so instrument the passthrough device (`grep autoclicker /proc/bus/input/devices` for its
  `eventN`) to see exactly what is being forwarded.
- `EVIOCGKEY` does report keys injected through uinput, which is what makes the held-button
  check work before any event has reached the daemon.

Two traps that cost real time: python's `struct.pack` must use native `llHHi` (24 bytes) for
`input_event` — the `'='` prefix makes `l` 4 bytes and the kernel rejects the write, so the
synthetic mouse silently never presses anything. And a successful `EVIOCGRAB` probe returns
`EBUSY` rather than raising when the daemon holds the device, so check the errno, not just
success.

## Recovery

If a click is ever stranded, press and release the button once (that clears the compositor's
implicit grab) and `systemctl --user restart autoclicker`. Update the `--device` list before
rebuilding a host with a different mouse.
