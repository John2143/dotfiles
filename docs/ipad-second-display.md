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

## Two Apple devices on one cable

Any Apple device switched into CDC-NCM is a client — an iPad or an iPhone alike, because
`USBMUXD_DEFAULT_DEVICE_MODE=3` is a daemon-wide default and both expose the same interface pair
(observed: an iPhone 16 Pro at `1-8.3`, `cfg=5`, as `usb0`/`usb1`). Only one can hold the link:
`ipad-usb` is a single connection on a single subnet, so the attach script serves one device and
marks every other Apple netdev `unmanaged`.

The choice is deterministic — **iPad before phone**, then the lowest ifindex — because the kernel
recycles ifindexes and raw ordering once let a charging phone take the screen's link. To promote a
specific device:

```
sudo ipad-usb-attach iPhone     # or iPad; no argument applies the preference above
```

The argument is a *model*, not an interface name: each device exposes a data function plus Apple's
private multiplexor, and only the former may carry the profile.

## The bar widget

`custom/ipad` runs `ipad-display status --waybar` and renders `iPad <link> <state>`:

| Text | Meaning |
|------|---------|
| `iPad USB ●` | cable attached, a stream is running |
| `iPad USB ○` | cable attached, idle |
| `iPad net ●` / `iPad net ○` | the same two states with no cable |

The class list carries the rest: `usb`/`net` (the cable state, `usb` shown in bold so it cannot mask
green), `streaming`/`idle`, plus `clone` (streaming with no `MOONLIGHT` — Sunshine is capturing the
laptop panel, click to recover), `stale` (output left behind) and `off` (Hyprland unreachable).
The tooltip holds the detail: `cable: 10.77.0.1/24 / iPad 10.77.0.56`, `stream: yes`, and the output
geometry. Left click is `ipad-display recover`, right click `ipad-display create`.

## The MacBook wire (Deskflow's path)

Deskflow only moves pointer and keyboard events, so bandwidth is irrelevant and latency is
everything. Over the Mac's Wi-Fi the hop measured 20-330 ms with ~100 ms jitter, against
sub-millisecond on a wire. The Mac reaches the desktop through a USB Ethernet adapter and a patch
cable (auto-MDIX on both ends, so any cable works), and either desktop serves it.

- Both hosts declare it: `services.macbookLink.interfaces` (`nixos/modules/macbook-link.nix`)
  emits one NetworkManager profile **per port** — office `["eno1"]`, arch `["enp7s0" "enp2s0f1"]`
  — each `ipv4.method = shared`, `10.99.0.1/24`, autoconnect priority 10, so it wins over
  NetworkManager's auto-created "Wired connection N".
- The Mac leases a `10.99.0.10-254` address and reaches the server at `10.99.0.1`, so **nothing on
  the Mac changes when the cable moves rooms**. nix-darwin appends `10.99.0.1 thunderbolt` to the
  Mac's `/etc/hosts`, so Deskflow can target a name instead of an address. The name is historical:
  this is plain Ethernet, not Thunderbolt. Until `darwin-rebuild` has run on the Mac, that entry
  does not exist — use the literal `10.99.0.1`.
- Shared mode **also provides NAT**, in its own nftables table (`table ip nm-shared-<iface>`,
  created when the link comes up, removed when it goes down). So the wire can carry the Mac's
  internet as well; whether it does is purely the Mac's service order. Check with
  `nft list ruleset | grep -A3 nm-shared` — `iptables -t nat` never shows NM's own table, which is
  what produced the earlier, wrong "shared mode does not NAT here" note.

### macOS traps, all seen in practice

1. **A newly attached Ethernet service becomes the primary service**, so its DHCP gateway becomes
   the default route. With NAT in place that is now merely a *choice*, not a breakage: keep the wire
   primary if you want the Mac's internet over the cable, or order Wi-Fi first if you would rather
   the desktop's uplink stayed out of the path:

   ```
   sudo networksetup -ordernetworkservices "Wi-Fi" "AX88179A" "Thunderbolt Bridge" "Tailscale"
   ```

   `-ordernetworkservices` requires **every** current service name, so run
   `networksetup -listallnetworkservices` first and pass the full list. The order persists across
   reboots. macOS is subnet-aware, so `10.99.0.0/24` stays on-link over the wire either way.
2. **A new adapter is a new service.** macOS keys a network service to the *chip*, so replacing the
   adapter (or adding a second one) creates a new entry that the command above does not mention.
   Re-run the ordering with the new name, and prune the old service if the old adapter is retired.
3. **A custom `system.activationScripts.<name>` never runs on nix-darwin.** The
   activate script concatenates a *fixed* list of names — `preActivation`, `checks`, `createRun`,
   `extraActivation`, `groups`, `users`, …, `homebrew`, `postActivation` — and never iterates the
   option, so a made-up name is accepted by the module system and silently does nothing. The
   `thunderbolt` hosts entry hid in such a name for a day. Put user snippets in
   `postActivation` (last, and after `/etc` is rewritten) and verify with
   `nix eval --raw .#darwinConfigurations.macbook.config.system.activationScripts.script.text | grep thunderbolt`
   — that assembled text is what actually executes.
4. **Tailscale can wedge** such that toggling it does nothing: `scutil --nc list` reports
   `(Connecting)`, no `100.64.0.0/10` routes appear, the CLI fails with `Tailscale.CLIError
   error 1`, and `/Library/Tailscale/ipn.log*.txt` stops advancing entirely. Restart the system
   extension (`sudo launchctl kickstart -k system/io.tailscale.ipn.macsys.network-extension`) or
   reboot. A user-initiated stop logs `Persistency disabled for stop reason userInitiated`; after
   that the app cannot bring the tunnel back until the extension is restarted.

