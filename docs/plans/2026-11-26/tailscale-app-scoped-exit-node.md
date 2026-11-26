# App-scoped Tailscale exit node on `arch` / `office` — scoping

Status: scoping only, nothing implemented. Written 2026-11-26 from the dotfiles
repo at `9c8fd1f` and read-only inspection of the live `arch` host
(Tailscale 1.104.6). No Tailscale state was changed and no exit node was
selected to produce this document; where a claim rests on reasoning rather than
observation it is marked **inferred**.

## 1. Summary and recommendation

Run a second, kernel-mode `tailscaled` inside a dedicated network namespace
(`tsexit`) on each desktop, give it its own tailnet identity (`arch-exit`,
`office-exit`), select exit nodes only on that instance, and launch the browser,
TeamSpeak and ad-hoc commands into the namespace with a small `tsexit-run`
wrapper. The host `tailscaled` — the one k3s, flannel, the subnet routes and
cluster DNS depend on — then never has an exit node selected, so cluster traffic
is isolated by construction rather than by a set of bypass rules that must stay
correct. TeamSpeak voice (UDP) works natively because the namespace has a real
TUN device and a real default route; no proxy is involved. The Noctalia
exit-node picker and status pill are repointed at the scoped instance's socket.
The costs are one extra headscale node per desktop, roughly 150 lines of Nix
plus about 40 changed lines in the status helpers, and the fact that scoped apps
no longer share the host's `localhost`. The single-daemon alternatives (policy
routing with marks, or `--exit-node-allow-lan-access` plus bypass rules) are
rejected as the primary design because they cannot scope DNS and because their
failure mode is the outage we are trying to remove.

## 2. Current behaviour and root cause

### 2.1 Topology (verified)

| Fact | Evidence |
| --- | --- |
| `arch` is a k3s **server** (control plane + etcd member) and runs pods. | `flake.nix:252` imports `nixos/modules/k3s-server.nix`; `systemctl is-active k3s` = `active`; 56 pod veths; `cni0 10.42.6.1/24`. |
| `office` is a k3s **agent** on Wi-Fi. | `flake.nix:221` imports `nixos/modules/k3s-agent.nix`; `nixos/office-configuration.nix:140-143`. Not inspected live. |
| Node LAN is `192.168.5.0/24` (`arch` = `.76`, API VIP `.10`). `192.168.6.0/24` is **not** on-link: it is the MetalLB LoadBalancer range, reached through the router `192.168.5.1`. | `ip -br addr`; `ip route get 192.168.6.20` → `via 192.168.5.1 dev enp2s0f0`; `nixos/modules/k3s-server.nix:74-77`. |
| Pod CIDR `10.42.0.0/16` + `fd42:42:42::/56`, service CIDR `10.43.0.0/16` + `fd42:42:43::/112`. Other nodes' pod /24s are reached via `flannel.1` in the **main** table. | `nixos/modules/k3s-net.nix:98-105`; `ip route show table main`. |
| `arch` advertises `192.168.5.0/24,192.168.6.0/24` and is currently the **primary** subnet router for `192.168.6.0/24`. `--accept-routes` is off. | `tailscale status --json` → `Self.PrimaryRoutes`; prefs `AdvertiseRoutes`, `RouteAll=false`. |
| Host DNS and cluster DNS both depend on the host `tailscaled`. | `resolvectl status tailscale0` → `100.100.100.100`, domains `ts.2143.me ~.`; `/etc/rancher/k3s/resolv.conf` = `nameserver 100.100.100.100` (`k3s-server.nix:42-48`). |
| Tailscale policy routing is the stock layout. | `ip rule`: `5210/5230/5250 fwmark 0x80000/0xff0000 …`, `5270 from all lookup 52`. Table 52 holds only tailnet /32s and `100.100.100.100` (no default, no throws). |
| `arch` has **no** pod-CIDR bypass rule. | No priority-2500 rule in `ip rule`. The rule exists only in `nixos/modules/k3s-agent.nix:100-126` (so `office` should have it, IPv4 pods only) and `nixos/github-configuration.nix:234-246`; `k3s-server.nix` has none. |
| No exit node is selected now. | `ExitNodeStatus: null`, prefs `ExitNodeID=""`, `ExitNodeAllowLANAccess=false`. |
| Exit-node candidates: `nas`, `vpin` (`mullvad-us-vpin-deccam`), four other `mullvad-*` nodes, `doks-us-nyc`, `apple-tv`, one offline Windows box. | `tailscale status --json`. |

### 2.2 How the exit node is toggled today (verified)

- `tailscale-exit-node` (`nixos/modules/status-helpers.nix:564-586`) lists peers
  with `ExitNodeOption`, pipes them through `noctalia dmenu`, then runs
  `sudo tailscale set --exit-node=<name> --exit-node-allow-lan-access` (or
  `--exit-node=` for None) against the **host** daemon.
- It is reached from the bar widget's right click
  (`noctalia-plugins/dotfiles-bar/tailscale.luau:41-43`) and from two buttons in
  the panel (`tailscale_panel.luau:253-259`, `:267-269`).
- `fish_functions/vc.fish` does the same from a terminal.
- `tailscale-status` (`status-helpers.nix:432-475`) and `tailscale-panel-data`
  (`:481-544`) read `tailscale debug prefs | jq .ExitNodeID` on the host daemon
  to draw the lock icon and the "Exit Node" card.

### 2.3 What selecting an exit node does on Linux (verified in source and docs, not exercised live)

Exit-node selection is all-or-nothing per `tailscaled`:

