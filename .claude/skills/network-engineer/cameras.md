# Cameras

Reolink, ONVIF/RTSP — not UniFi Protect.

| Item | Value |
|---|---|
| Subnet | `192.168.1.0/24`, cameras only |
| Egress | WAN blocked for the whole subnet by firewall rule |
| NVR duties | `secu` (192.168.5.140) |
| Recording UI | `frigate` LoadBalancer `.6.26` (ports 5000, 1984, 8554, 8555/udp) |

## Addressing

Cameras use RouterOS-side DHCP reservations on the 1.0/24 pool. A new camera gets a lease, then:

```
mikrotik-connect r '/ip dhcp-server lease make-static [find host-name=<name>]'
```

## Checks

```
mikrotik-connect r '/ip dhcp-server lease print terse where status=bound and address~"^192\\.168\\.1\\."'
mikrotik-connect r '/ip firewall filter print where comment~"camera"'
```

If a camera is unreachable, confirm in this order: PoE port state on the Upstairs switch →
DHCP lease present → ICMP from `secu` → ONVIF port (usually 8000) → Frigate logs. Do not "fix" the
blocked egress: it is deliberate.
