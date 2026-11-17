# iPad as a second display, and the cable link

Two independent halves, both in `nixos/modules/ipad-display.nix`, imported by `arch` and
`office` only (a Hyprland session is required):

1. **An extended display.** Hyprland gets a headless output named `MOONLIGHT`, Sunshine
   captures it, and Moonlight on the iPad shows it. Nothing is mirrored.
2. **A wired peer.** The same cable carries an IP link (`10.77.0.1/24`), so the stream works
   with Wi-Fi off and keeps working when the cable goes in or out.

Deskflow is separate (`nixos/modules/deskflow.nix`, Linux server + macOS client) and shares
nothing with either half except the two machines.

Why the cable link is `10.77.0.1/24` and not NetworkManager's default `10.42.0.1/24`: k3s
installs `10.42.0.0/24 via flannel.1` at metric 0 on every node, which beats the cable's
metric 101, so the iPad's packets arrived but every reply went into the overlay. Anything in
`10.42.0.0/16` (pods) or `10.43.0.0/16` (services) collides.

## Display: why each piece is the way it is

| Decision | Reason |
|---|---|
| `capture = wlr` | KMS capture cannot see a headless output. `zwlr_screencopy` can, and selects by name. |
| `output_name = MOONLIGHT` | Anonymous headless outputs are called `HEADLESS-N` and get a new number per creation. |
| The output is created by Sunshine's `global_prep_cmd`, not at login | It only has a purpose during a stream, and its mode comes from the client (`SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS`). |
| The watcher **restarts Sunshine** after removing the output | Sunshine's placebo desktop app reports itself as running forever, so a reconnect skips the prep hook and would capture a clone of the laptop panel. This is the single most important line in the supervisor. |
| Stream state is read from `/proc/<pid>/task/*/comm` (`session::video`, `session::audio`, `video::capture`) | `CLIENT DISCONNECTED` is not logged on an unclean drop, so parsing the log misses exactly the cases that matter. |
| Sunshine is found by `pgrep -f bin/sunshine`, never `pgrep -x sunshine` | nixpkgs' launcher execs `.sunshine-wrapped`, so `comm` reads `.sunshine-wrapp`. Matching the wrong thing tore down live streams during development. |
| `hyprctl output create` returning text is **success** | It prints `ok`. Treating output as failure silently skipped applying the mode. |
| Scale 1.6 only when both dimensions divide evenly (`W*5 % 8 == 0`) | Any other scale is rounded by Hyprland and lands the output in the wrong place. `2360x1640` → 1475x1025 ✔; `1920x1334` falls back to 1. |
| `stream_audio = disabled` | It is a second screen on the same desk; the speakers are on the host. |
| `sunshine.startLimitIntervalSec = mkForce 0` | The watcher restarts Sunshine on purpose, so a start limit would eventually refuse to restart it. |
| `LD_LIBRARY_PATH = /run/opengl-driver/lib` on the Sunshine unit | Without it the unit has no driver libs and cannot use NVENC. |

The output lands bottom-left of the existing layout (`x` of the leftmost monitor, `y` of the
lowest one) so it behaves like an extra panel on the floor of the desktop. Workspaces 16 and 17
belong to it (`ws.ip1` / `ws.ip2` in `nixos/home.nix`); `SUPER+CTRL+I` moves the focused
workspace there, `SUPER+CTRL+SHIFT+I` moves one window.

## Cable: usbmuxd mode 3 + a shared profile

Only a post-2022 `usbmuxd` can switch an iPad into CDC-NCM network mode, and upstream never
released it; nixpkgs' `1.1.1+date=2025-12-06` has it. Set as an environment variable because the
NixOS module fixes `ExecStart`:

```nix
services.usbmuxd.enable = true;
systemd.services.usbmuxd.environment.USBMUXD_DEFAULT_DEVICE_MODE = "3";   # CDC-NCM + multiplexor
```

The iPad then exposes **two** netdevs, and only one is the link:

| Netdev | Kernel name it registers as | Role |
|---|---|---|
| lower ifindex | `CDC NCM (Apple Tethering)` | the data function — this gets the profile |
| higher ifindex | `CDC NCM (Apple Private)` | Apple's multiplexor — set `unmanaged`, must stay out of NetworkManager |

