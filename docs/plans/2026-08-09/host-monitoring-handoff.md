# Host Monitoring + SMART Alert — handoff (2026-08-10)

## What's done (committed, pushed, live)

### 1. SMART alert with 1-day cooldown — **LIVE in Mimir**
- **Ruler rule** installed in namespace `cluster` (verified `state: inactive, health: ok`):
  ```yaml
  - alert: ReallocatedSectors
    expr: smartctl_device_attribute{attribute_name="Reallocated_Sector_Ct", attribute_value_type="raw"} > 0
    for: 5m
    labels: { severity: warning }
  ```
  **Metric name verified against live hardware** (nas's ST8000DM004 via smartctl_exporter 0.14): it's
  `smartctl_device_attribute{attribute_name="Reallocated_Sector_Ct", attribute_value_type="raw"}` —
  NOT the `smartctl_smartctl_attributes{name=...}` shape assumed earlier. NVMe disks emit
  `smartctl_device_media_errors` / `available_spare` instead (no reallocated family).
- **Alertmanager 24h cooldown** — child route added (verified in runtime config):
  ```yaml
  routes:
    - match: { alertname: ReallocatedSectors }
      receiver: ntfy
      repeat_interval: 24h
  ```
  Parent route stays at `repeat_interval: 4h`; all existing alerts unchanged. Fires promptly
  (`for: 5m`), then re-notifies at most once per 24h while the condition persists.
- Working config API: `POST /api/v1/alerts` at the **Mimir root** (201). The
  `/alertmanager/api/v1/alerts` path is the deprecated Alertmanager v1 (410).

### 2. Per-host telemetry — committed to dotfiles, **deploy = user rebuild**
New module `nixos/modules/observability-agent.nix`, enabled on all 11 flake hosts:
- **smartctl_exporter** on `:9633` (SMART attributes — the alert's data source). Iterates
  `/dev/disk/by-id/ata-*` at runtime; empty-safe on Pi/VM hosts.
- **nvidia_gpu_exporter** on `:9835` (arch only, `enableNvidiaGpu`; nvidia-smi via driver bin).

Host **temps were already covered**: all hosts run node_exporter (shared-cli-configuration.nix)
scraped by pite's Prometheus as `home-nodes` → Mimir. Verified live: `node_hwmon_temp_celsius` /
`node_thermal_zone_temp` for office/arch/closet/nas/big/pite. **No duplicate Alloy fleet deployed**
— that was the plan's original (redundant) design.

### 3. pite Prometheus additions (in the same dotfiles commit)
- `home-nodes` scrape: added **secu** (100.64.0.12) + **vpin** (100.64.0.7) — they'll appear when online.
- New **`smartctl` job**: scrapes `:9633` on closet/arch/nas/office/big/secu → Mimir.
- Dropped the redundant k8s-side `nas_smart` scrape from alloy.yaml (pite owns smartctl now).

### 4. Fixed the other agent's regressions (their work reviewed)
- **`flake.lock` input bump broke ALL host builds** (`rewriteURL` type error via nixpkgs-stable
  import at shared-cli-configuration.nix:44). Reverted to the known-good `00a8dae` pins. Builds pass again.
- **Beyla OTLP metrics path was dead**: `otelcol.exporter.otlp` (gRPC) pointed at a URL path
  (`dial tcp: lookup tcp/8080/otlp`) → fixed to `otelcol.exporter.otlphttp` with
  `http://mimir.observability.svc:8080/otlp`; and `batch.metrics` referenced the old
  `otlp.mimir.input` → fixed to `otlphttp.mimir.input` (this was crashlooping an alloy pod).
  **Verified: Beyla RED metrics now flow (45k+ series in Mimir).**

## What YOU need to run (nixos-rebuild switch)

```bash
for h in office arch closet nas secu big pite aman vpin github term; do
  echo "### $h"
  ssh $h 'sudo nixos-rebuild switch --flake ~/repos/dotfiles#'"$h"
done
```
- github/term may be offline — skip and note; a failure on one host doesn't block others.
- pite rebuild is required for the new smartctl scrape + home-nodes targets to take effect.
- After rebuilding, verify per host:
  - `curl -s localhost:9633/metrics | grep -c smartctl_` > 0 (on hosts with disks)
  - arch only: `curl -s localhost:9835/metrics | grep -c nvidia_` > 0
  - Mimir end-to-end:
    `curl -s "http://192.168.6.23:8080/prometheus/api/v1/query?query=smartctl_device_attribute%7Battribute_name%3D%22Reallocated_Sector_Ct%22%7D"`
    → returns samples labeled `device="ata-..."` for nas etc.

## Commits
- dotfiles `5758420` (monitoring), `09bf429` (flake.lock revert) — pushed
- argo `0cf498b` (otlphttp fix), `3a3502e` (drop nas_smart), `5c5bded` (batch.metrics fix) — pushed

## Notes
- The other agent's uncommitted `steam-lobby/deployment.yaml` (OAuth env vars) was left untouched.
- secu/vpin/aman/term/github are offline or intermittent; their node_exporter/SMART metrics appear
  when they're up.
- No disk currently has reallocated sectors (verified this session's sweep) — the alert is
  structural, ready to fire on first real reallocation.
