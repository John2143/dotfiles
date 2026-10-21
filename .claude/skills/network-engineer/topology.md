# Topology and switch ports

Physical cabling and per-device identity. Re-derive with `scripts/network-snapshot.sh`, or
live with `/ip neighbor print` on each MikroTik.

## Backbone

```
Router (RB5009) —10G— Core (CRS305) —10G— Upstairs-Core (CRS305) —10G— Upstairs (CRS310)
                        │
                        ├─10G→ NAS
                        └─10G→ Office (CRS310)
```

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

## Last known port map

| Switch | Port | Peer |
|---|---|---|
| Core | ether1 | Router (management, 1G) |
| Core | sfp-sfpplus1 | NAS 10GbE |
| Core | sfp-sfpplus2 | Upstairs-Core sfp-sfpplus2 |
| Core | sfp-sfpplus3 | Office 10G uplink |
| Core | sfp-sfpplus4 | Router 10G uplink |
| Upstairs-Core | ether1 | GL-KVM (PoE) |
| Upstairs-Core | sfp-sfpplus1 | closet 10G |
| Upstairs-Core | sfp-sfpplus2 | Core |
| Upstairs-Core | sfp-sfpplus3 | arch 2.5G |
| Upstairs-Core | sfp-sfpplus4 | Upstairs |
| Office | sfp-sfpplus1 | U7 Pro XGS (10GbE) |
| Office | sfp-sfpplus2 | Core |
| Office | ether1 | pite |
| Upstairs | sfp-sfpplus1 | Upstairs-Core |
| Upstairs | ether1 | Reolink NVR (PoE) |
| Upstairs | ether6 | Brother printer |
| Upstairs | sfp-sfpplus2 | bigp (and VM `big` over the same link) |
| Router | ether5 | U7 Lite (PoE) |

## Why port maps go stale, and how to check

Cables move; the table above is a snapshot. Both discovery methods are heuristic:

- `/ip neighbor print` (MNDP) and bridge host tables **traverse bridges**. A device two switches
  away appears on the port its packets *egress*, not the port it is plugged into.
- The bridge host table has the same property and additionally ages out idle MACs.

So: use them to narrow the candidates, then confirm physically. `/interface bridge host print terse`
shows MAC→port; `/ip arp print terse` maps MAC→IP.
