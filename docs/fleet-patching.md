# Fleet patching

Two systemd timers on **office** keep the fleet current. Neither one reboots anything.

| Timer | When | Does |
|---|---|---|
| `fleet-patch.timer` | Sunday 04:00 (+ up to 5 min jitter) | bumps `nixpkgs` and `nixpkgs-stable`, pushes `flake.lock`, switches every NixOS host to that exact commit |
| `renovate.timer` | Sunday 05:00 | opens PRs against `2143-Labs/argo` for chart and image bumps |

Both push to ntfy on failure (`notify-failure@<unit>`), so a broken week is visible without
logging in. `fleet-patch` also always sends its report, summarised in the notification title.

The job never reboots, so the kernel it stages only takes effect at the next reboot. When a
host's running kernel differs from the booted-only generation, its row says `REBOOT NEEDED`.

GPU hosts (`big`, `arch`) are the exception to `switch`: if the loaded NVIDIA kernel module
differs from the driver the new generation activates, the job runs `nixos-rebuild boot`
instead and the row says `STAGED (nvidia X → Y): REBOOT NEEDED`. Activating new NVIDIA
userspace on top of an old kernel module breaks NVML ("Driver/library version mismatch")
until reboot, which would take the frigate pod's GPU away on any restart. Until you reboot
them they keep running the old generation with a working GPU.

## Public DNS

`ddns/desec-ddns` (argo `workloads/ddns/cronjob.yaml`) keeps `john2143.com`,
`*.john2143.com`, `m.2143.me`, `dsstar.us`, `balabusta.homes` and `*.balabusta.homes` pointed
at the home WAN IP every 15 minutes. It replaces the deSEC timers that ran on home-pi. Any
error posts `desec-ddns failed` to ntfy.

To force a rewrite (this is also how you prove a new token can write):

```fish
ssh john@192.168.5.36 'kubectl create job -n ddns ddns-verify --from=cronjob/desec-ddns --dry-run=client -o json' \
  | jq '.spec.template.spec.containers[0].env=[{"name":"FORCE","value":"1"}]' \
  | ssh john@192.168.5.36 'kubectl create -f -'
ssh john@192.168.5.36 'kubectl wait -n ddns --for=condition=complete job/ddns-verify --timeout=180s'
ssh john@192.168.5.36 'kubectl logs -n ddns job/ddns-verify'
ssh john@192.168.5.36 'kubectl delete job -n ddns ddns-verify'
```

## Where the outcome lives

- `~/.local/state/fleet-patch/last-run.md` — per-host table, plus a "Not managed" table for
  bigp and unifi-os. Each row is one of:
  - `ok`
  - `REBOOT NEEDED`
  - `STAGED (nvidia …): REBOOT NEEDED`
  - `STALE` — the switch reported success but the host is not on the evaluated generation
  - `FAILED`
  - `HELD` — a control plane stopped the run
  - `OFFLINE`
- `run.log` — this run's detail; `run.log.1` — the previous run.
- `ATTENTION` — exists if and only if the last run recorded a failure.
- `~/.local/state/fleet-patch/dotfiles` — the job's own clone of `origin/master`. It is
  `reset --hard` every run. **Never edit it**; edit `~/dotfiles` and push.

## Run it by hand

```fish
bash ~/dotfiles/scripts/fleet-patch.sh                 # bump + switch everything
DRY_RUN=1 bash ~/dotfiles/scripts/fleet-patch.sh       # bump + evaluate + probe, change nothing
BUMP=0 ONLY="mirror vpin" bash ~/dotfiles/scripts/fleet-patch.sh   # named hosts, no bump
```

Run these in `tmux`: if the shell dies the script dies between hosts (each individual switch
still completes, because nixos-rebuild runs it under `systemd-run --wait`). Rerun with
`ONLY=` to finish the rest; the script is idempotent per host.

## Hold the schedule

```fish
sudo systemctl disable --now fleet-patch.timer
sudo systemctl disable --now renovate.timer
```

Re-enable with `enable --now`. `Persistent = true` means a window missed while office was off
runs on the next boot.

## Roll back one host

```fish
ssh john@<ip> 'sudo -n nixos-rebuild switch --rollback'
```

On `arch`, `closet` or `nas`, do the cordon/LB steps from "Rebooting a k3s node" first: the
rollback restarts k3s, which means a 30–90 s API/ingress blip.

## Roll back a bump

```fish
git -C ~/dotfiles revert <chore(fleet): weekly nixpkgs bump …>   # push it
sudo systemctl disable --now fleet-patch.timer
```

Disable the timer until the revert is understood: the next run re-bumps to branch head, which
would undo the revert.

## Roll back an argo bump

Revert the merged Renovate PR on `main`; ArgoCD self-heals it. Never re-pin an image by hand:
`automated: {prune, selfHeal}` will revert the edit anyway.

## Rebooting a k3s node

Not needed for the weekly job (it never reboots), but this is the only safe way to pick up a
staged kernel on `arch`, `closet` or `nas`. The full procedure is
`~/repos/argo/docs/node-maintenance.md`; the deviations that matter:

**1. Gate.** Every row must show `READY` = `INST`. If any row is short, stop: the promote
target may not be ready.

```fish
ssh john@192.168.5.36 'kubectl get clusters.postgresql.cnpg.io -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,INST:.spec.instances,READY:.status.readyInstances,PRIMARY:.status.currentPrimary'
```