- The daemon adds `0.0.0.0/0` and `::/0` to its routes; on Linux those land in
  table 52, which rule 5270 consults for **every** packet that does not carry
  Tailscale's own bypass mark `0x80000`
  ([`local.go` routerConfig, v1.104.6](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/ipn/ipnlocal/local.go),
  [`router_linux.go`](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/wgengine/router/osrouter/router_linux.go)).
  There is no per-application selector; the feature request is open
  ([tailscale#12764](https://github.com/tailscale/tailscale/issues/12764)).
- With `--exit-node-allow-lan-access`, every non-loopback, non-/32 prefix
  configured on a local interface becomes a `throw` route in table 52, so those
  destinations fall through to the main table. Without the flag the same
  prefixes are added as routes **into** `tailscale0` ("so that we do not leak
  any traffic", same function). On `arch` the thrown prefixes would be
  `192.168.5.0/24`, `10.42.6.0/24` (`cni0`), `10.99.0.0/24` (`eno1`) and their
  IPv6 counterparts. Other nodes' pod subnets are single-address on `flannel.1`
  and are routed, not on-link, so they get **no** throw. A third party shows
  exactly this table on k3s + flannel
  ([tailscale#14706](https://github.com/tailscale/tailscale/issues/14706)).
- "When a device uses an exit node, it also uses that exit node as its DNS
  resolver for all domains"
  ([Tailscale: Use an exit node](https://tailscale.com/docs/features/exit-nodes/use)).
  In source: the exit node's DoH proxy replaces the default resolvers
  ([`node_backend.go` dnsConfigForNetmap](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/ipn/ipnlocal/node_backend.go)).

### 2.4 Which flows break on `arch`

Assumes the helper's flags (`--exit-node=X --exit-node-allow-lan-access`).
"Static" means derived from the live rule/route tables plus the source above;
nothing in this table was reproduced by toggling.

| # | Flow | Effect with an exit node selected | Basis |
| --- | --- | --- | --- |
| 1 | Node ↔ node on `192.168.5.0/24`: kubelet → API VIP, etcd peers, flannel VXLAN underlay, Longhorn, BGP to the router | Survives, **only because of the flag** (`throw`). If the exit node is ever selected without it (`tailscale up --exit-node`, another client), the LAN prefix is routed into the tunnel and the node drops out of the cluster. | Static (source) |
| 2 | Host or local pod → pod on another node (`10.42.{0..4}.0/24` via `flannel.1`) | **Black-holed.** Rule 5270 matches table 52's new default before the main table's flannel routes. Takes cross-node pod-to-pod, ClusterIP services with remote endpoints, and anything on `arch` that talks to CoreDNS/webhooks on another node with it. | Static; the repo already documents this failure and its fix for agents (`k3s-agent.nix:100-126`), and `arch` lacks that rule |
| 3 | Host → ClusterIP (`10.43.0.0/16`) or LoadBalancer VIP (`192.168.6.0/24`, e.g. Temporal `192.168.6.20:7233`) | Breaks whenever the backend pod is on another node (as flow 2 after kube-proxy DNAT); otherwise sent to the exit node, which for a Mullvad exit cannot reach the home LAN. | Inferred (kube-proxy rules not inspected) |
| 4 | Pod on `arch` → internet | Re-pathed through the exit node. New connections work with a different egress IP, more latency and a 1280 MTU; **connections that were open at the moment of the toggle hang** — routing is per packet, their NAT state belongs to the old path. The same happens again when the exit node is cleared. | Inferred; consistent with a Docker-host write-up where containers egress via the exit node ([blog.thms.uk](https://blog.thms.uk/2026/06/docker-tailscale-exit-node/)) |
| 5 | Host-network processes → internet (k3s image pulls, hostNetwork pods, agents) | Same re-path and same stall of open connections. | Inferred |
| 6 | DNS for the host **and** for pods whose CoreDNS forwards to `100.100.100.100` | Upstream resolution moves to the exit node's DoH proxy (Tokyo, Johannesburg, …); slower, and dead if the exit node is. Routing rules cannot fix this — it is inside `tailscaled`. | Source + docs; where CoreDNS replicas run was not checked |
| 7 | Tailnet clients → `192.168.6.0/24` via `arch` as primary subnet router | Forwarded packets also hit table 52's default, so remote access to cluster services through `arch` breaks for other tailnet devices. | Inferred |
| 8 | Tailnet peer traffic (`100.64.0.0/10`) | Unaffected (/32 routes in table 52). | Static |

Flows 2, 4 and 6 together match the report: "network drops and unrecoverable
errors in all the web worker processes". Long-lived worker connections either
lose their route (2), are silently re-pathed mid-stream (4), or lose DNS (6),
and clearing the exit node repeats the damage rather than undoing it.

### 2.5 Not verified

- The failure itself was not reproduced. `arch`'s `tailscaled` journal (kept
  since 2026-10-01) contains no `EditPrefs` line, so I could not find a recorded
  exit-node selection on `arch` in that window. The incident may have been on
  `office`, or earlier.
- `office` was not inspected. From the repo it has the priority-2500 rule for
  `10.42.0.0/16` only, which fixes flow 2 (and the cross-node part of 3) for IPv4 but none of 4–7.
- Whether clearing the exit node also resets `ExitNodeAllowLANAccess` (it reads
  `false` now).
- kube-proxy/flannel netfilter rules (need root to list).

## 3. Requirements

Must keep working, untouched by any exit-node action:

- k3s on the host: API VIP, etcd, kubelet, flannel VXLAN, MetalLB BGP, Longhorn.
- Pod-to-pod and pod-to-service traffic across nodes, IPv4 and IPv6.
- Pod and host egress paths, so long-lived worker connections are never
  re-pathed.
- Host and cluster DNS through `100.100.100.100` with its current upstreams.
- `arch`'s subnet-router role for `192.168.5.0/24` / `192.168.6.0/24`.
- Host tailnet access (`*.ts.2143.me`), NAS mounts, restic, remote builders.

Should use the exit node:

- A browser (Firefox is installed firejailed, `nixos/firejail-desktop.nix`).
- TeamSpeak 3 (Flatpak `com.teamspeak.TeamSpeak3`, `nixos/home.nix:608-618`).
  Voice is UDP 9987, file transfer TCP 30033
  ([TeamSpeak: server ports](https://support.teamspeak.com/hc/en-us/articles/360002712257-Which-ports-does-the-TeamSpeak-3-server-use);
  the same ports are in `nixos/cluster/modules/dual-ip-firewall.nix:94-97`).
  **UDP support is a hard requirement.**
- Arbitrary commands on demand (`<wrapper> curl …`, a game, a CLI).

Should also hold:

- No silent leak to the home IP when the exit node drops (or an explicit,
  chosen fail-open).
- DNS for scoped apps leaves with their traffic, not through the host resolver.
- The Noctalia picker and pill keep working and make the scope obvious.
- Works on Wayland/Hyprland with the existing launch path
  (`systemd-run --user --scope --slice=…`, `nixos/modules/cpu-priority.nix:44`).

## 4. Options compared

### 4.1 (a) Dedicated netns with its own kernel-mode `tailscaled` — recommended

A named namespace (`ip netns add tsexit`) joined to the host by a veth pair and
NATed out through the host's normal uplink. A second `tailscaled` runs inside it
with its own state directory and socket, creating `tailscale0`, table 52 and the
52xx rules **inside the namespace only**. Exit nodes are selected on that
instance. This is an established pattern
([Tailscale exit node with split tunnelling using namespaces](https://dev.to/nevon/tailscale-vpn-exit-node-with-split-tunneling-using-wireguard-and-namespaces-2lkj),
[Running Tailscale in a network namespace](https://gist.github.com/rajsinghtech/c279beb50a63f231457e7087525e8f52),
[Multi-tailnet with a netns](https://jamesguthrie.ch/blog/multi-tailnet-unlocking-access-to-multiple-tailscale-networks/)).

- **Launching apps:** anything started in the namespace is scoped, including
  its children. Wayland, PipeWire, D-Bus and the X11 path socket are filesystem
  Unix sockets and cross a network namespace; only *abstract* Unix sockets are
  namespace-scoped (the firejail manual makes the same distinction). Entry
  needs root for `setns`; `john` has passwordless sudo (`user-john.nix:36`), so
  a ~15-line wrapper does it. Firejail can also join a named namespace directly
  with `--netns=name`
  ([firejail(1)](https://man7.org/linux/man-pages/man1/firejail.1.html)); the
  installed firejail 0.9.82.2 lists that option.
- **UDP:** native. TeamSpeak sends ordinary UDP into a TUN device; the exit
  node NATs it like any other client's traffic.
- **DNS:** fully separable from the host (design in §5.4). Needs care: glibc
  apps would otherwise resolve through the host's `nscd`/`systemd-resolved`
  Unix sockets, and Flatpak apps get the host's `resolv.conf` regardless of the
  namespace ([flatpak#3564](https://github.com/flatpak/flatpak/issues/3564)).
- **Second node identity:** yes, one per desktop. Registered once against
  headscale (web approval or a pre-auth key,
  [headscale registration](https://headscale.net/stable/ref/registration)).
- **Subnet routes / MagicDNS:** the host is untouched. The scoped node is an
  ordinary tailnet peer; with `--accept-routes` it reaches `192.168.5/6.0/24`
  through the existing subnet routers even while an exit node is active.
- **Failure modes:** if the exit node goes away the default route stays in the
  namespace's table 52 and traffic is dropped, not leaked (the daemon keeps
  default routes "to avoid leaking traffic at the expense of functionality",
  `local.go` routerConfig). One extra `ip rule` makes "no exit node selected"
  fail closed too (§5.2). If any part of the namespace setup breaks, **only
  scoped apps lose connectivity**; the cluster cannot be affected.
- **NixOS:** one module, three units (netns, `tailscaled-exit`, a DNS stub), a
  NAT rule, a wrapper. About 150 lines.
- **Maintenance:** low. Nothing depends on Tailscale's rule priorities or marks
  outside the namespace. Two nodes per desktop to keep approved in headscale.

### 4.2 (b) Second userspace-networking `tailscaled` with SOCKS5/HTTP proxy

`tailscaled --tun=userspace-networking --socks5-server=localhost:1055
--outbound-http-proxy-listen=localhost:1055 --statedir=… --socket=…`
([userspace networking](https://tailscale.com/docs/concepts/userspace-networking);
all five flags are in `tailscaled --help` on `arch`). Runs unprivileged, even as
a user unit; own node identity; exit node selected with
`tailscale --socket=… set --exit-node=…`.

- **Launching apps:** per-app proxy configuration. Firefox: a profile with
  SOCKS5 `127.0.0.1:1055` and remote DNS. CLI: `ALL_PROXY=socks5://localhost:1055/`. Apps
  with no proxy setting cannot be scoped.
- **UDP:** `tailscaled`'s SOCKS5 server does implement UDP ASSOCIATE
  ([PR #12623](https://github.com/tailscale/tailscale/pull/12623), present in
  [`socks5.go` v1.104.6](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/net/socks5/socks5.go)),
  and the bug that dropped UDP replies for userspace exit-node clients
  ([tailscale#20064](https://github.com/tailscale/tailscale/issues/20064)) looks
  fixed in 1.104.6 (`net/tstun/wrap.go` records the flow). That does not help:
  the application must speak SOCKS5-UDP itself. Firefox's SOCKS client has no
  UDP support ([bug 1808692](https://bugzilla.mozilla.org/show_bug.cgi?id=1808692)),
  so HTTP/3 is not proxied and WebRTC bypasses the proxy
  ([bug 1624063](https://bugzilla.mozilla.org/show_bug.cgi?id=1624063)); I found
  no SOCKS setting for the TeamSpeak 3 client (not exhaustively checked).
  **Disqualified for TeamSpeak and for arbitrary apps.**
- **DNS:** good for proxied apps — SOCKS/HTTP dials resolve through the exit
  node's DoH proxy ([`tsdial.go`](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/net/tsdial/tsdial.go)).
- **Failure modes:** fail-open. Any app, or any part of an app, that ignores the
  proxy goes out the home connection silently.
- **NixOS:** one unit, ~25 lines, plus Firefox profile settings.
- **Maintenance:** lowest. Worth knowing as a browser-only fallback.

### 4.3 (c) One `tailscaled`, policy routing only for selected apps

Keep a single daemon, select the exit node on it (needed, as far as I can
tell: without a selected exit node the peer's WireGuard AllowedIPs do not
include `0.0.0.0/0`, so a hand-made default route into `tailscale0` would be
dropped — inferred, not tested), then invert the default with rules ahead of
5270:

```
5262: not <selector> lookup 52 suppress_prefixlength 0   # tailnet routes for everyone
5264: not <selector> lookup main                          # everything else stays local
5270: from all lookup 52                                  # Tailscale's; now only scoped traffic
```

`suppress_prefixlength` is standard `ip rule`
([ip-rule(8)](https://www.man7.org/linux/man-pages/man8/ip-rule.8.html)). The
selector is either a fwmark set per cgroup in an nftables `type route` output
chain (`socket cgroupv2 level N`,
[nft(8)](https://www.netfilter.org/projects/nftables/manpage.html)) — the same
shape Mullvad's Linux split tunnelling uses
([Mullvad: split tunnelling on Linux](https://mullvad.net/en/help/split-tunneling-with-linux-advanced)) —
or `iif <veth>` if the apps sit in a namespace behind a veth.

Tailscale's rules make this workable but brittle:

- The mark is applied after the socket has chosen its source address, so scoped
  traffic needs a reroute and a masquerade to the tailnet address, plus
  connmark handling for replies. The mark must avoid Tailscale's `0xff0000`
  byte (`0x80000` bypass, `0x40000` subnet SNAT) and kube-proxy's bits.
- The priorities 5210–5270, table 52 and the mark are source constants, not an
  interface. The daemon uses a different base priority on some systems
  (`router_linux.go`, `ipPolicyPrefBase`), and it rewrites its rules on its own
  schedule.
- **DNS cannot be scoped.** Selecting the exit node switches the host daemon's
  resolver to the exit node's DoH for the whole host and for cluster DNS
  (flow 6). Turning `--accept-dns` off instead removes the upstreams that
  `100.100.100.100` serves to pods.
- `tailscale status`, the panel and every other client still show the **host**
  as using an exit node.
- **Failure is the current outage.** If the custom rules are missing — unit
  failed, ordering race at boot, a future Tailscale change — the host falls
  straight back to "everything, including pods, through the exit node".

UDP works. No second identity. Roughly 80–120 lines of Nix across nftables, ip
rules for both families, and a cgroup launcher. High maintenance; needs a
re-test on every Tailscale and kernel update. Not recommended.

### 4.4 (d) `--exit-node-allow-lan-access` plus bypass rules for cluster CIDRs

What the helper already half does. Completing it means rules ahead of 5270 for
`to 10.42.0.0/16`, `to 10.43.0.0/16`, `to 192.168.5.0/24`, `to 192.168.6.0/24`
and their IPv6 equivalents, plus source rules so pod egress stays local — and
those need a `lookup 52 suppress_prefixlength 0` step first, or pods lose
`100.100.100.100` and every tailnet destination. Prior art:
`nixos/modules/k3s-agent.nix:100-126`, and third-party write-ups of the same idea
([blog.thms.uk](https://blog.thms.uk/2026/06/docker-tailscale-exit-node/)).

It does not meet the request: the exit node still applies to the whole host
(every terminal, every daemon), flows 5 and 6 remain (host-network connections
re-pathed on each toggle, host and cluster DNS moved to the exit node), and
`arch` still appears on the tailnet as a subnet router that is itself behind an
exit node. About 25 lines.

Worth doing anyway as **hardening**, independent of the main design: put the
complete rule set in `k3s-net.nix` so server nodes get it too. Then an
accidental host-level `tailscale set --exit-node` degrades DNS and egress
instead of partitioning the node.

### 4.5 (e) Other things looked at

- **systemd `NetworkNamespacePath=`**
  ([systemd.exec(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)) —
  not an alternative but the right way to put the *daemons* of option (a) into
  the namespace. For interactive apps it would mean transient system units,
  which leave the user session's cgroup tree and break the slice tiers in
  `cpu-priority.nix`; the sudo wrapper keeps apps in the caller's cgroup.
- **`RestrictNetworkInterfaces=`**
  ([systemd.resource-control(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)) —
  a cgroup-BPF allow-list of interfaces. Useful only as a kill switch on top of
  (c); it selects nothing by itself.
- **Rootless user namespace + `pasta`/`slirp4netns`** ([passt](https://passt.top/)) —
  a kernel-TUN `tailscaled` inside an unprivileged user+net namespace, no host
  configuration at all. Apps then run inside a user namespace, which interacts
  badly with setuid firejail and adds a second sandbox layer under Flatpak. We
  have root via NixOS, so this buys nothing.
- **The SOCKS5 proxies already on the Mullvad exit nodes** (`microsocks` bound
  to the tailnet address on port 1080, `nixos/modules/mullvad.nix:633-656`,
  e.g. `mullvad-us-vpin-deccam.ts.2143.me:1080`). A Firefox profile can use one
  today with no change on `arch` and no exit node selected anywhere. TCP only
  as far as I can tell ([microsocks#58](https://github.com/rofl0r/microsocks/issues/58),
  not read in detail), so it is a browser stopgap, not a TeamSpeak answer.
- **Tailscale app connectors** — route by destination domain through a
  connector node, suggested by Tailscale on the per-app request
  ([tailscale#12764](https://github.com/tailscale/tailscale/issues/12764)).
  Per-domain rather than per-app, and I did not check whether headscale
  implements them.
- **Plain WireGuard-in-netns tools** (e.g. [vopono](https://github.com/jamesmcm/vopono/blob/master/USERGUIDE.md)) —
  same namespace idea but straight to a VPN provider, bypassing the tailnet's
  exit nodes (`nas`, `doks-us-nyc`, the `mullvad-*` hosts) and the existing
  picker.

### 4.6 Comparison

| | (a) netns + 2nd kernel `tailscaled` | (b) userspace + SOCKS5 | (c) one daemon + marks | (d) LAN access + bypass rules |
| --- | --- | --- | --- | --- |
| Scope | Any process launched in the namespace | Only proxy-aware apps | Any process in a cgroup / behind a veth | Whole host |
| TeamSpeak voice (UDP) | Yes, native | **No** | Yes | Yes (but host-wide) |
| Arbitrary command | Yes | Only if it honours a proxy | Yes | n/a |
| DNS for scoped apps | Separate, exits with traffic | Via exit node (proxied apps) | **Shared with host and cluster** | Shared with host and cluster |
| Host/cluster DNS untouched | Yes | Yes | No | No |
| Second tailnet node | Yes | Yes | No | No |
| Long-lived cluster connections | Never re-pathed | Never re-pathed | Safe while rules hold | Host-network flows re-pathed |
| If the mechanism fails | Scoped apps go offline | App leaks to home IP | **Whole host, pods included, goes through exit node** | Same as today |
| Leak when exit node drops | No (fail closed) | No for proxied flows; non-proxied flows always leak | Depends on an extra rule | No |
| Coupling to Tailscale internals | None on the host | None | Rule priorities, table, marks | Rule priority |
| Nix, roughly | ~150 lines | ~25 lines | ~100 lines | ~25 lines |
| Maintenance | Low | Lowest | High | Low |

## 5. Recommended design

### 5.1 Architecture

```
host netns (unchanged)                         netns "tsexit"
────────────────────────────────────           ─────────────────────────────────────
tailscaled  (node "arch")                      tailscaled-exit (node "arch-exit")
  never selects an exit node                     exit node selected here
  subnet router, MagicDNS, k3s resolv.conf       tailscale0, table 52, rules 52xx
k3s, flannel, cni0, pods                       tsexit-dns  127.0.0.53:53
enp2s0f0 192.168.5.76 ── uplink                apps: firefox (exit profile),
ve-tsexit 10.200.200.1/30 ◄──── veth ────►     eth0 10.200.200.2/30   TeamSpeak, tsexit-run …
  MASQUERADE 10.200.200.2 → uplink             default via 10.200.200.1 (underlay)
```

- The veth is the **underlay** only: the scoped `tailscaled` uses it for
  WireGuard, DERP and the control connection to `https://net.john2143.com`. Its
  sockets carry Tailscale's bypass mark
  ([`netns_linux.go`](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/net/netns/netns_linux.go))
  and are owned by root.
- Application traffic in the namespace is unmarked, so it meets the namespace's
  own rule 5270 → table 52 → `tailscale0` → exit node.
- `10.200.200.0/30` is free on `arch` (`ip route get 10.200.200.2` currently
  resolves to the default route) and clear of `10.42/16`, `10.43/16`,
  `10.99.0.0/24`, `192.168.5–6.0/24` and `100.64.0.0/10`.
- Host firewall: no new INPUT openings. Scoped apps cannot reach host services
  over the veth; they reach the host by its tailnet name like any other peer.

### 5.2 NixOS module sketch

New file `nixos/modules/tailscale-exit-scope.nix`, imported by `arch` and
`office` in `flake.nix`, with a `custom.tsExit.enable` switch and options for
the addresses, node hostname, kill switch and upstream resolver. Illustrative,
untested:

```nix
{ config, lib, pkgs, ... }: let
  ns = "tsexit";
  sock = "/run/tailscale-exit/tailscaled.sock";
  inNs = { NetworkNamespacePath = "/run/netns/${ns}"; };
in {
  systemd.services.tsexit-netns = {
    wantedBy = ["multi-user.target"];
    path = [pkgs.iproute2];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ip netns add ${ns}
      ip link add ve-tsexit type veth peer name eth0 netns ${ns}
      ip addr add 10.200.200.1/30 dev ve-tsexit
      ip link set ve-tsexit up
      ip -n ${ns} link set lo up
      ip -n ${ns} addr add 10.200.200.2/30 dev eth0
      ip -n ${ns} link set eth0 up
      ip -n ${ns} route add default via 10.200.200.1
      # Kill switch: only root (tailscaled) may fall through to the underlay.
      # Everything else must match table 52 (rule 5270) or fail immediately.
      ip -n ${ns}    rule add pref 6000 uidrange 1-4294967294 unreachable
      ip -n ${ns} -6 rule add pref 6000 uidrange 1-4294967294 unreachable
    '';
    preStop = "ip netns del ${ns}";   # removes the veth pair with it
  };

  # Same pattern as modules/mullvad.nix:467-472.
  networking.firewall.extraCommands = ''
    iptables -t nat -A POSTROUTING -s 10.200.200.2/32 ! -o ve-tsexit -j MASQUERADE
  '';
  networking.networkmanager.unmanaged = ["interface-name:ve-tsexit"];
  services.avahi.settings.server.deny-interfaces = ["ve-tsexit"];

  systemd.services.tailscaled-exit = {
    after = ["tsexit-netns.service" "network-online.target"];
    bindsTo = ["tsexit-netns.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = inNs // {
      StateDirectory = "tailscale-exit";
      RuntimeDirectory = "tailscale-exit";
      # Private, plain resolv.conf: see 5.4.
      BindReadOnlyPaths = ["${pkgs.writeText "tsexit-bootstrap-resolv.conf" "nameserver 1.1.1.1\n"}:/etc/resolv.conf"];
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --statedir=/var/lib/tailscale-exit --socket=${sock}";
      ExecStopPost = "${pkgs.tailscale}/bin/tailscaled --cleanup --socket=${sock}";
      Restart = "on-failure";
    };
  };

  systemd.services.tsexit-dns = {
    after = ["tsexit-netns.service"];
    bindsTo = ["tsexit-netns.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = inNs // {
      DynamicUser = true;                       # non-root, so the kill switch applies
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --no-resolv --no-hosts"
        "--listen-address=127.0.0.53 --bind-interfaces"
        "--server=/ts.2143.me/100.100.100.100 --server=9.9.9.9"
      ];
    };
  };
}
```

Notes on the sketch:

- `--statedir`, `--socket` and `--cleanup` are `tailscaled` flags on this
  machine ([tailscaled reference](https://tailscale.com/docs/reference/tailscaled));
  `--tun` is left at its default (`tailscale0`), which is free inside the
  namespace. `services.tailscale` in nixpkgs is single-instance, hence the
  hand-written unit; copy its `path`/hardening when implementing.
- The `uidrange … unreachable` rule sits at 6000, after Tailscale's 5270 and
  before `main` at 32766, and outside the 52xx band the daemon manages. It is
  what makes "no exit node selected" and "exit node gone" both fail closed. Make
  it an option; dropping it gives fail-open behaviour (scoped apps use the home
  connection whenever no exit node is selected).
- One-time registration per host, by hand, no secret in the repo:

  ```
  sudo tailscale --socket=/run/tailscale-exit/tailscaled.sock up \
    --login-server=https://net.john2143.com --hostname=arch-exit \
    --accept-dns=false --accept-routes --operator=john
  ```

  then approve the node in headscale. All flags are in `tailscale up --help`
  here. `--operator=john` lets the picker run `tailscale set` without sudo.
- **Never** point this daemon at the host's `resolv.conf`; see §5.4.

### 5.3 App launch model

A `tsexit-run <command> [args…]` wrapper in `environment.systemPackages`:

```
sudo -E  →  nsenter --net=/run/netns/tsexit
         →  unshare --mount   (private mount namespace)
              mount --bind /dev/null /run/nscd/socket
              mount --bind /dev/null /run/systemd/resolve/io.systemd.Resolve
         →  setpriv --reuid=<caller> --regid=<caller> --init-groups --inh-caps=-all
         →  exec "$@"
```

`nsenter`, `unshare` and `setpriv` are util-linux and already on the system
path. The process stays in the caller's cgroup, so the wrapper composes with the
existing slice launcher: `systemd-run --user --scope --slice=games.slice --
tsexit-run firefox …`. The wrapper must restore `HOME`, `USER`, `LOGNAME` and
pass the session environment through (`sudoers` grants `SETENV`, so `-E` is
allowed); it must not set no-new-privileges, because the `firefox` on `PATH` is
the setuid firejail wrapper.

- **Firefox:** a separate profile and instance, otherwise the launch is handed
  to the already-running host-namespace Firefox:
  `tsexit-run firefox --no-remote -P exit --name firefox-exit`. Add an
  `xdg.desktopEntries` entry "Firefox (exit node)" next to the existing one in
  `cpu-priority.nix`. The distinct `--name` gives Hyprland an app id to style
  (a coloured border makes the scope visible).
- **TeamSpeak:** `tsexit-run flatpak run com.teamspeak.TeamSpeak3`. Flatpak's
  sandbox shares the network namespace it is started from. Two knock-on
  changes: the ClientQuery plugin listens on `127.0.0.1:25639` *inside* the
  namespace, so `teamspeak-mute-proxy` (`nixos/modules/teamspeak.nix:493`) must be
  started through `tsexit-run` as well (its Unix socket in `$XDG_RUNTIME_DIR`
  stays reachable from the bar and keybinds); and TeamSpeak has to be quit and
  relaunched to move between scoped and unscoped.
- **Ad hoc:** `tsexit-run curl …`, `tsexit-run fish` for a scoped shell.

What scoped apps lose: the host's loopback. A scoped browser cannot open
`localhost:3000` on the host; use `arch.ts.2143.me:3000` (the service must
listen beyond loopback) or the unscoped browser.

### 5.4 DNS

Three separate problems, each with a specific answer.

1. **The scoped daemon must not touch the host resolver.** On start
   `tailscaled` inspects `/etc/resolv.conf`
   ([`manager_linux.go`](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/net/dns/manager_linux.go));
   seeing systemd-resolved it would configure the host's resolved over D-Bus,
   addressing links by interface index
   ([`resolved.go`](https://raw.githubusercontent.com/tailscale/tailscale/v1.104.6/net/dns/resolved.go):
   `SetLinkDNS`, `RevertLink`) — the index of *its* `tailscale0` inside the
   namespace, which on the host is some unrelated NIC (index 3 is `eno1` on
   `arch`; the host's own `tailscale0` is 7). A third party running
   `tailscaled` in a namespace reports it rewriting the namespace's
   `resolv.conf` when DNS is accepted
   ([dev.to write-up](https://dev.to/nevon/tailscale-vpn-exit-node-with-split-tunneling-using-wireguard-and-namespaces-2lkj)).
   A private plain-text `resolv.conf` in the unit forces "direct" mode, and
   `--accept-dns=false` means it never writes one. The file points at a public
   resolver over the underlay so the daemon can resolve the control server
   before any tunnel exists (it runs as root, so the kill switch does not apply
   to it).
2. **Scoped apps need a resolver that works for native, firejailed and Flatpak
   apps alike.** The host's `resolv.conf` says `nameserver 127.0.0.53`, and
   Flatpak hands sandboxes the host's file whatever namespace they start in
   ([flatpak#3564](https://github.com/flatpak/flatpak/issues/3564)). So rather
   than fight over the file, answer on that address **inside the namespace**:
   `tsexit-dns` listens on the namespace's own `127.0.0.53`. It forwards
   `ts.2143.me` to the scoped daemon's `100.100.100.100` (MagicDNS records are
   served even with `--accept-dns=false`: hosts are populated before the
   accept-DNS early return in `dnsConfigForNetmap`) and everything else to a
   public resolver. That query is ordinary unmarked traffic, so it travels
   through the exit node and is blocked by the kill switch when there is none.
3. **glibc must not resolve through the host.** On NixOS `getaddrinfo` goes to
   `nscd` over `/run/nscd/socket` (present and active on `arch`), and
   `nsswitch.conf` lists `resolve`, which talks to systemd-resolved over another
   Unix socket. Both are filesystem sockets, both live in the host namespace,
   and both would resolve scoped apps' names on the host's connection — a DNS
   leak that also returns the host's view of the world. The wrapper masks both
   sockets in a private mount namespace; glibc then falls back to in-process
   `files` and `dns`, which reads `resolv.conf` and reaches the stub from (2).

Alternative for (2): leave `--accept-dns` on and forward everything to
`100.100.100.100`, so non-tailnet names resolve through the exit node's DoH
proxy. Fewer moving parts in the stub, but the daemon then wants to manage
`resolv.conf`, and resolution depends on each exit node's proxy. Start with the
explicit split above.

### 5.5 Noctalia panel and pill

All of it is in the helper scripts; the Luau changes are cosmetic. Scoped mode
is on when `/run/tailscale-exit/tailscaled.sock` exists, so hosts without the
module keep today's behaviour unchanged.

- `tailscale-exit-node` (`status-helpers.nix:564-586`): read candidates from,
  and apply the choice to, `tailscale --socket=/run/tailscale-exit/tailscaled.sock`.
  Drop `sudo` (operator is `john`) and drop `--exit-node-allow-lan-access` (the
  namespace's only "LAN" is the veth). Prompt text "Exit node (scoped apps)".
  If the scoped instance is not `Running`, `notify-send` instead of silently
  doing nothing.
- `tailscale-panel-data` (`:481-544`): tailnet, self and peer list stay from
  the host daemon. `exit_id`, `exit_name`, `exit_ip` come from the scoped
  daemon (same `debug prefs | jq .ExitNodeID` technique with `--socket`; peer
  IDs are stable node IDs, so the existing `select(.ID == $eid)` lookup still
  works). Add `exit_scope` (`"apps"` or `"host"`) and `scoped_state`.
- `tailscale-status` (`:432-475`): lock icon and tooltip line
  `Exit (apps only): <name>` from the scoped daemon. Tooltips are plain text,
  which this already is. Add one more state: if the **host** daemon reports an
  exit node, show a warning class and say so — that is now always a mistake.
- `tailscale_panel.luau:243`: section title becomes "Exit Node (scoped apps)"
  when `d.exit_scope == "apps"`. The fallback path that parses raw
  `tailscale status --json` (`:45-111`) needs no change. `tailscale.luau` needs
  none: right click still runs `tailscale-exit-node`.
- `fish_functions/vc.fish`: same retarget, or it remains a way to put the whole
  host behind an exit node by accident.
- "Toggle Connect" keeps acting on the host daemon.
- Widgets are instantiated once per monitor; each poll becomes two LocalAPI
  calls instead of one, which is negligible.
- `docs/noctalia-migration/*.md` describe these helpers and need a matching
  edit when this is implemented.

### 5.6 Interaction with existing routes and MagicDNS

- Host: no change to rules, table 52, resolved, `K3S_RESOLV_CONF`, advertised
  routes or primary-router status. The host peers with `arch-exit` like any
  other node, directly over the veth.
- Scoped node with `--accept-routes`: `192.168.5.0/24` and `192.168.6.0/24` are
  more specific than the exit default, so home and cluster addresses stay
  reachable from the scoped browser through the subnet routers while an exit
  node is active (for `192.168.6.0/24` that is currently the `arch` host
  itself — a hairpin across the veth, which is fine). Without `--accept-routes`
  those addresses go to the exit node and are unreachable from a Mullvad exit.
- The scoped daemon's own underlay to LAN peers is unaffected by accepted
  routes: its sockets carry the bypass mark and use the namespace's main table.
- New MagicDNS names `arch-exit.ts.2143.me` / `office-exit.ts.2143.me`.

## 6. Risks and open questions for John

Decisions only you can make:

1. **Second node identity.** One extra headscale node per desktop
   (`arch-exit`, `office-exit`), registered once by hand. User-owned or tagged
   (e.g. `tag:exit-client`)? Does your headscale policy let a new node use the
   exit nodes and the subnet routes, and what key expiry applies to it?
2. **Which apps, and how.** A dedicated "Firefox (exit node)" profile beside
   your normal Firefox (recommended start), or your main Firefox always inside
   the namespace? TeamSpeak always scoped, or a second launcher?
3. **Fail closed or fail open.** With the kill switch, scoped apps have no
   internet unless an exit node is selected and reachable. Without it they fall
   back to the home connection. Recommended: closed.
4. **Reach of scoped apps.** Should the exit browser still reach home and
   cluster addresses (`--accept-routes` on), or be isolated from them?
5. **Resolver for scoped DNS.** Quad9 in the sketch; Cloudflare, Mullvad's, or
   the exit node's own proxy are equally easy.
6. **Host-level exit node.** Remove it from the UI entirely (recommended), or
   keep an explicit "whole host" action behind a warning? Either way, do you
   want the complete bypass rule set from §4.4 on all k3s nodes as a safety
   net?
7. **Where and when did the outage happen?** `arch`'s journal shows no
   exit-node selection since 2026-10-01. Knowing the host and the affected
   namespace/workers picks the validation targets in §7.

Technical risks (all testable before rollout):

- Nothing here was run. Specific unknowns: `BindReadOnlyPaths` onto
  `/etc/resolv.conf`, which is a symlink chain on NixOS (fallback: start the
  daemon through `ip netns exec` with `/etc/netns/tsexit/resolv.conf`,
  [ip-netns(8)](https://www.man7.org/linux/man-pages/man8/ip-netns.8.html));
  environment passthrough through `sudo -E`; firejail started from inside the
  wrapper; Flatpak TeamSpeak's X11 and audio from inside the namespace;
  `100.100.100.100` answering MagicDNS names with `--accept-dns=false` (read
  from source, not observed).
- The host FORWARD path for `10.200.200.2` was not inspected (kube-proxy and
  flannel rules need root to list). Expected to be accepted; verify.
- A new host interface (`ve-tsexit`) on a k3s node. `arch` pins `--node-ip` and
  avahi's interface list, so nothing should latch onto it; `office` relies on
  autodetection and gets the avahi deny entry in the sketch. Check after the
  first boot.
- The kill switch keys on uid: anything run as root inside the namespace
  bypasses it. `tsexit-run` always drops to the caller, so this only matters
  for `sudo ip netns exec` by hand.
- TeamSpeak reconnects when the exit node is changed mid-call (its UDP source
  address changes). Expected, and limited to scoped apps.
- A scoped daemon outage takes scoped apps offline. That is the intended
  trade: the blast radius moves from the cluster to the browser.

## 7. Validation plan

Run on `arch` first, with worker pods live. `S=/run/tailscale-exit/tailscaled.sock`.

Baseline, before selecting anything:

```
ip rule > /tmp/rules.before; ip route show table 52 > /tmp/t52.before
resolvectl status tailscale0
kubectl get pods -A -o wide --field-selector spec.nodeName=arch   # note RESTARTS
kubectl get nodes
```

Start long-lived probes and leave them running through every step below:

```
kubectl get nodes -w
kubectl -n <workers-ns> logs -f <a-worker-pod>
kubectl exec -n <ns> <pod-on-arch> -- sh -c 'while :; do nc -zw2 <pod-ip-on-another-node> <port> || date; sleep 1; done'
ssh nas 'while :; do date; sleep 1; done'          # host long-lived TCP over LAN
```

Select an exit node on the scoped instance, then switch between three of them
and back to none, five times:

```
tailscale --socket=$S set --exit-node=mullvad-us-vpin-deccam
```

Host and cluster untouched (all must hold while the scoped exit node is active):

```
ip rule | diff - /tmp/rules.before                 # no difference
ip route show table 52 | diff - /tmp/t52.before    # no default, no throw
tailscale status --json | jq .ExitNodeStatus       # null
tailscale debug prefs | jq -r .ExitNodeID          # empty
ip route get 10.42.0.5                             # dev flannel.1
ip route get 192.168.6.20                          # via 192.168.5.1 dev enp2s0f0
ip route get 1.1.1.1                               # dev enp2s0f0
curl -s https://ipinfo.io                       # home IP
kubectl exec -n <ns> <pod-on-arch> -- wget -qO- https://ipinfo.io   # home IP
resolvectl status tailscale0                       # unchanged from baseline
```

plus: none of the probes printed a gap, no node went NotReady, RESTARTS on
`arch`'s pods are unchanged, and a phone on cellular still reaches a
`192.168.6.x` service through the tailnet.

Scoped apps exit via the exit node:

```
tsexit-run curl -s https://ipinfo.io            # exit node's public IP
tsexit-run getent hosts example.org                # resolves
tsexit-run getent hosts nas.ts.2143.me             # MagicDNS works
sudo ip netns exec tsexit ip route get 1.1.1.1     # dev tailscale0 table 52
```

UDP and TeamSpeak:

```
sudo tcpdump -ni enp2s0f0 udp port 9987 &          # host uplink: must stay silent
sudo ip netns exec tsexit tcpdump -ni tailscale0 udp port 9987   # shows voice packets
```

with TeamSpeak launched through `tsexit-run`, connected and talking; the server
should list the client under the exit node's address, and the mute keybinds
(`teamspeak-mute-status --toggle`) must still work.

Leaks:

```
tailscale --socket=$S set --exit-node=
tsexit-run curl -m 5 -s https://ipinfo.io       # must FAIL (fail closed)
sudo tcpdump -ni enp2s0f0 'port 53 or port 853' &  # then, with an exit node selected:
resolvectl monitor &
tsexit-run getent hosts leaktest-$RANDOM.example.org
```

The name must not appear in `resolvectl monitor` (proves the nscd and
nss-resolve paths are closed). Select an exit node that is offline and confirm
scoped `curl` fails rather than returning the home IP. In the scoped Firefox,
confirm a WebRTC leak test shows only the exit address.

UI: the pill shows the lock with "Exit (apps only): …", the panel card shows
the scoped exit node, the picker changes it without a sudo prompt, and all of it
reverts to today's behaviour on a host without the module.

Repeat the host-untouched block on `office`.

## 8. Rough effort

Short-to-Medium, about one working day end to end.

| Piece | Size | Time |
| --- | --- | --- |
| `nixos/modules/tailscale-exit-scope.nix` (netns, daemon, DNS stub, NAT, wrapper) | ~150 lines | 3–4 h |
| `status-helpers.nix`, `tailscale_panel.luau`, `vc.fish` retarget | ~40 changed lines | 1 h |
| Desktop entries, scoped `teamspeak-mute-proxy` | ~25 lines | 0.5 h |
| Validation on `arch` (§7), fixes for the unknowns in §6 | — | 2–3 h |
| Rollout to `office`, docs touch-up | — | 1 h |
| John, by hand: register and approve two nodes in headscale, pick answers to §6 | — | 15 min |

Optional and separate: the §4.4 hardening rules in `k3s-net.nix`, ~25 lines,
1 h plus a rolling check on each k3s node.
