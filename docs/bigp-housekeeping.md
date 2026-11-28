# bigp post-rebuild housekeeping

Last updated 2026-11-27.

`bigp` is a PowerEdge R740 (service tag `6V3QK93`) running Proxmox VE 9.3.1 on kernel
`7.0.14-30-pve`, Debian trixie. It was rebuilt on 2026-09-17 onto a new BOSS-S1 hardware RAID1
(`bigp_raid`) with a fresh Proxmox install and restored `/etc`. This file records the state of the
post-rebuild housekeeping items: what is verified as already working, what is deliberately left alone,
and what is still open.

## ZFS scrub/trim — verified working, do not change

`/etc/cron.d/zfsutils-linux` schedules `24 0 1-7 * *` → `/usr/lib/zfs-linux/trim` (TRIM, first
Sunday) and `24 0 8-14 * *` → `/usr/lib/zfs-linux/scrub` (scrub, second Sunday, gated on
`date +%w` = 0). `cron` is active and enabled; both helpers are executable. `zpool history tank` shows
exactly this cadence: `2026-08-09.00:24:02` and `2026-09-13.00:24:02`; the latest scrub finished
`Sun 2026-11-08 00:44:35` (repaired 0B, 0 errors). Next run: **Sun 2026-12-13 00:24 EST**.
Systemd's `zfs-scrub-monthly@`/`zfs-scrub-weekly@` timers are deliberately **not** used, and cron does
not catch up a missed run (a scrub is skipped if the host is down at that minute).

## Alerting — currently silent, configuration to apply later

iDRAC (at `192.168.5.254`, FW `7.00.00.181`) has every destination disabled:
`EmailAlert.1..4.Enable = Disabled` with empty `.Address`, `SNMPAlert.1..5.State = Disabled` with
empty `.Destination`, `RemoteHosts.1.SMTPServerIPAddress = 0.0.0.0`, `RemoteHosts.1.SMTPPort = 25`,
`RemoteHosts.1.ConnectionEncryption = STARTTLS`, `SNMP.1.AlertPort = 162`,
`IPMILan.1.AlertEnable = Disabled`. These attributes are readable and writable through
`PATCH /redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellAttributes/iDRAC.Embedded.1` with body
`{"Attributes": {"<Name>": "<Value>"}}` — the GET on that endpoint was exercised, the **PATCH was
not**; confirm a 200 before relying on it, and fall back to the iDRAC web UI (Configuration → System
Settings → Alert Configuration) if it is refused. A minimal email setup is
`EmailAlert.1.Enable=Enabled`, `EmailAlert.1.Address=<recipient>`,
`RemoteHosts.1.SMTPServerIPAddress=<smtp host>`, `RemoteHosts.1.SenderEmail=<sender>`, adding
`RemoteHosts.1.SMTPAuthentication=Enabled` + `.SMTPUserName`/`.SMTPPassword` only if the relay
requires it.

**Status 2026-09-24:** still accurate for *hardware* alerting, but backup alerting provably works —
the `pbs-daily` job's notifications are delivered, because postfix on bigp sends them direct-to-MX
(`mail.protonmail.ch:25`) for `root@pam`'s address (`john@2143.me`) and the queue clears cleanly each
night at ~02:03. iDRAC's own destinations remain disabled exactly as described above.


## ZED can already push to ntfy but is unconfigured

`/etc/zfs/zed.d/zed.rc` ships `ZED_NTFY_TOPIC` (line ~163), `ZED_NTFY_ACCESS_TOKEN` (~171) and
`ZED_NTFY_URL="https://ntfy.sh"` (~178) commented out; `ZED_NOTIFY_INTERVAL_SECS=3600` is already
set. Setting a non-empty `ZED_NTFY_TOPIC` plus `systemctl restart zfs-zed` enables pool-event pushes.
**The topic URL is a capability secret: read it from the operator's secret store and never commit it
to this repo.**

## Root's mail — fixed 2026-09-24 (previously a black hole)

