# Attic binary cache

The fleet's substituter, running on `nas`. Every host that imports
`nixos/modules/attic.nix` pushes its builds here through a post-build hook
(`attic-push-queue`, see `fleet-patching.md`).

- **Endpoint** — `http://nas:8280`, cache name `2143nix`, priority 25, 90-day retention.
- **Public key** — `2143nix:zqt4fb8dINfCsQPqWQcggPm2eqk9RpotNh1u8QKRQVA=`,
  pinned in `nix.settings.trusted-public-keys` on every host. **Never regenerate
  it casually** — a new keypair means every host must re-trust the cache. The
  keypair lives in the `cache` table; `attic cache create` mints a new one.
- **Location** — DB `sqlite:///var/lib/atticd/server.db`, storage
  `/tank/atticd/storage`. Client config `/etc/attic/config.toml`, tokens in agenix
  (read them via `--netrc-file` / `XDG_CONFIG_HOME=/etc`; never print them).

## Why the DB is not on tank (2026-11-19)

The DB started on `tank/atticd/db`. `tank`'s txg is **pool-wide**, so every SQLite
commit waited for whatever else was dirty in that transaction group — Longhorn
rebuilds, seaweedfs, immich uploads — on a raidz1 whose two `ST8000DM004` members
are SMR. Under bulk I/O the DB blocked, the connection pool starved, and every
request died at the 30 s pool timeout. On 2026-11-19 a post-reboot Longhorn rebuild
produced 14 × 500 in the first five minutes.

The DB is 155 MB of metadata, so it now lives on the root SSD (`/dev/sda2`, ext4),
which is a different filesystem from `tank` and outside the pool's txg and its
corruption. `/var/lib/atticd` is `StateDirectory=atticd`, so ownership, mount
ordering and `ProtectSystem=strict` writability come from systemd.

Measured after the move, **while `tank` was still at 101 MB/s read / 152 MB/s write**:
narinfo 10–21 s → 19–22 ms, NAR 11–15 s → 48–84 ms, 69 × 500/20 min → 0.

`tank/atticd/db` still holds the pre-move copy. `systemd.services.atticd.preStart`
migrates it **only if** `/var/lib/atticd/server.db` is absent — so if you ever delete
the new DB deliberately, delete the old copy too, or the stale one is resurrected
at the next start. Once the move is old news, destroy the dataset.

## Failure modes — recognise them before touching anything

### 1. Pool starvation (the common one)

`ERROR ... Database error: Failed to acquire connection from pool: Connection pool
timed out`, every request 500s after exactly `latency=30002 ms`, `NRestarts=0`. The
daemon is healthy; the pool underneath is saturated by someone else. Threads pile up
in `D`. **It does not recover on its own** — restart atticd after the competing I/O
is gone, or the watchdog will. Since the DB moved this only happens if the *root* SSD
is saturated, so recurrence now means something else went wrong.

### 2. Wedged ZFS directory (needs a reboot)

Symptom: 200+ threads stuck in `D` inside `path_openat`, load average equals the
thread count, and **one** storage directory cannot be read — `ls` on it never
returns while its siblings list 14 000 entries in 60 ms. The process that touched it
first becomes unkillable: `kill -9` leaves it in `R` with the voluntary context-switch
counter frozen, because it never returns to a syscall boundary. `zpool status` is
clean and a scrub finds nothing.

This is an OpenZFS readdir/dentry hang, not atticd and not the DB:
[#4105](https://github.com/openzfs/zfs/issues/4105),
[#11621](https://github.com/openzfs/zfs/issues/11621),
[#5346](https://github.com/zfsonlinux/zfs/issues/5346),
[#6918](https://github.com/openzfs/zfs/issues/6918). **Only a reboot clears it.** It
was in-memory on 2026-11-19 — after the reboot the same directory listed in 97 ms.
If it survives a reboot, the shard is damaged on disk: wipe that subtree and let the
post-build hooks re-seed it (the cache is rebuildable).

### 3. Planner regression (attic#377)

atticd never runs `ANALYZE`, so `state = ?` looks as selective as `chunk_hash = ?` and
every chunk insert scans all valid chunks: one SQLite worker at 100 % CPU, uploads
collapse to ~0.5 MB/s. One `ANALYZE` flips the plan to `idx-chunk-chunk-hash` and an
8 MB push goes 15.19 s → 0.59 s. Re-run it as chunks accumulate:

```bash
python3 -c 'import sqlite3;c=sqlite3.connect("/var/lib/atticd/server.db");c.execute("ANALYZE");c.commit()'
```

### 4. Corruption

`narinfo` answers 200 in milliseconds while the NAR body streams zero bytes — the
metadata survived and the chunks did not. **Never verify with `narinfo` alone:**

```bash
curl -s --netrc-file /run/agenix/attic-netrc -o /dev/null \
  -w 'http=%{http_code} bytes=%{size_download} t=%{time_total}s\n' --max-time 60 \
  http://nas:8280/2143nix/nar/<hash>.nar       # want 200 AND bytes > 0
nix store verify --store http://nas:8280/2143nix \
  --option netrc-file /run/agenix/attic-netrc /nix/store/<path>
```

A NAR that delivers **some** bytes and then stops — `bytes=15898518` of 44,749,560
with the transfer never terminating — is not corruption but the dentry wedge: a
`du`/`find`/`ls -R` over `/tank/atticd/storage` wedges ZFS path lookups on `tank`
(twice on 2026-11-19), every affected atticd thread parks in
`path_openat`, and the chunk stream stalls mid-object while `narinfo` still answers
in milliseconds. Confirm with the blocked-thread count:

```bash
sudo cat /proc/$(systemctl show atticd -p MainPID --value)/task/*.stat | awk '$3=="D"' | wc -l
```

or the `atticd_blocked_threads` metric (`AtticThreadsBlocked` alerts above 50 for
10m). Hundreds means wedged; a handful is normal. `systemctl restart atticd` does
**not** clear it — the old daemon goes defunct with its threads still in `D`, holding
its SQLite handle, and the replacement dies on `database is locked`. A reboot does.
Never walk that tree: no `du`, `find` or `ls -R` on `/tank/atticd/storage`.

## Watchdog

`atticd-watchdog.timer` (every 5 min, `OnBootSec=10min`) probes a DB-backed narinfo
and restarts atticd on anything that is not a real HTTP answer — 5xx, timeout, refused.
atticd reports `active` through every wedge above, so systemd's `Restart=` can never
see these; the timer is the only automatic recovery. It exits early if atticd is not
active, so it will not fight a restart or an activation.

## Rebuilding a host while the cache is unhealthy

nix treats a **500** from a substituter as fatal for that path — it retries five times
and then fails the build; it does **not** fall through to `cache.nixos.org`. A
connection *refused* is only a warning. So when attic 500s and you must rebuild:

```bash
sudo systemctl stop atticd && nos      # nix falls back to cache.nixos.org
```

or override the substituter list for that one invocation
(`--option substituters https://cache.nixos.org`). This is why a broken cache looks
like "everything is broken" rather than "the cache is broken".

## Checking on it

```bash
systemctl status atticd atticd-watchdog.timer
sudo journalctl -u atticd --since '-30m' | grep -c 'Status code: 500'
curl -s --netrc-file /run/agenix/attic-netrc -o /dev/null -w '%{http_code} %{time_total}s\n' \
  http://nas:8280/2143nix/<hash>.narinfo
zfs list -o name,used,refer tank/atticd/storage
```
