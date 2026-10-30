# UniFi wireless

Wireless is invisible to the MikroTiks — AP association, signal and channel data only exist in the
UniFi controller.

## Access points

| AP | IP | Model | Uplink |
|---|---|---|---|
| U7 Pro XGS | 192.168.5.171 (DHCP) | U7 Pro XGS | Office sfp-sfpplus1, 10GbE |
| U7 Lite | 192.168.5.173 (DHCP) | U7 Lite | **Router `u7-lite`** (ether5), 1GbE PoE |
| U7-Mesh | 192.168.5.198 (DHCP) | U7-Mesh | wireless, **pinned** to U7 Lite (`mesh_uplink_1`), ~−61 dBm on ch 149 |

Re-point an AP at the controller:

```
ssh ubnt@<ap-ip>
set-inform http://192.168.5.30:8080/inform
```

Router PoE caveats: `u7-lite` (ether5) runs the U7 Lite and once sat in `short-circuit` with
`LLDP … low-voltage` errors — if an AP drops, check `/interface ethernet poe monitor` before
touching the AP. `core-poe` (router ether2) powers the CRS305 via PoE-in: **never** set `poe-out=off` there.

An unpinned mesh AP picks a new parent after any provision, and every move drops its clients. Keep
the mesh pinned.

## Radio settings (2026-10-29)

| | 2.4 GHz | 5 GHz | 6 GHz |
|---|---|---|---|
| U7 Pro XGS | ch 1, 20 MHz | ch 40, **160 MHz**, custom 24 dBm | ch 37, 160 MHz |
| U7 Lite | ch 11 | ch 149, 80 MHz | — |
| U7-Mesh | ch 6 | ch 149, 80 MHz (follows parent) | — |

- XGS 5 GHz stays at 160 MHz on purpose. iperf3 office↔nas: 1.50/1.44 Gbps down/up at
  160 MHz versus 0.96/0.77 at 80 MHz. Every 160 MHz option includes DFS channels; no radar hit in 14 days.
- Main SSID: roaming assistant 5 GHz −75, 6 GHz −77; 802.11r and BSS transition on; **MLO on**
  (an off-trial is pending, see task #170).
- Uplink Connectivity Monitor targets `192.168.5.1`. With `8.8.8.8` every WAN blip made the APs
  drop SSIDs.

## Controller

UniFi OS Server 1.0.1, a VM on bigp ("2707 McComas"), `192.168.5.30`, MAC `BC:24:11:23:B8:A5`,
Network application 10.6.109, single local admin, no Ubiquiti SSO.

- UI: `https://192.168.5.30:11443/network/default` (self-signed) or `https://unifi.ts.2143.me`
  (argo app `unifi-os`, LAN-only middleware).
- Credentials: `/run/agenix/unifi-credentials` holds `UNIFI_CONTROLLER` (`unifi.ts.2143.me`) and
  `UNIFI_PASSWORD` (the UniFi OS password). There is no `UNIFI_USERNAME` line; the user is `admin`,
  the owner/super-admin. If login fails, ask the owner rather than guessing.

## API

This is a UniFi OS console, so the login path has `/auth`:

```
POST /api/auth/login   {"username": "…", "password": "…", "remember": true}   → cookie TOKEN
POST /api/auth/login   (writes also need the X-CSRF-Token response header)
GET  /proxy/network/api/s/default/stat/device | stat/sta | stat/health | stat/report/hourly.ap
```

Before forming a request by hand, **prefer the owner's curl/urllib snippet**: the login flow needs a
cookie jar and a TLS context that skips verification.

- **Event history:** `POST /proxy/network/v2/api/site/default/system-log/all` with
  `{"timestampFrom": <ms>, "timestampTo": <ms>, "pageSize": 500, "pageNumber": 0}` returns ~14 days of
  client connect/disconnect/roam events (signal, band, channel, AP, duration) and device events
  (`AP_CHANGED_CHANNELS`, `DEVICE_UNREACHABLE`, setting changes). It is a read-only query despite
  being a POST. `system-log/device-alert`, `client-alert` and `critical` also work;
  `client-connection`, `update`, `triggers` and legacy `stat/event` return 404.
- **Secrets come back in cleartext** in `get/setting` / `rest/setting` (`x_ssh_password`,
  `x_api_token`, `x_mesh_psk`), `rest/wlanconf` (`x_passphrase`) and even `stat/device`
  (`x_vwirekey`). Drop every `x_*` key before printing anything, and print allowlisted fields only.
- API writes (anything beyond a read GET, the login POST and the `system-log/*` query POSTs) change
  controller state — ask first.