Was: `/etc/aliases` defined no `root:` entry while postfix ran `inet_interfaces = loopback-only` with
an empty `relayhost`, so everything `smartd-runner`, cron and ZED mailed to root went to an unread
local mbox (`/var/mail/` holds no `root` file). Fixed on 2026-09-24:

- `/etc/aliases` → `root: technology@m.2143.me`, then `newaliases`.
- `/etc/postfix/transport` → `m.2143.me smtp:[192.168.6.13]:25`, plus
  `transport_maps = hash:/etc/postfix/transport` in `main.cf`, then `systemctl reload postfix`.
  **The transport map is required, not optional:** split-horizon DNS resolves `m.2143.me` to
  `192.168.6.11` (the Traefik webmail ingress), which has **no SMTP listener** on 25 or 587, so mail
  to the mail domain otherwise fails with `connect to m.2143.me[192.168.6.11]:25: No route to host`.
  The MetalLB mail load balancer is `192.168.6.13`.
- Verified in the log: `to=<technology@m.2143.me>, orig_to=<root@bigp.local>,
  relay=192.168.6.13[192.168.6.13]:25, status=sent (250 2.0.0 Message queued with id …)`.
- Pre-change originals are at `/root/aliases.orig-20260924` and `/root/main.cf.orig-20260924`.

Net effect: SMART disk alerts (`-m root` in `/etc/smartd.conf`), cron reports (including the ZFS
scrub/trim jobs) and ZED output now reach a monitored mailbox instead of vanishing. Mail to other
domains is untouched — `john@2143.me` still resolves to Proton's MX and is delivered directly.

## Disk health is now iDRAC-only

With the BOSS presenting `DELLBOSS VD` (`bigp_raid`, RAID1, mirrored, write-through),
`smartctl -i /dev/sdd` reports `SMART support is: Unavailable - device lacks SMART capability` and
`-d sat+megaraid,0` returns nothing, so the PVE SMART tab for the boot disk is blank and smartd cannot
watch the two M.2s. `mvcli` (BOSS-S1 CLI) and the iDRAC storage/fault endpoints are the only
in-band/out-of-band ways to see member health. Members: `PHYH102006H0240J` (firmware `XC31DL6R`,
18 223 power-on hours) and `PHYH01820CDS240J` (firmware `XC31DL6P`, 39 536 power-on hours) — the
higher-hours member is the one expected to fail first.

## Deliberate non-action: M.2 firmware mismatch

`XC31DL6P` (Apr 2020) vs `XC31DL6R` (Sep 2020, latest Dell build for `SSDSCKKB240G8R`). Left alone
because flashing a live RAID member is riskier than the mismatch; if it is ever aligned, do it on a
spare, off the array.

## Package upgrades — PVE 9.3.1 landed 2026-11-27

`apt full-upgrade` ran on 2026-11-27 and cleared the backlog that the 2026-09-18 source repair created
(**181** entries then): **174 upgraded, 11 newly installed, 0 removed**. The host is now
`proxmox-ve 9.3.0` / `pve-manager 9.3.1` on kernel **7.0.14-30-pve**, `pve-qemu-kvm 11.1.3-4`,
`zfsutils-linux 2.4.4-pve1`, and `apt-get -s full-upgrade` reports `0 upgraded`. Nothing is held back
any more — the two packages pinned before (`proxmox-kernel-7.0`, `pve-firewall`) moved with the rest.
PVE packages remain excluded from `unattended-upgrades` (restricted to the Debian security origin), so
this stays a manual procedure.

**Why it happened when it did:** advisory **PSA-2026-00111-1** (2026-11-26, no CVE) — an out-of-bounds
read in `pvefw-logger` lets a crafted ICMPv6 packet leak host memory into
`/var/log/pve-firewall.log`. Fixed in **`pve-firewall 6.0.9`**, which is what runs now. There was no
smaller fix: installing only `pve-firewall` pulls 45 packages including `pve-manager`, because the
archive has no self-consistent subset.