Interface *numbers* cannot tell them apart (the naming is `enp0s20f0u9c5i2` / `…i4`, and the
port part changes per port, so the name is not stable either). Discovery is therefore by
scanning `/sys/class/net` for vendor `05ac` + driver `cdc_ncm` and taking the lowest ifindex.

`ipv4.method = shared` makes the host the iPad's DHCP server *and* gateway on `10.77.0.1/24`,
which is what lets one Moonlight host entry work on Wi-Fi and on the cable: packets the iPad
sends to the host's LAN or tailnet address arrive on the cable and are delivered locally.

### Why not a NetworkManager dispatcher

The first implementation used `networking.networkmanager.dispatcherScripts` with a `$2 = up`
guard. It cannot work, for two independent reasons:

- **It is a feedback loop.** Activating `ipad-usb` is itself a connection-lifecycle event, so the
  hook re-activated the connection that fired it. Measured on arch: 71 hook runs in two minutes,
  dnsmasq failing each round with `failed to create listening socket for 10.42.0.1: Address
  already in use`, and the activation ending in `failed for connection 'ipad-usb'`.
- **A cold interface fires nothing.** A newly appeared netdev matches no profile, so nothing
  activates and no `up` action is ever emitted. The NCM interfaces sat `disconnected` for hours.

The trigger is a udev rule on device arrival instead:

```
ACTION=="add", SUBSYSTEM=="net", ATTRS{idVendor}=="05ac", ATTRS{bInterfaceClass}=="02",
  DRIVERS=="cdc_ncm", RUN+="…/systemd-run --collect --quiet -- …/ipad-usb-attach"
```

The `systemd-run` hop exists because udev blocks until `RUN` commands return and `nmcli` can take
seconds. The script takes no interface argument on purpose: udev reports the **pre-rename** kernel
name (`usb0`), which no longer exists once predictable naming has run. It also waits for
NetworkManager to realize the device before binding the profile. `ipad-usb-attach` is on `PATH`
for manual recovery.

## Deskflow: Linux server, macOS client

Hyprland's portal implements `InputCapture` (what a server needs) but not `RemoteDesktop` (what a
client needs), so `arch` and `office` cannot share with each other — the MacBook is the client.
Clipboard sync needs the Clipboard portal, which does not exist yet; it will not work and is not a
bug to chase.

| Decision | Reason |
|---|---|
| No `uinput`, udev rules or setuid wrappers | Deskflow 1.27.0 injects and captures through libei and the portal only. |
| `~/.config/Deskflow/` is never managed declaratively | The GUI writes it; a read-only store symlink would break saving. |
| The unit is `static` (manual start) | You start the server on the machine you are sitting at. |
| `StartLimitBurst=5` / `StartLimitIntervalSec=60` | Without it an unstartable unit restarts forever: a missing `deskflow-server.conf` exits 4, and a core that is already running exits 5. That produced 149 restarts in ten minutes, each logging only `an instance of deskflow core is already running`. |
| macOS cask from `deskflow/tap`, with the tap marked `trusted = true` | The nixpkgs bundle is ad-hoc signed with no team ID, so every rebuild changes the cdhash and silently invalidates the Accessibility grant (Apple TN3127). The tap's DMG is Developer ID signed and notarized; Homebrew refuses untrusted third-party taps at activation. |

**The GUI and the unit both want port 24800.** The GUI starts its own core when you press Start,
which wins the port and makes the unit fail with `status=5`. The working pattern is: configure in
the GUI, **quit the GUI**, then `systemctl --user start deskflow`. The bar's `DF` widget reports a
core that is serving regardless of who started it, and refuses to toggle silently when the core
belongs to the GUI.

The server will not start at all until the GUI has saved a layout: it reads
`~/.config/Deskflow/deskflow-server.conf`, and a layout with only the host screen in it means there
is nowhere to place the client. The client's screen name must match exactly what Deskflow.app
reports on the Mac (the system hostname, which is not the tailnet name).

## Runbook

Per Linux host (once): switch to the branch, then

```
systemctl --user start sunshine ipad-display-watch     # both are wanted by graphical-session.target,
                                                       # but a unit installed mid-session is not started
ipad-display status                                    # output / sunshine / session / cable
```