**2. Promote** every primary the node holds onto another node. Each switchover drops that
database's connections for a few seconds. Rerun the gate afterwards; `PRIMARY` must show the
new instance.

```fish
ssh john@192.168.5.36 'nix run nixpkgs#kubectl-cnpg -- promote <cluster> <instance-on-other-node> -n <namespace>'
```

**3. Cordon, add `node.kubernetes.io/exclude-from-external-load-balancers`, and wait for the
router to withdraw the node** (`prefix-count=0` for that address).

**4. Selective drain, not a full drain.** A full drain cannot finish: Longhorn's
`node-drain-policy` is `block-if-contains-last-replica`, and every CNPG instance volume plus
`loki-write-0/1` has exactly one replica. Always `--dry-run=client` first and check the
listed pods against the stay list.

Closet (evicted 61 pods on 2026-10-31):

```
!cnpg.io/cluster,longhorn.io/component!=instance-manager,app notin (home-assistant,minecraft),app.kubernetes.io/name!=za-mullvad,statefulset.kubernetes.io/pod-name!=loki-write-1
```

Stay list: the five `*-db-2` CNPG pods, `home-assistant` (Zigbee stick `/dev/ttyUSB0` is on
closet), `minecraft`, `za-mullvad`, `loki-write-1`, the instance-manager.

Big (evicted 21 pods on 2026-10-31):

```
!cnpg.io/cluster,longhorn.io/component!=instance-manager,app notin (frigate,matter-server),app.kubernetes.io/name notin (ee-mullvad,tempo),statefulset.kubernetes.io/pod-name notin (loki-write-0,mimir-1,loki-chunks-cache-0,loki-results-cache-0)
```

Stay list: the CNPG instances, `frigate` (big has the only allocatable GPU), `matter-server`,
`ee-mullvad`, `tempo-0`, `mimir-1`, `loki-write-0`, both loki caches, the instance-manager.

Before reusing a selector, re-check it against `kubectl get pods -A --field-selector
spec.nodeName=<node>`; pods added since 2026-10-31 may belong in the stay list. A wrongly
evicted pinned pod only goes Pending until the node returns; no data is lost.

**5. Reboot**, then follow the "Return" section of `node-maintenance.md`. Pods that were moved
do not move back, which is fine.

**`secu`** is the exception to everything above: reboot it only with its LUKS unlock USB
inserted, or type the passphrase at its console (`nixos/modules/disko_secu.nix:26-27`).

**`pite`** permanently carries the exclude-from-LB label; never remove it on return.

## How long a run takes

A fresh `nixpkgs` bump usually substitutes from `nas:8280` and `cache.nixos.org`, and the x86
hosts finish in minutes. The three aarch64 hosts (`pite`, `vpin`, `mirror`) are rank-0 sinks in
`nixos/modules/remote-builders.nix`: they delegate to nobody, and when Hydra's aarch64 builds
lag behind a bump they compile from source at `--max-jobs 1`. Seeing `rustc` and `cc1` under
`nixbld1` on a Pi, with load above 10 for half an hour, is that — not a hang.

The unit has `TimeoutStartSec = 6h`. If a run is still on an ARM host near that, the unit is
killed mid-fleet: the hosts after it have no rows, and every individual switch that already
finished stays finished. Finish the remainder by hand with `ONLY="<hosts missing from the
table>" BUMP=0`. Do not lower `--max-jobs 1` on those hosts to speed it up; they OOM.

## When a host fails

`FAILED (switch)` on `github` with a Python traceback ending `No usable temporary directory
found in ['/tmp', '/var/tmp', '/usr/tmp', '/home/john']` is a **full root filesystem**, not a
broken nixos-rebuild (`tempfile` reports ENOENT whatever the real error was). It happens
because `John2143/dotfiles` runs the frigate-genai image build on that host whenever a push
touches `flake.nix` or `flake.lock` — which every weekly bump does — so the switch can land
while the build is still writing to `/nix`.

```fish
ssh john@192.168.5.108 'df -h / /dev/sda1'          # root is the one that matters
gh run list -R John2143/dotfiles --limit 3          # is a build still running
```

Wait for the build to finish, confirm the root filesystem is back under about 80%, then rerun
that host alone: `ONLY=github BUMP=0 bash ~/dotfiles/scripts/fleet-patch.sh`. The same run
logs `No space left on device` from the runner, `swapfile` and k3s etcd if you look at
`journalctl` on that host at the time — those are symptoms of the same fill, not separate
faults.

`FAILED (switch)` on any other host is a real error: read the last 40 lines of `run.log`
before rerunning.

## Adding a host

1. Add `name:max-jobs:address` to `HOSTS` in `scripts/fleet-patch.sh`, keeping control planes
   last. `1` max-jobs for the aarch64 Pis, `auto` for everything else.
2. Collect the key with `ssh-keyscan -t ed25519 <lan-ip>`, compare it with
   `ssh-keyscan -t ed25519 <tailnet-ip>`, and add it to `programs.ssh.knownHosts` in
   `nixos/modules/fleet-patching.nix`. An unpinned host fails with `Host key verification
   failed`; the job never trusts an unknown key.
3. Before trusting it, run `DRY_RUN=1 ONLY=<host> bash ~/dotfiles/scripts/fleet-patch.sh`.