### Bringing up a new Mac-side adapter (RTL8153 class)

The **host side needs nothing**: the profiles are per-port and all serve `10.99.0.1/24`, so a new
adapter on the Mac changes nothing on the desktop. All the risk is on macOS.

- **RTL8153 is the one chip with a bad reputation on Apple Silicon.** It is supported through
  Apple's `AppleUSBRealtek8153Patcher`, and there are current reports of dongles that enumerate
  but never become a usable interface on M-series Macs (macOS 15+), plus a documented case of a
  dongle stuck in "USB configuration 2, CDC ECM mode" that only works via a legacy-ECM workaround.
  Symptoms to distinguish:
  - `system_profiler SPUSBDataType | grep -i -A6 realtek` — is the dongle even enumerated?
  - `networksetup -listallhardwareports` — did a new "USB 10/100/1000 LAN" / RTL8153 port appear?
  - `ifconfig <if>` — a `169.254.x.x` self-assigned address means the interface exists but DHCP
    never reached the host; no interface at all means a driver problem, not our configuration.
- **Throughput depends on which mode the dongle presents.** Some RTL8153 units attach as CDC-ECM,
  which on macOS does not reach gigabit (2021 MacBook Pro owners report well under it); others
  attach as NCM and saturate the gigabit link. Irrelevant for Deskflow, which moves kilobytes per
  second, but visible on large file copies.
- **Do not assume `en4`/`en5`/`en6` are the dongle.** On this Mac those already exist as "Ethernet
  Adapter" hardware ports — Apple's hidden USB Device NCM interfaces. A new adapter shows up as its
  own port, typically named `USB 10/100/1000 LAN`.
- **The AX88179A is the known-good fallback.** If the new dongle misbehaves, the old adapter works
  on the same cable and the same port with no configuration change.
- Watch for the **"Allow accessories to connect"** prompt on first plug; the link stays down until
  it is approved.

Plug-in checklist, host side (either desktop):

```
nmcli device show enp7s0 | grep GENERAL.CONNECTION   # macbook-link-enp7s0, not "Wired connection N"
ip -br addr show enp7s0                              # 10.99.0.1/24
sudo cat /var/lib/NetworkManager/dnsmasq-enp7s0.leases
ping -c2 10.99.0.<lease>
ss -tnp | grep 24800                                 # peer must be 10.99.0.x, not 192.168.5.x
```

## Which path a stream takes (Wi-Fi vs cable)

The cable profile is `ipv4.method=shared`, so the iPad gets a `10.77.0.x` address from dnsmasq on the host and a route to `10.77.0.0/24` that is **directly connected** over the NCM interface. iPadOS sends to a directly connected subnet over that interface no matter which service is primary, and sends everything else over the primary service — which stays Wi-Fi while Wi-Fi is up.

So with the cable plugged in and Wi-Fi on:

| Moonlight entry | Path actually used |
|---|---|
| host LAN address (`192.168.5.x`) | Wi-Fi — the cable is ignored |
| host tailnet address (`100.64.0.x`) | Wi-Fi — Tailscale picks the primary service |
| `10.77.0.1` (the cable address) | **cable** — on-link over NCM |

That is why forcing the cable meant turning Wi-Fi off: with Wi-Fi gone, Tailscale roams its endpoint to the NCM interface and the tailnet entry streams over the cable. Nothing about Sunshine changes in either direction; it accepts the stream on whatever address it arrives on.

**There is no way to have two entries for one desktop.** Moonlight keys a host by the Sunshine instance's identity, so adding a second address for the same instance only *updates* the existing entry ("host updated") rather than creating a second tile. Switching paths therefore means editing the one entry's address, and the address must work on both paths — which `10.77.0.1` does not (it disappears with the cable).

**Making it automatic** needs the iPad to route a *permanent* address over the cable. Two candidates, neither implemented:

1. **Give the cable internet** — already true, and therefore not the lever. `shared` mode installs NAT in its own nftables table (`table ip nm-shared-usb0`: `ip saddr 10.77.0.0/24 ip daddr != 10.77.0.0/24 masquerade`), and a cabled device really does reach the internet through the host: `/proc/net/nf_conntrack` shows `src=10.77.0.56 dst=1.1.1.1` masqueraded to the host's LAN address while the iPhone was attached. iPadOS still keeps Wi-Fi primary with both up, and iOS exposes no service order to change that, so NAT alone does not make the cable win.
2. **Push a classless static route** so the iPad reaches the host's tailnet address *through the cable*: DHCP option 121, `100.64.0.1/32 via 10.77.0.1`. A `/32` beats Tailscale's `100.64.0.0/10`, so the entry keeps working unplugged over Wi-Fi and switches to the cable the moment it is plugged in — seamless, one entry, no NAT. NetworkManager's shared mode cannot do this: it exposes only `ipv4.shared-dhcp-range` and `shared-dhcp-lease-time`, no generic dnsmasq options, so this requires running our own dnsmasq instead of NM's.

**Reading the current path** while the iPad is attached:

```bash
tailscale status | grep -i ipad           # direct 10.77.0.x:... = cable, 192.168.5.x = Wi-Fi
watch -n1 "cat /sys/class/net/enp0s20f0u9c5i2/statistics/rx_bytes"   # moves while streaming over cable
```

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
