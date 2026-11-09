# Mice: DPI, and why Hyprland's pointer gain is 1:1

Pointer speed on these machines is set in **two** places, and only one of them is in Nix:

| Where | What | In git? |
|---|---|---|
| The mice's own memory | DPI and report rate, stored in an onboard profile | No — it lives in the hardware |
| `nixos/home.nix` | `input.sensitivity = 0` (and `accel_profile = "flat"`) | Yes |

## Why the gain is 0

Firefox's Wayland pointer lock truncates every relative-motion event to whole pixels and drops
the zeros, without carrying the fraction over ([bug 1739598](https://bugzilla.mozilla.org/show_bug.cgi?id=1739598)).
Both engines report `movementX` as integers, so this cannot be worked around from a page.

At `sensitivity = -0.2` with a flat profile each mouse count moves the pointer 0.8 px, so a 1000 Hz
mouse's slow movements round to 0 and never reach a browser game: a deadzone. At `0` each count is
exactly 1 px and nothing is lost.

So pointer speed belongs in the mouse, not in the compositor:

| Host | Mouse | DPI | Report rate | Onboard profile |
|---|---|---|---|---|
| office | G502 X LIGHTSPEED (046d:c547 receiver, WPID 409F) | 950 | 1000 Hz | 1 |
| arch | G502 HERO (046d:c08b, wired) | 950 | 1000 Hz | 3 |

950 is the same speed as office's old 1200 DPI at 0.8 gain (960 px/in) within 1%, and it replaces
arch's 800 px/in. The DPI buttons step 650 / 950 / 1250 / 1900 / 2550 on office, whose shift button
now gives 1250 (was 1600).

**Games that read raw input** (CS2, the native ROTS client) do not use `sensitivity`, so they only
see the DPI change. Multiply in-game sensitivity by office 1200/950 = **1.26** and arch
1000/950 = **1.05** to keep the old feel. One in-game value then feels the same on both machines.

## Reading and changing it

Solaar is deliberately **not installed**. It is only needed when changing a mouse, it needs no
daemon, and the settings live in the hardware, so run it from the store instead:

```fish
nix shell nixpkgs#solaar -c solaar show            # model, firmware, current DPI, onboard mode
nix shell nixpkgs#solaar -c solaar config "G502 X LIGHTSPEED" dpi   # lists the steps it accepts
```

DPI moves in 50s (hence 950 rather than 960). With the mouse in **On-Board** mode — both are —
`solaar config ... dpi` is temporary; the profile has to be rewritten to keep it.

### Rewriting a profile (persistent, survives reboot and other computers)

```fish
# 1. dump every profile to YAML
nix shell nixpkgs#solaar -c solaar profiles "G502 X LIGHTSPEED" > before.yaml
# 2. edit the active profile's `resolutions:` list and (optionally) `report_rate:` — 1 is 1 ms
# 3. write it back, then read it back
nix shell nixpkgs#solaar -c solaar profiles "G502 X LIGHTSPEED" after.yaml
nix shell nixpkgs#solaar -c solaar profiles "G502 X LIGHTSPEED" | diff after.yaml -
```

Only the DPI table and the report rate belong in such an edit: the same file carries the button
mappings and lighting, and a wrong table rewrites those too. Dump first, and keep the dump.

The exact device names are `G502 X LIGHTSPEED` and `G502 SE Hero Gaming Mouse`; a substring such
as `G502` matches both if they were ever attached at once.

### Undoing it

Restore a dump taken before the change, on the machine that mouse is plugged into:

```fish
nix shell nixpkgs#solaar -c solaar profiles "G502 X LIGHTSPEED" before.yaml
```

## Access

Solaar talks HID++ to `/dev/hidraw*`, which it can only do unprivileged because
`/etc/udev/rules.d/92-viia.rules` sets every hidraw node to `0666` — an **untracked** rule that a
VIA/Vial install dropped on both machines. If that rule ever goes away, Solaar needs `sudo`, or add
`hardware.logitech.wireless.enable = true` to make Logitech access explicit (it ships
`solaar-udev`'s rules).

That rule is also broader than it needs to be: it makes every hidraw device world-writable, not
just the VIA keyboards.
