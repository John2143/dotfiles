# WireGuard tunnel (`wg-remote`)

Native RouterOS WireGuard. One peer today: the DigitalOcean cluster. It carries DO → home Postgres
and Temporal, and home → DO MongoDB.

| Property | Value |
|---|---|
| Interface | `wg-remote`, MTU 1420, listen **UDP 51820** |
| Subnet | `10.99.0.0/24` — router `.1`, DO `.2`, next peer `.3` |
| Router public key | `26mSa5AF67ZCYagY8TBwlMLSo1YkQLUKAUjJajBwEgQ=` |
| Peer `peer1` | DO cluster, `allowed-address=10.99.0.2/32,10.244.0.0/16`, router never dials |
| Firewall | input accept UDP 51820 from WAN, **above** `drop all not coming from LAN` |
| Forwarding | tunnel ACL: default-deny, three allows (`→ .5.36:5432` postgres, `→ .6.20:7233` temporal, `→ .6.31:8333` seaweedfs S3) |

Not a member of the `LAN` list — tunnel traffic to the router itself is dropped except the DNS
allow. `allowed-address` doubles as source filter: a mismatch fails silently.

## Add a peer

```
mikrotik-connect r '/interface wireguard peers add interface=wg-remote public-key="<PUBKEY>" allowed-address=10.99.0.3/32 comment="<device>"'
```

Then, before it can reach anything forwarded, add an allow **above** the deny:

```
mikrotik-connect r ':put [:len [/ip firewall filter find comment="wg: deny tunnel traffic not allowed above"]]'   # must print 1
mikrotik-connect r '/ip firewall filter add chain=forward action=accept protocol=tcp in-interface=wg-remote dst-address=<ip> dst-port=<port> comment="wg: doks -> <svc>" place-before=[find comment="wg: deny tunnel traffic not allowed above"]'
```

## Verify

`/interface wireguard print` prints `private-key=`. Never run it plain.

```
mikrotik-connect r '/interface wireguard print proplist=name,listen-port,public-key,running'
mikrotik-connect r '/interface wireguard peers print proplist=comment,current-endpoint-address,last-handshake,rx,tx'
kubectl --context 2143prod -n default exec deploy/wireguard-doks -- wg show wg0
```

A fresh handshake under 2 minutes with non-zero rx/tx is the only proof the tunnel is live — and
because the router never dials, it also proves inbound UDP 51820 survives the Verizon path.

## Rotate the key (~30 s outage)

1. `wg genkey` / `wg pubkey` off-router; never echo the private half.
2. Put the new **public** key on the peer line in `2143-k8s/base/wireguard-doks.yaml`; commit.
3. `:put [/interface wireguard get [find name="wg-remote"] public-key]` must show the new key after
   the set. Private key goes in via a script that never prints it.
4. Push `2143-k8s`, reconcile, verify the handshake.

Dead keys — any config still pinning them is stale: `lNbjEa…` and `2HeIlsYng…`.

## Rollback

Removing `wg-remote` cuts DO off from closet Postgres and Temporal and home off from DO MongoDB.
Remove in order: forward allows → tunnel deny rule → interface → `LAN` list member.
