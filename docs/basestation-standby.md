# Valve base stations back to standby after power loss

`arch` has no UPS, so a power cut takes the PC and both Base Station 2.0 units down
together. The stations come back **on** (firmware default) and nothing puts them away
again. A timer on `arch` fixes that, and a `basestation` command drives them by hand.

```sh
basestation status              # <name> <mac> <state>, e.g. "LHB-4657C94C F3:B6:84:3E:68:BA standby"
basestation standby             # what the timer runs
basestation off                 # sleep (motors and radios off)
basestation on                  # wake them up by hand
basestation identify            # blink the LED
basestation standby --if-idle   # no-op while SteamVR is running
```

Every write is read back and reported, so the command says what the station actually did,
not what it was asked to do. Exit 1 if any station failed; failures never abort the loop,
so one unreachable unit does not stop the other.

## Layout

| Path | Role |
|---|---|
| `nixos/modules/basestation.nix` | options, the `basestation` package, the service + timer |
| `nixos/modules/basestation.sh` | the script body (`writeShellApplication`: strict mode, `PATH` from `runtimeInputs`, shellcheck) |
| `nixos/arch-configuration.nix` | `custom.basestation = { enable = true; standbyInterval = "30min"; }` |
| `flake.nix` | module listed under `arch` only — no other host has stations |

Timer: `OnBootSec = 90s` (the power-cut case) and `OnUnitInactiveSec = 30min` (units
plugged in later), with `ExecStartPre = sleep 20` so the stations finish booting first.
Nothing is hardcoded per unit: stations are found by their advertising name `LHB-*`, and the
characteristics by UUID, so a third station or a replaced unit needs no edit.

## Why each piece looks the way it does

**`ReadValue`/`WriteValue`, not `Read`/`Write`.** BlueZ's GATT interface exposes those two
method names. `Read`/`Write` fail with `Method "Read" with signature "a{sv}" … doesn't
exist`, which reads like a signature problem and is not one.

**The scan stays open for the whole run.** BlueZ forgets an idle LE device about 30 s after
it last saw it. Discover-then-handle dropped the second station mid-run, so the script
holds `bluetoothctl --timeout 280 scan on` in the background and kills it on exit. Without
it, station 2 reliably failed with "not known to BlueZ".

**Wait for `ServicesResolved` before touching a characteristic.** Selecting a
characteristic too early fails with `No attribute selected` — silently, if the error is not
checked. `wait_resolved` polls once a second, and gives up immediately if `Connected` goes
false.

**A failed connect is explicitly disconnected.** If `Connect` times out, bluetoothd keeps
the attempt pending and the controller stays busy. Two attempts per station, each
`timeout 25`, then an explicit `Disconnect`.

**`--if-idle` uses a bare `|`.** `pgrep` compiles an ERE, so `'vrmonitor\|vrserver'` matches
nothing; `'vrmonitor|vrserver'` matches. Check with
`pgrep -f 'vrmonitor|vrserver'` before trusting the guard.

**No D-Bus policy change was needed.** This host already allows any user to send to
`org.bluez` (`/run/current-system/sw/share/dbus-1/system.d/bluetooth.conf` ends with
`<policy context="default"><allow send_destination="org.bluez"/></policy>`), so
`basestation` works from an ordinary shell while the service runs as root.

**The adapter is matched as `hciN`.** `devpath_for` looks for
`/org/bluez/hci[0-9]+/dev_<mac>`, so the dongle moving between USB ports is not a change:
on 2026-11-24 it moved from a rear port (`hci0`) to the front panel and came back as
`hci1` with everything still working.

## When the radio stops seeing anything

The ASUS USB-BT500 (RTL8761BU) can wedge after a hung `Connect`: the adapter stays powered
and `bluetoothctl` reports `Discovering: yes`, but no advertisement ever arrives — not the
stations, not a phone. A `btmon` capture shows the scan commands succeeding and then nothing
at all, and the kernel logs `Bluetooth: hci0: Opcode 0x2039 failed: -38`. Observed
2026-11-24 for ~35 minutes; the script's explicit disconnect is meant to prevent it, which
is unproven.

Recovery is a software power cycle, no unplugging:

```sh
bluetoothctl power off; sleep 3; bluetoothctl power on
```

It drops every paired phone and tablet for a few seconds. While the adapter is wedged, each
timer run logs `FAIL` lines and exits 1; it recovers on the next run once the radio works.

## Observability

The journal reaches **Loki** (not Mimir — Mimir is metrics only):

```logql
{job="node-journal", host="arch", unit="basestation-standby.service"}
```

Lines carry `level="info"`; `FAIL` lines go to stderr and should arrive as `level="err"`.
The unit's state is also a **Mimir** metric, scraped by the `home-nodes` job on `pite`:

```
node_systemd_unit_state{name="basestation-standby.service", instance="arch.local:9100"}
```

## Checks

```sh
systemctl list-timers basestation-standby.timer
journalctl -u basestation-standby -n 20     # expect one line per station
systemctl cat basestation-standby.service  # points at the store script
```

As first installed (2026-11-24) the first run handled both stations and exited 0. The
`OnBootSec` path itself was still unproven: the host had not been rebooted since the module
was added.

## Rollback

`systemctl --now disable basestation-standby.timer` stops the automation at runtime and
leaves the LEDs as they are; `custom.basestation.enable = false` removes it declaratively.
Nothing else depends on the module.
