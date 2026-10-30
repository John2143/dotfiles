# Topology and switch ports

Physical cabling and per-device identity. Re-derive with `scripts/network-snapshot.sh`, or
live with `/ip neighbor print` on each MikroTik.

## Backbone

```
Router (RB5009) —10G— Core (CRS305) —10G— Upstairs-Core (CRS305) —10G— Upstairs (CRS310)
   │                    │
   └─core-poe → ether1  ├─10G→ NAS
     (PoE + 1G mgmt)    └─10G→ Office (CRS310)
```

The core switch is powered by the router's `core-poe` port. **A router reboot power-cycles the
core**, and with it every 10G path. That is by design; it is not a fault.

## Devices

| Device | Alias | IP | Model | S/N |
|---|---|---|---|---|
| Router | `r` | 192.168.5.1 | RB5009UPr+S+ | HKG0AWJZPCK |
| Core | `c` | 192.168.5.4 | CRS305-1G-4S+ r2 | HMC0B8ZZ7F2 |
| Upstairs | `u` | 192.168.5.3 | CRS310-8G+2S+ | HKG0AVERD3V |
| Office | `o` | 192.168.5.2 | CRS310-8G+2S+ | HKG0AJ14YM5 |
| Upstairs-Core | `uc` | 192.168.5.5 | CRS305-1G-4S+ r2 | HMB0BED9WV8 |

Verify identity before operating: `/system routerboard print` (model + serial) and
`/system resource print` (RouterOS version). They are different commands and answer different
questions.

## Port map

Verified 2026-10-29 from the leaf switch's bridge host table, LLDP/MNDP and link-flap timing.
The router ports were renamed and commented the same day. Select them with
`[find default-name=etherN]`, which never changes, rather than by name.

### Router (RB5009)

| Name (default) | Peer | Notes |
|---|---|---|
| `2GWAN` (ether1) | Verizon CR1000B, 2.5G | WAN. PoE probe reports `short-circuit`; nothing is powered |
| `core-poe` (ether2) | Core ether1 | Powers the core switch (~10 W) and carries 1G mgmt. **Never `poe-out=off`** |
| `ether3` | unconfirmed | Link up, no MAC learned. Flaps coincide with nas reboots |
| `jetkvm` (ether4) | JetKVM 192.168.5.187 | 100M is normal for this device |
| `u7-lite` (ether5) | U7 Lite AP | PoE ~5 W. The U7 Mesh uplinks wirelessly to it |
| `ether6` | — | empty |
| `cam-front` (ether7) | Front driveway camera 192.168.1.66 | Camera has its own power |
| `pite` (ether8) | pite 192.168.5.9 (k3s agent) | Was named `to-wifi`; pite is **not** on the office switch |
| `10GsfpLAN` (sfp-sfpplus1) | Core sfp-sfpplus4 | 10G DAC |

### Switches

| Switch | Port | Peer |
|---|---|---|
| Core | ether1 | Router `core-poe` (PoE-in + mgmt) |
| Core | sfp-sfpplus1 | NAS 10GbE (`bond0` → `enp1s0f1`) |
| Core | sfp-sfpplus2 | Upstairs-Core sfp-sfpplus2 |
| Core | sfp-sfpplus3 | Office sfp-sfpplus2 |
| Core | sfp-sfpplus4 | Router `10GsfpLAN` |
| Upstairs-Core | ether1 | GL-KVM 192.168.5.8 |
| Upstairs-Core | sfp-sfpplus1 | closet 10G |
| Upstairs-Core | sfp-sfpplus2 | Core |
| Upstairs-Core | sfp-sfpplus3 | arch, **10G** (ixgbe; not 2.5G) |
| Upstairs-Core | sfp-sfpplus4 | Upstairs sfp-sfpplus1 |
| Upstairs | ether1 | Reolink NVR (feeds the wired cameras) |
| Upstairs | ether2 | R740 (bigp) onboard LOM: link only, no MACs learned |
| Upstairs | ether4 | Bedroom lightswitch 192.168.5.85, 1G |
| Upstairs | ether5 | R740 iDRAC 192.168.5.254 |
| Upstairs | ether6 | Brother printer 192.168.5.6, 100M half duplex |
| Upstairs | ether8 | vpin 192.168.5.118 (Raspberry Pi), 100M |
| Upstairs | sfp-sfpplus1 | Upstairs-Core |
| Upstairs | sfp-sfpplus2 | bigp 10G (Proxmox; VMs `big` .68 and UniFi OS .30) |
| Office | sfp-sfpplus1 | U7 Pro XGS, 10G over a 6COM `6C-SFP-10G-T` copper module |
| Office | sfp-sfpplus2 | Core |
| Office | ether1–8 | all down |

The DACs (Cable Matters) report no DDM, so `sfp-rx-power` is always empty.

## Flaps that are expected

- Upstairs `ether2`, `ether5` and `sfp-sfpplus2` drop on every R740 power cycle. During POST loops
  ether2 can flap every ~40 s.
- Core `sfp-sfpplus1` and router `ether3` drop when nas reboots. A nas shutdown can hang ~11 min on
  ZFS/iSCSI unmounts before it resets.
- Upstairs-Core `sfp-sfpplus3` drops when arch reboots.
- Upstairs `ether1` and Upstairs-Core `ether1` drop together around 02:00–03:00 on Saturdays,
  most likely a weekly reboot.

Anything else is worth a look: check the switch's `/log print where topics~"interface"` first.

## Why port maps go stale, and how to check

Cables move; the tables above are a snapshot. Both discovery methods are heuristic:

- `/ip neighbor print` (MNDP) and bridge host tables **traverse bridges**. A device two switches
  away appears on the port its packets *egress*, not the port it is plugged into.
- The bridge host table has the same property and additionally ages out idle MACs.

So use them to narrow the candidates, then confirm. The device's real port is the only *leaf*
port that learns its MAC; every other switch sees it on an uplink.
`/interface bridge host print terse` shows MAC→port; `/ip arp print terse` maps MAC→IP.
