# Fleet patching

**The weekly patch runs from GitHub Actions** (since 2026-11-23):

| Job | Planned | Actual |
|---|---|---|
| `fleet-patch.yml` in dotfiles | Sundays 09:00 UTC (04:00 America/New_York), plus `workflow_dispatch` | Runs on the org's self-hosted runners (`[self-hosted, nixos]`), logging in to OpenBao with GitHub OIDC as the `ci-fleet-patch` role. No stored credential: the token lasts 10 minutes and is revoked when the run ends. |
| CronJob `renovate` in 2143-Labs/argo | Sundays 05:00 America/New_York | Runs in-cluster on k3s (`workloads/renovate/`); opens dependency PRs on argo only. It does not touch this fleet. |

The job bumps `nixpkgs`, `nixpkgs-stable` and `oh-my-pi`, pushes `flake.lock`, and switches
every NixOS host to that exact commit. It never reboots anything, and neither does the Renovate
CronJob.

It replaces the office `fleet-patch` timer, which was masked during the i9-14900K stress test
(card #363) and is now deleted; `systemd.services.fleet-patch` remains as the manual escape
hatch (`sudo systemctl start fleet-patch`, or run the script by hand). The `github` host runs the
CI job, so the job only *stages* its generation with `boot` instead of switching it: reboot
`github` to activate, until then it keeps running the previous system.

What the job trusts, and what to change when rotating anything:

- OpenBao role `auth/jwt-github/role/ci-fleet-patch` — `token_max_ttl 10m`, policy
  `fleet-patch-read` (read-only on the KV path below), and `bound_claims` of `repository_id`
  82301766, `ref: refs/heads/master`, `runner_environment: self-hosted`,
  `event_name: [schedule, workflow_dispatch]`, and
  `workflow_ref: John2143/dotfiles/.github/workflows/fleet-patch.yml@refs/heads/master`. A
  dispatch from any other branch or workflow is refused at login.
- KV `consumers/data/john2143-com/default/fleet-patch` — fields `ssh_private`, `ssh_public`,
  `ntfy_file`. The public half is also a `my-keys` entry in `flake.nix`, which is what makes it
  work fleet-wide; a new key needs both places plus one run of the job to distribute it.
- `scripts/fleet-known_hosts` — the host keys CI pins instead of reading a `~/.ssh`.

The runner gives the job a curated `PATH`: `nix`, `git`, `curl`, `bash` and coreutils, but **no
`ssh`, `jq`, `grep` or `python3`**, and its user has no git identity. That is why the job runs the
script inside `nix shell nixpkgs#openssh`, reads OpenBao with `nix run nixpkgs#jq`, matches with
bash `case` rather than `grep`, and sets `GIT_AUTHOR_*`/`GIT_COMMITTER_*` for the bump commit.
Drop the openssh wrapper and every host reports `FAILED (ssh)`, because the script tests the
connection itself and discards ssh's own message.

`REBOOT NEEDED` on every host is the steady state, not a failure: the job switches generations and
never reboots, so a kernel bump waits for you. The job's own host adds
`STAGED (host runs the CI job)`: `github` is only staged and takes the new generation on its next
reboot.

Run it by hand:

```fish
gh workflow run fleet-patch.yml                     # the full weekly run
gh workflow run fleet-patch.yml -f dry_run=true     # bump, evaluate, probe — changes nothing
gh workflow run fleet-patch.yml -f only=mirror -f bump=false
gh run watch                                        # follow the newest run
```

## What builds without being asked

Nothing rebuilds dotfiles on a schedule. The only recurring builds are in CI:

| What | When | Result |
|---|---|---|
| `fork-sync.yml` in `John2143/oh-my-pi` | daily 05:17 UTC, or `workflow_dispatch` | rebases the fork's patches on `upstream/main`, runs typecheck + native build + full suite, force-pushes `john` |
| `build-frigate-genai.yml` in dotfiles | on push to the frigate/nix paths, or by hand | builds both images, pushes to attic and ghcr, then bumps the tag in `2143-Labs/argo` |
| `attic-push-queue.timer` | 2 min after the previous run, on every host with attic | uploads paths queued by the post-build hook; it builds nothing |

Consequence for `omp`: the fork advances daily, and dotfiles' `flake.lock` follows it weekly when
the fleet-patch job runs (or whenever you switch by hand). Each host then builds the new
derivation itself — the first to finish queues it to attic and the rest substitute. There is
no scheduled warm; the hourly warmer is parked on `omp-warmer-wip` (card #450).

`fleet-patch` pushes to ntfy on failure (`notify-failure@fleet-patch`) and always sends its
report, summarised in the notification title, so a broken week is visible without logging in.
The argo Renovate CronJob pushes nowhere: its surface is `kubectl -n renovate get jobs` and
the Dependency Dashboard going stale.

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
ssh john@closet 'kubectl create job -n ddns ddns-verify --from=cronjob/desec-ddns --dry-run=client -o json' \
  | jq '.spec.template.spec.containers[0].env=[{"name":"FORCE","value":"1"}]' \
  | ssh john@closet 'kubectl create -f -'
ssh john@closet 'kubectl wait -n ddns --for=condition=complete job/ddns-verify --timeout=180s'
ssh john@closet 'kubectl logs -n ddns job/ddns-verify'
ssh john@closet 'kubectl delete job -n ddns ddns-verify'
```

## Where the outcome lives

- `~/.local/state/fleet-patch/last-run.md` — per-host table, plus a "Not managed" table for
  bigp and unifi-os. Each row is one of:
  - `ok`
  - `REBOOT NEEDED`
  - `STAGED (nvidia …): REBOOT NEEDED`
  - `STALE` — the switch reported success but the host is not on the evaluated generation
  - `LOCKED (deadman: …)` — the host failed its own boot/switch health check, returned itself
    to the last generation that passed, and locked itself; the run skipped it
  - `ROLLED BACK (deadman: …)` — this run's switch failed that same check and was rolled back
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
gh workflow disable fleet-patch.yml
ssh closet 'sudo -n k3s kubectl -n renovate patch cronjob renovate --type merge -p "{\"spec\":{\"suspend\":true}}"'
```

Re-enable it with `gh workflow enable fleet-patch.yml`; resume the CronJob with the same patch
and `{"spec":{"suspend":false}}`. Neither timer survives a missed window: trigger the workflow
by hand after re-enabling, and the CronJob with
`kubectl -n renovate create job --from=cronjob/renovate renovate-manual`.

## Roll back one host

```fish
ssh john@<ip> 'sudo -n nixos-rebuild switch --rollback'
```

On `arch`, `closet` or `nas`, do the cordon/LB steps from "Rebooting a k3s node" first: the
rollback restarts k3s, which means a 30–90 s API/ingress blip.

## What the weekly bump moves

`nixpkgs`, `nixpkgs-stable` and `oh-my-pi`. The omp input follows
`github:John2143/oh-my-pi/john`, a fork that `fork-sync` rebases onto `upstream/main`
daily at 05:17 UTC and gates on the full bun suite before force-pushing; a failed
gate leaves `john` where it was, so the bump simply finds nothing new.

There is deliberately **no** CI job that bumps this lock. Building omp on the runner
just to warm attic cost 30–40 min a day for a compile one host would have done anyway.
Attic's post-build hook (`nix.settings.post-build-hook`) is on for every host that
imports the attic module — office, arch, big, closet, pite, vpin, secu, term, github and
the `vm-*` clones — but not for `nas` (the cache server itself), `steam`, `mirror` or
`installer`. So the first *hooked* host that builds a new omp uploads it and every later
host substitutes it — within a couple of minutes, not instantly: the hook only appends to
`/var/lib/attic-push-queue/paths` and `attic-push-queue.timer` drains that spool with one
batched `attic push` every 2 minutes (5 minutes after boot). A rebuild started immediately
after another host's will still compile omp if the flush has not run yet. Keep the bump on
fleet-patch unless the omp compile starts landing on more than one host.

To move omp alone, between weekly runs:

```fish
cd ~/dotfiles && nix flake update oh-my-pi   # then rebuild one host
```

If a fleet patch fails with `unable to download 'http://nas:8280/2143nix/nar/<hash>.nar':
HTTP error 500`, the cache is the problem, not the patch — nix treats a substituter
500 as fatal and does **not** fall through to `cache.nixos.org`. Stop atticd for the
run and it falls back cleanly (`sudo systemctl stop atticd` on nas). Failure modes,
the watchdog and the DB's location are documented in `attic-cache.md`.

Build it through this flake, not the fork's own lock: the input follows dotfiles'
`nixpkgs` (`flake.nix`), so only this evaluation produces the same derivation every
host asks for. After the first host rebuilds, confirm the upload with
`nix path-info --store http://nas:8280/2143nix (nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.oh-my-pi.packages.x86_64-linux.omp.outPath')`.

## What a bump actually costs

Measured on office, 2026-11-13: a single `nix flake update` that moved `nixpkgs`
(2026-11-07 → 2026-11-11) *and* `oh-my-pi` (18.18.6 → 18.20.0) asked for **570
derivations, 453 of them `bun-pkg-*`**.

The reason omp always seems to rebuild from scratch: the nixpkgs bump rebuilds
`bun` itself (`r46nbq0d…-bun-1.4.4` → `0gk371kg…-bun-1.4.4`), and bun2nix keys
every package derivation off that runtime and its stdenv. One `bun` change
invalidates omp's whole JS closure — the npm versions are irrelevant. Bumping
nixpkgs *without* touching omp therefore costs the same 453 derivations.

Three kinds of package can never be substituted and always build on the first
host after a nixpkgs bump:

- **unfree** — `steam`, `discord`: cache.nixos.org never builds them, so attic
  only has what a host already built under the *current* hash;
- **locally overridden** — `voxtype` (`vulkanSupport = true` plus the `sqlite`
  buildInput in `nixos/shared-configuration.nix`): an override is in no binary
  cache, by construction;
- **module wrappers** — `firejail-wrapped-binaries`, the fhs/bwrap wrappers,
  waybar's unit and fish completions: local-only artifacts.

Consequence: after a bump, rebuild **one** host and let it upload, then let the
rest substitute. Do not fan a fresh bump across the fleet in parallel — every
host would build the same 500-odd derivations. If the first host is short on
cores, `--max-jobs 0` hands the work to `big` instead of building locally.

## Roll back a bump

```fish
git -C ~/dotfiles revert <chore(fleet): weekly input bump …>   # push it
gh workflow run fleet-patch.yml -f bump=false                   # deploy the revert
```

Keep running with `-f bump=false` until the revert is understood: a normal run re-bumps to
branch head, which would undo the revert. `gh workflow disable fleet-patch.yml` stops the
schedule entirely; `bao delete auth/jwt-github/role/ci-fleet-patch` makes every run fail at
login instead of touching a host.

## Roll back an argo bump

Revert the merged Renovate PR on `main`; ArgoCD self-heals it. Never re-pin an image by hand:
`automated: {prune, selfHeal}` will revert the edit anyway.

## Rebooting a k3s node

Not needed for the weekly job (it never reboots). Since 2026-11-03 `kured` reboots `arch`,
`closet` and `nas` one at a time, Wednesdays 12:00–17:00 America/New_York, and only when that
node's own `deadman needs-reboot` gate says the cluster can absorb the loss (all nodes Ready,
no degraded Longhorn volume, and every *existing* `openbao-N` / `*-db-N` pod Running and Ready —
a hibernated or scaled-to-zero CNPG cluster has no pod, so it is neither inspected nor an
obstacle). Its cordon is what makes
CNPG move each primary, so a kured reboot needs no promotion step. Expect the
`lh-volume-degraded` alert for up to ~1 h afterwards while replicas rebuild.

Expect the **ExternalSecret-backed apps to go `Degraded` for a few minutes** as well: the
reboot drops the `ClusterSecretStore`'s connection to OpenBao, every `ExternalSecret` retries
into `ClusterSecretStore "openbao" is not ready`, and ArgoCD's `ExternalSecret` health check
turns those Applications red. It clears by itself — observed 2026-11-23: the store was
`Ready=True` four minutes after the last node returned, and the fleet was back to 134
`Healthy` within ~10 minutes. One still `False` *after* the store is `Ready` is only waiting
out its retry backoff; `kubectl annotate externalsecret <name> force-sync=$(date +%s)
--overwrite` proves it immediately.

This procedure remains the way to reboot **big** or **pite** (kured does not manage them, and
they hold no cluster-wide kubeconfig to gate on) and to reboot a control plane outside the
window. The full procedure is `~/repos/argo/docs/node-maintenance.md`; the deviations that
matter:

**1. Gate.** Every row must show `READY` = `INST`. If any row is short, stop: the promote
target may not be ready.

```fish
ssh john@closet 'kubectl get clusters.postgresql.cnpg.io -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,INST:.spec.instances,READY:.status.readyInstances,PRIMARY:.status.currentPrimary'
```

**2. Promote** every primary the node holds onto another node. Each switchover drops that
database's connections for a few seconds. Rerun the gate afterwards; `PRIMARY` must show the
new instance.

```fish
ssh john@closet 'nix run nixpkgs#kubectl-cnpg -- promote <cluster> <instance-on-other-node> -n <namespace>'
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
inserted, or type the passphrase at its console (`nixos/modules/disko_secu.nix:26-27`). Since
`9153cef` the initrd also waits 10 s for `/dev/disk/by-partlabel/CRYPTKEY` and then falls back
to that prompt (`keyFileTimeout`; the scripted-stage-1 `fallbackToPassword` is a removed option
with no effect), so a missing stick is a prompt rather than a boot that never gets there.

**`pite`** permanently carries the exclude-from-LB label; never remove it on return.

## How long a run takes

A fresh `nixpkgs` bump usually substitutes from `nas:8280` and `cache.nixos.org`, and the x86
hosts finish in minutes. The three aarch64 hosts (`pite`, `vpin`, `mirror`) are rank-0 sinks in
`nixos/modules/remote-builders.nix`: they delegate to nobody, and when Hydra's aarch64 builds
lag behind a bump they compile from source at `--max-jobs 1`. Seeing `rustc` and `cc1` under
`nixbld1` on a Pi, with load above 10 and gigabytes of swap in use, is that — not a hang. On
2026-11-02 one such build ran past six hours and was still going.

So each host's switch is capped by `HOST_TIMEOUT` (default 1800 s = 30 min). A host that is
still building when the cap expires gets a `TIMEOUT (switch, 1800s)` row and the run moves on;
it is **not** a failure, but the run counts the day as needing attention. The remote build is
not cancelled — it keeps compiling after the script has stopped waiting, so the next
`ONLY="<host>"` run usually finds the work already in that host's store and finishes in
minutes. Give a genuinely slow host more room with
`HOST_TIMEOUT=14400 ONLY=pite BUMP=0 bash ~/dotfiles/scripts/fleet-patch.sh`.

The unit's own `TimeoutStartSec = 8h` is the outer backstop, sized above 13 hosts at the
per-host cap. If a run is killed by *it*, the hosts after that point have no rows and every
switch that already finished stays finished; finish the remainder with
`ONLY="<hosts missing from the table>" BUMP=0`. Do not lower `--max-jobs 1` on those hosts to
speed it up; they OOM.

If ARM builds keep timing out week after week, the real fix is to let `pite`/`vpin` delegate
aarch64 builds to `office` (which has `boot.binfmt.emulatedSystems = ["aarch64-linux"]` and is
already an `aarch64-linux` builder). That means changing their `rank` from 0 to 2 in
`nixos/modules/remote-builders.nix`. It cannot bootstrap itself — the host needs its old
builderless config to build the new one — so the first switch after the change has to be given
`HOST_TIMEOUT` room, or built on office and substituted.

## When a host fails

`FAILED (switch)` on `github` with a Python traceback ending `No usable temporary directory
found in ['/tmp', '/var/tmp', '/usr/tmp', '/home/john']` is a **full root filesystem**, not a
broken nixos-rebuild (`tempfile` reports ENOENT whatever the real error was). It happens
because `John2143/dotfiles` runs the frigate-genai image build on that host whenever a push
touches `flake.nix` or `flake.lock` — which every weekly bump does — so the switch can land
while the build is still writing to `/nix`.

```fish
ssh john@github 'df -h / /dev/sda1'          # root is the one that matters
gh run list -R John2143/dotfiles --limit 3          # is a build still running
```

Wait for the build to finish, confirm the root filesystem is back under about 80%, then rerun
that host alone: `ONLY=github BUMP=0 bash ~/dotfiles/scripts/fleet-patch.sh`. The same run
logs `No space left on device` from the runner, `swapfile` and k3s etcd if you look at
`journalctl` on that host at the time — those are symptoms of the same fill, not separate
faults.

`FAILED (switch)` on any other host is a real error: read the last 40 lines of `run.log`
before rerunning.

**A bumped `nixpkgs` can silently drop an option you still set.** `mkRemovedOptionModule` only
throws when something *reads* the option; once the module that consumed it is gone, nothing
does, so the definition stays, the build succeeds, and the setting is ignored.
`boot.initrd.luks.devices.<name>.fallbackToPassword` and disko's `preLVM` are both in that
state since the scripted stage 1 was removed. Read values back rather than trusting the file —
`nix eval --json '.#nixosConfigurations.secu.config.boot.initrd.luks.devices.cryptroot'` failed
on `preLVM` the moment it was asked, which is how this one was found.

## A LOCKED host (deadman)

Every k3s node except office runs `nixos/modules/deadman.nix`. After each boot and each live
switch it proves itself: `k3s` and `sshd` running, the API reporting the node `Ready`, and —
for a switch — a node lease renewed after the switch started. If it cannot within 15 min
(boot) or 10 min (switch), it points the profile at the last generation that passed, switches
to it, writes `/var/lib/deadman/locked`, and publishes the node condition `DeadmanLocked`.

A lock is a **freeze, not a cordon**: the node keeps serving, fleet-patch skips it, and kured
holds every reboot cluster-wide. Grafana's `deadman-locked` alert fires.

```fish
ssh john@<host> 'deadman status'                   # state, why, last good, last result
ssh john@<host> 'deadman needs-reboot; echo $status'   # 0 = kured may reboot it
```

Fix the cause in `~/dotfiles`, deploy to that host with `ONLY=<host>`, then clear the lock:

```fish
ssh john@<host> 'sudo deadman unlock'
```

`unlock` moves the lock file aside, records `unlocked by john`, and republishes
`DeadmanLocked=False`. It does **not** deploy anything, so a host can be unlocked and still be
on the older generation — check `deadman status` (`current` versus `default`).

Deadman is also kured's reboot sentinel on the control planes:

- `deadman needs-reboot` answers "reboot" only when the booted kernel differs from the
  profile's **and** the whole cluster passes its gate (all nodes Ready, no degraded or faulted
  Longhorn volume, exactly three `openbao-N` pods, and every `*-db-N` pod that exists Running and
  Ready). The check reads pods, so a cluster scaled to zero — CNPG hibernation leaves the CR but no
  pods — is invisible to it and can never hold a reboot.
- Any error — a locked node, a switch in flight, an unreachable API, a missing cluster
  kubeconfig — answers "do not reboot". That is why kured only runs on arch, closet and nas:
  only those three can read `/etc/rancher/k3s/k3s.yaml`. `sudo deadman gate` prints the same
  verdict by hand.

## After a bare reboot: a pod stuck in ContainerCreating

This is usually a corrupted ext4, not a scheduling problem. The journal recovers, but the CSI
driver runs `fsck -p` (preen), which refuses anything it cannot fix safely, so `MountDevice`
fails forever with:
```
'fsck' found errors on device /dev/longhorn/<pvc> but could not correct them
/dev/longhorn/<pvc>: UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY.
```
Repair it on the node the volume is attached to (`kubectl -n longhorn-system get
volumes.longhorn.io <pvc> -o jsonpath='{.spec.nodeID}'`):
```fish
ssh john@<node> 'sudo e2fsck -fn /dev/longhorn/<pvc>'     # read-only: see the damage first
ssh john@<node> 'sudo e2fsck -fy /dev/longhorn/<pvc>'     # repair
ssh john@<node> 'sudo e2fsck -fn /dev/longhorn/<pvc>'     # exit 0 = clean
```
Two traps, both hit on 2026-11-02:
- **Back up the block device first** if the data matters. A 50 GiB volume with 12 GiB used
  compressed to 36 GiB, so do not assume it fits on the node — closet had exactly 50 GiB free.
- **Do not delete the stuck pod between repairing and it starting.** Deleting it detaches the
  volume, the next attach starts a fresh engine from the replicas, and the repair is gone. The
  repair only sticks if you fix the engine that is already attached and then let the kubelet's
  own retry (up to ~5 min of backoff) mount that same engine.
- ArgoCD's `selfHeal` will undo a `kubectl scale --replicas=0` on a managed Deployment, so you
  cannot buy a quiet window that way without changing git.

## Adding a host

1. Add `name:max-jobs:address` to `HOSTS` in `scripts/fleet-patch.sh`, keeping control planes
   last. `1` max-jobs for the aarch64 Pis, `auto` for everything else.
2. Collect the key with `ssh-keyscan -t ed25519 <lan-ip>`, compare it with
   `ssh-keyscan -t ed25519 <tailnet-ip>`, and add it to `programs.ssh.knownHosts` in
   `nixos/modules/fleet-patching.nix`. An unpinned host fails with `Host key verification
   failed`; the job never trusts an unknown key.
3. Before trusting it, run `DRY_RUN=1 ONLY=<host> bash ~/dotfiles/scripts/fleet-patch.sh`.