**How it was done — two phases, not one window:**

1. *Phase A, live, guests running*: config archive first
   (`/root/pve-etc-2026-11-27.tgz`, 61 files), then
   `apt-get -y -o Dpkg::Options::=--force-confold full-upgrade` under
   `setsid nohup … > /root/apt-upgrade-2026-11-27.log` so a dropped SSH session cannot SIGHUP dpkg.
   Took 292 s, 944 log lines, no `E:`/`W:` and no conffile prompt. `--force-confold` is needed for
   `/etc/issue` (`base-files`); there is no `needrestart` on this host. PVE point releases apply live,
   and the `pve-firewall` postinst restarts `pvefw-logger.service`
   (`/var/lib/dpkg/info/pve-firewall.postinst:31`) — that restart, not a reboot, is what closes the
   advisory.
2. *Phase B, the disruptive part*: guests down, reboot, verify, guests up.

**Reboot procedure that was used (18:41–18:58, ~17 min):**

- Shut guests down in order, each with `--forceStop 1` as the fallback after its timeout:
  `qm shutdown 102 --timeout 300` (Windows), then 150, 104, 105, 101, then
  `qm shutdown 100 --timeout 300` (big, ~150 s while k3s stops), then 103. All seven stopped cleanly;
  none needed the forced stop.
- Do **not** `kubectl drain big` first: the other nodes cannot absorb its CPU requests, and draining
  faults the Longhorn instance-manager and its single-replica volumes.
- `systemctl reboot`. The host was back in **~2 min**; first SSH already reported `7.0.14-30-pve`.
- `pve-guests.service` autostarted 100, 101, 103, 104, 105 and 150 (all `onboot: 1`, in parallel — no
  guest has a `startup:` order). **102 (Windows) has no `onboot` and must be started by hand**
  (`qm start 102`).
- Verify after the reboot: `uname -r`; `zfs --version` **and** `modinfo -F version zfs` (both must read
  `2.4.4-pve1` — before the reboot the image was still running module 2.4.2-pve1); `zpool status tank`;
  `pvesm status`; `systemctl --failed`; `timedatectl show -p NTPSynchronized --value`.

### Do not "fix" the ZFS import units

`tank` is imported **on demand by PVE**, not at boot, and that is the intended design here:

- the pool has `cachefile=none`, so `/etc/zfs/zpool.cache` is 0 bytes, so `zfs-import-cache.service`
  skips every boot (`ConditionFileNotEmpty` unmet);
- `zfs-import-scan.service` is disabled by the `50-zfs.preset` default;
- `PVE::Storage::ZFSPoolPlugin::activate_storage` runs
  `zpool import -d /dev/disk/by-id/ -o cachefile=none tank` when the first guest touching a `tank`
  volume starts — it appears in `zpool history tank` seconds after each boot (2026-11-27 18:51:37 the
  last time).

So `zpool list` legitimately shows nothing until guests are up, and every guest disk lives on `tank`
(see `qm config <id>`). Enabling the scan unit or writing a cache file is not a bug fix; it changes a
working design.

### Kernel rollback stays available — do not `zpool upgrade`

`7.0.2-6-pve` is still installed and in the GRUB submenu (*Advanced options for Proxmox VE GNU/Linux*),
so a bad boot can be reverted from the iDRAC virtual console (`https://192.168.5.254`). That only holds
while the pool's feature set stays compatible: **never run `zpool upgrade tank`** without first
deciding to give the old kernel up. The 9.3 opt-ins were likewise left alone — the 7.3 kernel branch is
not installed and the nftables backend is not enabled.

### Firewall backend on 9.3: still iptables, not nftables

`proxmox-firewall.service` (nftables) is `active`, but it is a no-op: `nft list ruleset` is **empty**,
`use_nftables` is absent from `/etc/pve/datacenter.cfg`, and policy is still enforced by the `PVEFW-*`
chains in iptables-legacy (165 of them). "proxmox-firewall is active" does not mean "nftables is in
use" — check `nft list ruleset`. Taking the 9.3 nftables opt-in is a separate change with its own
testing.

