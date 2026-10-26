# Cluster networking: MetalLB, BGP, LB IPs

How pod services get LAN-routable addresses. `argo-engineer` carries the operator view (allocation
rules, change flow); this is the network side.

## Nodes

k3s HA (embedded etcd) on `closet` (.36), `arch` (.76), `nas` (.175); workers `pite` (.9),
`big` (.68, a VM on bigp), `office` (.209, wifi — deliberately **not** a BGP speaker).

## BGP

MetalLB v0.16.1 with frr-k8s. Nodes are AS 65000, router is AS 65001. One RouterOS listener
connection (`metallb-speakers`) carries `afi=ip,ipv6`, BFD and the input filter; admission is the
firewall address-list `k8s-nodes` on TCP/179.

- Every speaker advertises every allocated prefix; the router keeps one active next-hop and the
  rest as backup. No leader lease, no loopback VIP — kube-proxy DNATs on every node.
- `externalTrafficPolicy: Local` services are announced only by the node with the local endpoint,
  which is why clients see their real address on those.
- Dual-stack: `192.168.6.0/24` announced as /32s, `fd00:6::/64` as /128s. The BGPPeer needs
  `dualStackAddressFamily: true`, otherwise frr-k8s renders `ipv6 prefix-list … deny any`.
- BGP multipath was trialled 2026-10-19 and reverted — it broke TLS on the WAN hairpin. Do not
  re-enable without reading follow-up #78.

Live checks:

```
ssh closet 'kubectl get bgpsessionstates -n metallb-system'        # 5 Established
mikrotik-connect r '/routing bgp session print'
mikrotik-connect r '/ip route print where dst-address=192.168.6.6/32'
```

## LB addresses

| Service | v4 | v6 |
|---|---|---|
| traefik (ingress) | `.6.6` | `fd00:6::6` |
| stalwart | `.6.13` | `fd00:6::13` |
| steam coturn | `.6.14` | `fd00:6::14` |
| ts-voice / ts-files | `.6.15` / `.6.16` | `::15` / `::16` |
| openrct2 | `.6.17` | `::17` |
| headscale-stun | `.6.18` | `::18` |
| mosquitto | `.6.19` | `::19` |
| temporal | `.6.20` | — |
| matrix coturn / livekit | `.6.21` / `.6.22` | `::21` / `::22` |
| mimir / loki | `.6.23:8080` / `.6.24:3100` | `::23` / `::24` |
| syslog | `.6.25:514/udp` | `::25` |
| frigate | `.6.26` | `::26` |
| factorio / minecraft | `.6.28:34197` / `.6.29:25565` | `::28` / `::29` |
| lan-dns | `.6.30:53` | `fd00:6::30` |
| seaweedfs S3 | `.6.31:8333` | `::31` |
| k8s API | `.5.10:6443` (v4 only) | — |

Full inventory with ports: `kubectl get svc -A`.

## Traffic flow

Traefik's access log is shipped to Loki by Alloy and is the only usable record of "who called
what" — `kubectl logs` rotates in seconds. Query Loki directly on the LAN:

```
curl -sS -G 'http://192.168.6.24:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="kube-system"} |= "seafile.john2143.com" | json | DownstreamStatus >= 500' \
  --data-urlencode "start=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode "end=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Fields that matter: `DownstreamStatus` (returned to client), `OriginStatus` (from backend),
`ClientHost` (LAN clients show their real `192.168.5.x`; hairpin NAT was removed, so only external
clients share the WAN IP), `RouterName` (maps back to the HTTPRoute). `RequestCount` is a
cumulative counter, never sum it. `429` is rate limiting, `403` is CrowdSec.