The unit files appear at activation; because `graphical-session.target` is already active when a
new `WantedBy=` unit is installed, they do not start until the next login or an explicit `start`.

iPad (once): Moonlight (App Store `1000551566`) + Tailscale. Add **one** host entry per desktop
using its tailnet address (`arch` = `100.64.0.1`); that entry survives the cable going in or out,
because Tailscale's WireGuard endpoint roams while the inner 5-tuple stays identical. Pair with
the PIN from `https://localhost:47990`.

Mac (once): Deskflow.app → client → server `100.64.0.1` → grant Accessibility, Input Monitoring,
Local Network. If Gatekeeper calls it damaged: `xattr -dr com.apple.quarantine /Applications/Deskflow.app`.

## The MacBook wire (Deskflow's path)

Deskflow only moves pointer and keyboard events, so bandwidth is irrelevant and latency is
everything. Over the Mac's Wi-Fi the hop measured 20-330 ms with ~100 ms jitter. The Mac's USB
Ethernet adapter (an AX88179A, `en7` on macOS) plugged into `eno1` gives it a 1 Gb direct link:

- office declares it: `networking.networkmanager.ensureProfiles.profiles.macbook-link` — `eno1`,
  `ipv4.method = shared`, `10.99.0.1/24`, autoconnect priority 10 so it wins over NetworkManager's
  auto-created "Wired connection 1".
- The Mac leases a `10.99.0.10-254` address and reaches the server at `10.99.0.1`.
- NAT is deliberately **off**: the Mac keeps its internet on Wi-Fi, only `10.99.0.0/24` crosses
  the cable. (NetworkManager's `shared` mode installs no MASQUERADE rules on these hosts — only
  k3s's flannel/kube ones exist — so sharing internet this way would not have worked anyway.)

Two macOS traps, both seen in practice:

1. **A newly attached Ethernet service becomes the primary service**, so its DHCP gateway becomes
   the default route and the Mac loses internet. Order Wi-Fi first, once:

   ```
   sudo networksetup -ordernetworkservices "Wi-Fi" "AX88179A" "Thunderbolt Bridge" "Tailscale"
   ```

   macOS is subnet-aware, so `10.99.0.0/24` stays on-link over the wire while the default route
   and DNS go out Wi-Fi. The order persists across reboots.
2. **Tailscale can wedge** such that toggling it does nothing: `scutil --nc list` reports
   `(Connecting)`, no `100.64.0.0/10` routes appear, the CLI fails with `Tailscale.CLIError
   error 1`, and `/Library/Tailscale/ipn.log*.txt` stops advancing entirely. Restart the system
   extension (`sudo launchctl kickstart -k system/io.tailscale.ipn.macsys.network-extension`) or
   reboot. A user-initiated stop logs `Persistency disabled for stop reason userInitiated`; after
   that the app cannot bring the tunnel back until the extension is restarted.

## Verification

```
hyprctl monitors -j | jq -r '.[] | select(.name=="MOONLIGHT") | "\(.width)x\(.height)@\(.refreshRate) at \(.x)x\(.y) scale \(.scale)"'
ipad-display status --waybar     # one JSON object, exit 0
ip -br addr | grep 10.77.0.1     # cable link
nmcli -t device status | grep enp0s20   # data iface on ipad-usb, private one unmanaged
journalctl -b --since -1min | grep -c ipad-usb-attach   # 1-2, not dozens (a loop looks like dozens)
ss -ltn | grep 24800             # Deskflow serving
```

## Pitfalls seen in practice

| Symptom | Cause |
|---|---|
| iPad shows a mirror of the laptop panel | Sunshine restarted without the prep hook running, or `MOONLIGHT` was removed while a stream was live. Left-click the bar's iPad widget (`ipad-display recover`). |
| `iPad USB ○` stays while streaming | `cable:` is false — the NCM netdev is up but NetworkManager has not bound the profile. Run `sudo ipad-usb-attach`. |
| Deskflow unit cycles every 3 s | No `deskflow-server.conf` yet (exit 4), or the GUI's core owns the port (exit 5). |
| Bar says `DF` on but nothing listens | Should not happen: the widget checks for a running core, not just the unit. If it does, the core is running but failed to bind. |