### What a reboot costs the cluster (observed 2026-11-27)

- `big` was down ~10 min, past the 5 min default toleration, so **212 eviction events** fired and its
  pods were rescheduled onto arch/closet/nas. They drift back afterwards (36 pods on `big` right after
  boot, 103 about 40 min later). Expect requests near the ceiling in between — `closet` at 98% CPU,
  `nas` at 99% memory.
- **The rescheduling itself is what does the damage, and it is load, not disk.** `arch` (16 cores) went
  from a `node_load1` baseline of 3–5 to **48.4** (18:40–19:50 local: 48.4 / 38.9 / 26.0 / 42.0 /
  47.3). Its kubelet fell behind on the node lease, the node was `NotReady` 19:22–19:28, and the taint
  manager evicted pods on it (`DeletionByTaintManager`, including `loki-write-0` and `openbao-1`).
  The `arch` replica of three Longhorn volumes failed at 00:23Z and they went `degraded`; the
  single-replica `data-loki-write-0` went **`faulted`**. `openbao-1` was killed mid-write and its
  bbolt raft db came back corrupt (`freepages: failed to get all reachable pages`), so it never
  restarted cleanly — that is the one thing here that did not heal itself (card #50).
- **Do not read this as a disk problem.** At the worst moment `arch`'s `/` was 79% used of 443 GiB and
  17% of its inodes, and `kube_node_status_condition{condition="DiskPressure"}` read `false` at every
  sample all night. Disk pressure is not the signal for this failure mode, and nothing alerts on load
  or IO saturation today. Budget headroom on arch before the next `big`-side reboot rather than
  watching its disk.
- Recovery needs no intervention: Longhorn rebuilt and every volume was `healthy` within ~1 h
  (`replica-replenishment-wait-interval=3600s`), `loki-write-0` came back on its own, and `arch` was
  rebooted at 19:55 — a clean `systemd-reboot`, not a crash, so the corruption did not come from an
  unclean shutdown.
- `tempo-0` crash-looped once because SeaweedFS was not ready yet, then reported
  `backend-worker: Starting` for ~10 min before settling to `Healthy/Synced`. Do not restart it early;
  it recovers on its own.
- `mattermost-db` reads `Suspended` — that is the CNPG hibernation annotation
  (`cnpg.io/hibernation: on`), not damage.
- Health checks that actually work: UniFi's UI is on **:11443** (inform agent on :8080), **not** 443.

### Unverified

The PBS **server** version on VM 103 is still unknown: `root@192.168.5.20` refuses key auth and
`/api2/json/version` needs credentials. The host side is `proxmox-backup-client 4.2.14-1`, and a
`vzdump 105` snapshot backup to `pbs` succeeded on 2026-11-27, so the path works — but the server's own
version (the subject of PSA-2026-00086-1) has never been read.


## Open hardware items

From the iDRAC SEL, unchanged by the rebuild: 2026-07-31 17:45 —
`Multi-bit memory errors are detected on the memory device at location(s) DIMM_A2. Immediately
replace the DIMM.` preceded by repeated correctable warnings for the same DIMM; and six paired events
across 2026-08-11 → 2026-08-13 — `The Power Supply Unit (PSU) 1` and `(PSU) 2 is not receiving input
power because of issues in PSU or cable connections`, each followed seconds later by an
input-power-restored event. Both PSUs are `PWR SPLY,750W,RDNT,LTON` and hot-pluggable; both supplies
reported the fault, which points at shared upstream power/cabling rather than one supply. Neither item
was inspected physically during the rebuild.

## Deliberate non-action: PBS job scope

The `pbs-daily` job covers `100,101,102,104,105` and omits `103` (the `proxmox-backup` VM). Left as
is: PBS cannot usefully back itself up into itself.
