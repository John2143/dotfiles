# UniFi wireless

Wireless is invisible to the MikroTiks — AP association, signal and channel data only exist in the
UniFi controller.

## Access points

| AP | IP | Model | Uplink |
|---|---|---|---|
| U7 Pro XGS | 192.168.5.171 (DHCP) | U7 Pro XGS | Office sfp-sfpplus1, 10GbE |
| U7 Lite | 192.168.5.173 (DHCP) | U7 Lite | **Router ether5**, 1GbE PoE |
| U7-Mesh | 192.168.5.198 (DHCP) | U7-Mesh | wireless, mesh to U7 Lite (~-67 dBm) |

Re-point an AP at the controller:

```
ssh ubnt@<ap-ip>
set-inform http://192.168.5.30:8080/inform
```

Router PoE caveats: `ether5` runs the U7 Lite and once sat in `short-circuit` with
`LLDP … low-voltage` errors — if an AP drops, check `/interface ethernet poe monitor` before
touching the AP. `pi` (router ether2) powers the CRS305 via PoE-in: **never** set `poe-out=off` there.

## Controller

UniFi OS Server 1.0.1, a VM on bigp ("2707 McComas"), `192.168.5.30`, MAC `BC:24:11:23:B8:A5`,
Network application 10.4.57, single local admin, no Ubiquiti SSO.

- UI: `https://192.168.5.30:11443/network/default` (self-signed) or `https://unifi.ts.2143.me`
  (argo app `unifi-os`, LAN-only middleware).
- Credentials: `/run/agenix/unifi-credentials` as `UNIFI_USERNAME` / `UNIFI_PASSWORD`. The file
  predates the 2026-09 controller migration — if login fails, ask the owner rather than guessing.

## API

This is a UniFi OS console, so the login path has `/auth`:

```
POST /api/auth/login   {"username": "…", "password": "…", "remember": true}   → cookie TOKEN
POST /api/auth/login   (writes also need the X-CSRF-Token response header)
GET  /proxy/network/api/s/default/stat/device | stat/sta | stat/health | stat/report/hourly.ap
```

Before forming a request by hand, **prefer the owner's curl/urllib snippet**: the login flow needs a
cookie jar and a TLS context that skips verification.

- **No event history via API.** Legacy `stat/event` returns 404 on 10.4.57, and
  `/proxy/network/v2/api/site/default/events` 404s too.
- **`get/setting` returns cleartext device credentials** (`x_ssh_password`, `x_api_token`,
  `x_mesh_psk`). Never dump it into a transcript.
- API writes (anything beyond a read GET and the login POST) change controller state — ask first.
