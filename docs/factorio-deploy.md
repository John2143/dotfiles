# Factorio deploy — status & debug notes

Last updated 2026-08-14.

## Status

- **Server: RUNNING** — Factorio **2.1.14** (the *experimental* branch; stable is
  2.0.77 per factorio.com/api/latest-releases). Satisfies SE 0.7.61 (needs base ≥ 2.1.7).
- **Save:** `k2se` (vanilla placeholder, created only for the join test — replace with a
  fresh save after the K2+SE mods are installed).
- **Web UI (OFSM):** https://factorio.john2143.com
- **Game:** WAN `factorio.john2143.com:34197` (UDP) · LAN `192.168.6.28:34197`.
- A real client joined at 22:53:44 (`[JOIN] John2143 joined the game`) — path verified end-to-end.

## Credentials (change these)

| What | Value |
|---|---|
| OFSM web UI admin | `admin` / `MMrHRuyVakLIluBDapUFGZtO` |
| RCON password | `XVlBzgbaiCMRAjWwhTHctcuA` |

Both persist on the `factorio-db-lh` PVC now. Change the admin password in the OFSM **Users** page.

## What's deployed (argo repo, `main`)

- `apps/factorio.yaml` — Argo app.
- `workloads/factorio/`:
  - `deployment.yaml` — `ofsm/ofsm:latest`, replicas 1, Recreate.
  - `service-http.yaml` — v4-only ClusterIP (backing the HTTPRoute).
  - `service-game.yaml` — MetalLB dual-stack LB `192.168.6.28`/`fd00:6::28`, UDP 34197.
  - `pvc.yaml` — 4 PVCs on `longhorn-2`.
  - `ingress.yaml` — HTTPRoute → `factorio-john2143-https` gateway listener.
- `workloads/gateway/gateway.yaml` — added `factorio-john2143-https`; removed the
  vestigial `factorio.2143.me` listener + commented `factorio-udp` block.
- MikroTik dst-nat (outside git): `chain=dstnat protocol=udp dst-port=34197
  to-addresses=192.168.6.28 in-interface-list=WAN comment=factorio` (single rule, no dup).

## OFSM image contract (learned the hard way — do not reintroduce the old env vars)

`ofsm/ofsm:latest` entrypoint (`/opt/entrypoint.sh`):

- OFSM conf + sqlite DB are **hardcoded to `/opt/fsm-data`**.
- Game install: `FACTORIO_VERSION=latest` (image default) → resolves to the current
  experimental build; re-downloads on every pod start.
- Binary's default modpack dir: `/opt/fsm/mod_packs`.
- **`FSM_MODPACK_DIR`, `SQ_LITE_DATABASE_FILE`, `FSM_AUTOSTART` are all NO-OPS** (ignored
  by the image — verified against entrypoint + binary strings). The old config's
  `/mnt/db` and `/mnt/mod_packs` mounts therefore persisted nothing.

Correct mounts (as deployed now):

| mountPath | PVC | purpose |
|---|---|---|
| `/opt/fsm-data` | `factorio-db-lh` | OFSM sqlite db, conf.json, log |
| `/opt/fsm/mod_packs` | `factorio-mod-packs-lh` | OFSM modpack collection |
| `/opt/factorio/mods` | `factorio-mod-packs-lh` | game mods dir |
| `/opt/factorio/saves` | `factorio-saves-lh` | game saves |
| `/opt/factorio/config` | `factorio-configs-lh` | server-settings.json |

## Open debugging items

1. **Friends get `UserVerificationMissing`** — `require_user_verification: true` in
   `server-settings.json` (on the configs PVC). To let friends in: set it `false`
   (+ optionally a `game_password`), or keep `true` (Factorio-account clients only).
2. **`Missing token` in the log** — `visibility.public: true` but no factorio.com
   `username`/`token`. Only affects the public server-browser listing; direct IP join is unaffected.
3. **Server `name` is still the placeholder text** in server-settings.json.
4. **No autostart** — the game server does not start on pod restart (FSM_AUTOSTART is a
   no-op). Start it from the OFSM UI (**Controls**). Check whether OFSM has a UI autostart setting.
5. **Mods not installed yet** — see list below. Install via OFSM **Mods** page, then create
   a fresh save.

## Mod list (K2 + Space Exploration, validated)

| Mod | slug | ver |
|---|---|---|
| Space Exploration | `space-exploration` | 0.7.61 |
| Space Exploration Postprocess *(required)* | `space-exploration-postprocess` | 0.7.6 |
| Krastorio 2 | `Krastorio2` | 2.1.2 |
| FNEI | `FNEI` | 0.4.7 |
| Factory Planner | *(search "Factory Planner")* | 2.1.11 |
| Rate Calculator | `RateCalculator` | 3.4.1 |
| Todo List | *(search "Todo List")* | 19.15.3 |
| Even Distribution | `even-distribution` | 2.1.0 |
| Squeak Through 2 | `squeak-through-2` | 0.2.0 |
| VehicleSnap | `VehicleSnap` | 2.0.4 |
| LTN — Logistic Train Network | `LogisticTrainNetwork` | 3.1.0 |
| LTN Space Exploration companion | *(search "LTN Space Exploration")* | — |
| Deadlock's Stacking Beltboxes & Compact Loaders | `deadlock-beltboxes-loaders` | 2.6.0 |

Excluded: Bob's/Angel's/Py/etc. (hard-conflict with SE), K2SE "Spaced Out" bundle (stale),
SE Official Modpack (stale), Miniloader & Ghost Scanner (abandoned 1.1), Recipe Book (EOL),
Rampant (UPS), Waterfill/power-gen (breaks SE balance).

## Pelican — PARKED (do not touch)

Committed to the argo repo but intentionally left half-deployed 2026-08-14.
`pelican-db` CNPG cluster is running; the `pelican` deployment is stuck
(`CreateContainerConfigError`: the configmap fix is committed but never synced).
Revisit later.

## ArgoCD repo-server note

`argocd-repo-server` crash-looped after a burst of concurrent syncs (liveness probe
`/healthz?full=true` too tight for the manifest-regen load). It appeared to be
stabilizing; if GitOps syncs stall, check `kubectl -n argocd get pods | grep repo-server`.
