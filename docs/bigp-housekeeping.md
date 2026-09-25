# bigp post-rebuild housekeeping

Last updated 2026-09-18.

`bigp` is a PowerEdge R740 (service tag `6V3QK93`) running Proxmox VE 9.2.2 on Debian trixie. It was
rebuilt on 2026-09-17 onto a new BOSS-S1 hardware RAID1 (`bigp_raid`) with a fresh Proxmox install and
restored `/etc`. This file records the state of the post-rebuild housekeeping items: what is verified
as already working, what is deliberately left alone, and what is still open.

## ZFS scrub/trim — verified working, do not change

`/etc/cron.d/zfsutils-linux` schedules `24 0 1-7 * *` → `/usr/lib/zfs-linux/trim` (TRIM, first
Sunday) and `24 0 8-14 * *` → `/usr/lib/zfs-linux/scrub` (scrub, second Sunday, gated on
`date +%w` = 0). `cron` is active and enabled; both helpers are executable. `zpool history tank` shows
exactly this cadence: `2026-08-09.00:24:02` and `2026-09-13.00:24:02`. Next run: **Sun 2026-10-11
00:24 EDT**. Systemd's `zfs-scrub-monthly@`/`zfs-scrub-weekly@` timers are deliberately **not** used,
and cron does not catch up a missed run (a scrub is skipped if the host is down at that minute).

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

## Deferred: Debian package upgrade

Procedure to run in a maintenance window — `apt update && apt full-upgrade`, then check whether a new
kernel arrived (`dpkg -l 'proxmox-kernel*' 'pve-kernel*' | tail -5`) and reboot only if one did.
Gracefully stop all guests before any reboot (`qm shutdown 105 104 103 102 101 100`, then
`systemctl reboot`). VMs 100, 101, 103, 104 and 105 have `onboot: 1` and return on their own; VM 102
(Windows) does not, so start it by hand afterwards. Proxmox packages are deliberately excluded from
`unattended-upgrades`, which is restricted to the Debian security origin on this host, so PVE and Ceph
upgrades happen only through this manual procedure.

Repairing the package sources on 2026-09-18 made the Proxmox stack visible to apt for the first time
(the previous enterprise-only sources returned 401 with no subscription key), so the pending set is
much larger than the handful of Debian updates that were visible before. Baseline captured on `bigp`
with `apt list --upgradable` on **2026-09-18 02:16 EDT**: **181** entries — of the 179 the resolver
would upgrade, 99 come from the Debian channels, 74 from the Proxmox channels and 6 from
`trixie-security` alone; 2 are held back (`proxmox-kernel-7.0`, `pve-firewall`). Headline deltas:
PVE 9.2.2 → 9.2.20, `proxmox-kernel-7.0` 7.0.2-6 → 7.0.14-17 (**a reboot would be required**), and
Ceph 19.2.3-pve4 → 19.2.6-pve4.

```
base-files/stable 13.8+deb13u7 amd64 [upgradable from: 13.8+deb13u5]
bash/stable 5.2.37-2+b10 amd64 [upgradable from: 5.2.37-2+b9]
bind9-dnsutils/stable-security 1:9.20.29-1~deb13u1 amd64 [upgradable from: 1:9.20.21-1~deb13u1]
bind9-host/stable-security 1:9.20.29-1~deb13u1 amd64 [upgradable from: 1:9.20.21-1~deb13u1]
bind9-libs/stable-security 1:9.20.29-1~deb13u1 amd64 [upgradable from: 1:9.20.21-1~deb13u1]
bsdextrautils/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
bsdutils/stable,stable-security 1:2.41.5-0+deb13u1 amd64 [upgradable from: 1:2.41-5]
busybox/stable 1:1.37.0-6+b9 amd64 [upgradable from: 1:1.37.0-6+b8]
ceph-common/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
ceph-fuse/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
chrony/stable 4.8-4~bpo13+2 amd64 [upgradable from: 4.6.1-3+deb13u1]
corosync/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
curl/stable 8.14.1-2+deb13u5 amd64 [upgradable from: 8.14.1-2+deb13u3]
dhcpcd-base/stable 1:10.1.0-11+deb13u4 amd64 [upgradable from: 1:10.1.0-11+deb13u2]
dirmngr/stable 2.4.7-21+deb13u1+b5 amd64 [upgradable from: 2.4.7-21+deb13u1+b3]
e2fsprogs/stable 1.47.2-3+b12 amd64 [upgradable from: 1.47.2-3+b11]
eject/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
fdisk/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
frr-pythontools/stable 10.6.1-1+pve3 all [upgradable from: 10.6.1-1+pve2]
frr/stable 10.6.1-1+pve3 amd64 [upgradable from: 10.6.1-1+pve2]
gpg-agent/stable 2.4.7-21+deb13u1+b5 amd64 [upgradable from: 2.4.7-21+deb13u1+b3]
gpgconf/stable 2.4.7-21+deb13u1+b5 amd64 [upgradable from: 2.4.7-21+deb13u1+b3]
gpgsm/stable 2.4.7-21+deb13u1+b5 amd64 [upgradable from: 2.4.7-21+deb13u1+b3]
gpg/stable 2.4.7-21+deb13u1+b5 amd64 [upgradable from: 2.4.7-21+deb13u1+b3]
gzip/stable 1.13-1+deb13u1 amd64 [upgradable from: 1.13-1]
krb5-locales/stable,stable-security 1.21.3-5+deb13u1 all [upgradable from: 1.21.3-5]
libasound2-data/stable 1.2.14-1+deb13u1 all [upgradable from: 1.2.14-1]
libasound2t64/stable 1.2.14-1+deb13u1 amd64 [upgradable from: 1.2.14-1]
libaudit1/stable 1:4.0.2-2+deb13u1 amd64 [upgradable from: 1:4.0.2-2+b2]
libaudit-common/stable 1:4.0.2-2+deb13u1 all [upgradable from: 1:4.0.2-2]
libblkid1/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
libbytes-random-secure-perl/stable 0.29-4~deb13u1 all [upgradable from: 0.29-3]
libc6/stable 2.41-12+deb13u4 amd64 [upgradable from: 2.41-12+deb13u3]
libcap2-bin/stable 1:2.75-10+deb13u1+b3 amd64 [upgradable from: 1:2.75-10+deb13u1+b1]
libcap2/stable 1:2.75-10+deb13u1+b3 amd64 [upgradable from: 1:2.75-10+deb13u1+b1]
libc-bin/stable 2.41-12+deb13u4 amd64 [upgradable from: 2.41-12+deb13u3]
libcephfs2/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
libcfg7/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
libc-l10n/stable 2.41-12+deb13u4 all [upgradable from: 2.41-12+deb13u3]
libcmap4/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
libcom-err2/stable 1.47.2-3+b12 amd64 [upgradable from: 1.47.2-3+b11]
libcorosync-common4/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
libcpg4/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
libcurl3t64-gnutls/stable 8.14.1-2+deb13u5 amd64 [upgradable from: 8.14.1-2+deb13u3]
libcurl4t64/stable 8.14.1-2+deb13u5 amd64 [upgradable from: 8.14.1-2+deb13u3]
libevent-2.1-7t64/stable-security 2.1.13-stable-1~deb13u1 amd64 [upgradable from: 2.1.12-stable-10+b1]
libevent-core-2.1-7t64/stable-security 2.1.13-stable-1~deb13u1 amd64 [upgradable from: 2.1.12-stable-10+b1]
libexpat1/stable,stable-security 2.8.3-1~deb13u1 amd64 [upgradable from: 2.7.1-2]
libext2fs2t64/stable 1.47.2-3+b12 amd64 [upgradable from: 1.47.2-3+b11]
libfdisk1/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
libgbm1/stable 25.0.7-2+deb13u1 amd64 [upgradable from: 25.0.7-2]
libgcrypt20/stable,stable-security 1.11.0-7+deb13u1 amd64 [upgradable from: 1.11.0-7]
libglib2.0-0t64/stable 2.84.4-3~deb13u5 amd64 [upgradable from: 2.84.4-3~deb13u3]
libgraphite2-3/stable 1.3.14-2+deb13u1 amd64 [upgradable from: 1.3.14-2+b1]
libgssapi-krb5-2/stable,stable-security 1.21.3-5+deb13u1 amd64 [upgradable from: 1.21.3-5]
libgstreamer-plugins-base1.0-0/stable-security 1.26.2-1+deb13u2 amd64 [upgradable from: 1.26.2-1+deb13u1]
libhtml-parser-perl/stable 3.83-2~deb13u1 amd64 [upgradable from: 3.83-1+b2]
libhttp-daemon-perl/stable,stable-security 6.16-1+deb13u1 all [upgradable from: 6.16-1]
libjs-extjs/stable 7.0.0-7 all [upgradable from: 7.0.0-5]
libk5crypto3/stable,stable-security 1.21.3-5+deb13u1 amd64 [upgradable from: 1.21.3-5]
libknet1t64/stable 1.35-pve2 amd64 [upgradable from: 1.31-pve1]
libkrb5-3/stable,stable-security 1.21.3-5+deb13u1 amd64 [upgradable from: 1.21.3-5]
libkrb5support0/stable,stable-security 1.21.3-5+deb13u1 amd64 [upgradable from: 1.21.3-5]
liblastlog2-2/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
libldb2/stable 2:2.11.0+samba4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:2.11.0+samba4.22.8+dfsg-0+deb13u1]
liblzma5/stable 5.8.1-1+deb13u1 amd64 [upgradable from: 5.8.1-1]
libmount1/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
libnet-dns-perl/stable,stable-security 1.56-0+deb13u1 all [upgradable from: 1.50-1]
libnozzle1t64/stable 1.35-pve2 amd64 [upgradable from: 1.31-pve1]
libnss3/stable,stable-security 2:3.110-1+deb13u4 amd64 [upgradable from: 2:3.110-1+deb13u1]
libnvpair3linux/stable 2.4.4-pve1 amd64 [upgradable from: 2.4.2-pve1]
libpcre2-16-0/stable 10.46-1~deb13u2 amd64 [upgradable from: 10.46-1~deb13u1]
libpcre2-8-0/stable 10.46-1~deb13u2 amd64 [upgradable from: 10.46-1~deb13u1]
libpcre2-posix3/stable 10.46-1~deb13u2 amd64 [upgradable from: 10.46-1~deb13u1]
libperl5.40/stable 5.40.1-6+deb13u1 amd64 [upgradable from: 5.40.1-6]
libproxmox-acme-perl/stable 1.7.2 all [upgradable from: 1.7.1]
libproxmox-acme-plugins/stable 1.7.2 all [upgradable from: 1.7.1]
libproxmox-backup-qemu0/stable 2.0.3 amd64 [upgradable from: 2.0.2]
libpve-access-control/stable 9.1.2 all [upgradable from: 9.1.1]
libpve-apiclient-perl/stable 3.4.3 all [upgradable from: 3.4.2]
libpve-cluster-api-perl/stable 9.1.6 all [upgradable from: 9.1.5]
libpve-cluster-perl/stable 9.1.6 all [upgradable from: 9.1.5]
libpve-common-perl/stable 9.2.2 all [upgradable from: 9.1.12]
libpve-guest-common-perl/stable 6.0.5 all [upgradable from: 6.0.3]
libpve-network-api-perl/stable 1.6.7 all [upgradable from: 1.6.5]
libpve-network-perl/stable 1.6.7 all [upgradable from: 1.6.5]
libpve-notify-perl/stable 9.1.6 all [upgradable from: 9.1.5]
libpve-storage-perl/stable 9.1.10 all [upgradable from: 9.1.5]
libpython3.13-minimal/stable 3.13.5-2+deb13u5 amd64 [upgradable from: 3.13.5-2+deb13u2]
libpython3.13-stdlib/stable 3.13.5-2+deb13u5 amd64 [upgradable from: 3.13.5-2+deb13u2]
libquorum5/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
librabbitmq4/stable,stable-security 0.15.0-1+deb13u2 amd64 [upgradable from: 0.15.0-1]
librados2-perl/stable 1.5.1 amd64 [upgradable from: 1.5.0]
librados2/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
libradosstriper1/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
librbd1/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
librgw2/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
libslirp0/stable 4.8.0-1+deb13u1 amd64 [upgradable from: 4.8.0-1+b1]
libsmartcols1/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
libsmbclient0/stable 2:4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:4.22.8+dfsg-0+deb13u1]
libsqlite3-0/stable 3.46.1-7+deb13u2 amd64 [upgradable from: 3.46.1-7+deb13u1]
libss2/stable 1.47.2-3+b12 amd64 [upgradable from: 1.47.2-3+b11]
libssh2-1t64/stable 1.11.1-1+deb13u2 amd64 [upgradable from: 1.11.1-1]
libssl3t64/stable,stable-security 3.5.7-1~deb13u2 amd64 [upgradable from: 3.5.6-1~deb13u1]
libtalloc2/stable 2:2.4.3+samba4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:2.4.3+samba4.22.8+dfsg-0+deb13u1]
libtasn1-6/stable 4.20.0-2+deb13u1 amd64 [upgradable from: 4.20.0-2]
libtdb1/stable 2:1.4.13+samba4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:1.4.13+samba4.22.8+dfsg-0+deb13u1]
libtevent0t64/stable 2:0.16.2+samba4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:0.16.2+samba4.22.8+dfsg-0+deb13u1]
libunbound8/stable,stable-security 1.22.0-2+deb13u3 amd64 [upgradable from: 1.22.0-2+deb13u2]
libuuid1/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
libuutil3linux/stable 2.4.4-pve1 amd64 [upgradable from: 2.4.2-pve1]
libvotequorum8/stable 3.1.10-pve3 amd64 [upgradable from: 3.1.10-pve2]
libwbclient0/stable 2:4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:4.22.8+dfsg-0+deb13u1]
libxml2/stable 2.12.7+dfsg+really2.9.14-2.1+deb13u3 amd64 [upgradable from: 2.12.7+dfsg+really2.9.14-2.1+deb13u2]
libxml-libxml-perl/stable 2.0207+dfsg+really+2.0134-5+deb13u1 amd64 [upgradable from: 2.0207+dfsg+really+2.0134-5+b2]
libzfs7linux/stable 2.4.4-pve1 amd64 [upgradable from: 2.4.2-pve1]
libzpool7linux/stable 2.4.4-pve1 amd64 [upgradable from: 2.4.2-pve1]
locales/stable 2.41-12+deb13u4 all [upgradable from: 2.41-12+deb13u3]
login/stable,stable-security 1:4.16.0-2+really2.41.5-0+deb13u1 amd64 [upgradable from: 1:4.16.0-2+really2.41-5]
logsave/stable 1.47.2-3+b12 amd64 [upgradable from: 1.47.2-3+b11]
mesa-libgallium/stable 25.0.7-2+deb13u1 amd64 [upgradable from: 25.0.7-2]
mount/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
novnc-pve/stable 1.7.0-2 all [upgradable from: 1.7.0-1]
openssl-provider-legacy/stable,stable-security 3.5.7-1~deb13u2 amd64 [upgradable from: 3.5.6-1~deb13u1]
openssl/stable,stable-security 3.5.7-1~deb13u2 amd64 [upgradable from: 3.5.6-1~deb13u1]
perl-base/stable 5.40.1-6+deb13u1 amd64 [upgradable from: 5.40.1-6]
perl-modules-5.40/stable 5.40.1-6+deb13u1 all [upgradable from: 5.40.1-6]
perl/stable 5.40.1-6+deb13u1 amd64 [upgradable from: 5.40.1-6]
postfix/stable,stable-security 3.10.13-0+deb13u1 amd64 [upgradable from: 3.10.5-1~deb13u1]
proxmox-backup-client/stable 4.2.6-1 amd64 [upgradable from: 4.2.0-1]
proxmox-backup-file-restore/stable 4.2.6-1 amd64 [upgradable from: 4.2.0-1]
proxmox-enterprise-support-keyring/stable 1.1 all [upgradable from: 1.0]
proxmox-kernel-7.0/stable 7.0.14-17 amd64 [upgradable from: 7.0.2-6]
proxmox-kernel-helper/stable 9.2.0 all [upgradable from: 9.1.0+fde2]
proxmox-mini-journalreader/stable 1.7 amd64 [upgradable from: 1.6]
proxmox-widget-toolkit/stable 5.2.8 all [upgradable from: 5.2.2]
pve-cluster/stable 9.1.6 amd64 [upgradable from: 9.1.5]
pve-container/stable 6.1.14 all [upgradable from: 6.1.10]
pve-docs/stable 9.2.11 all [upgradable from: 9.2.1]
pve-edk2-firmware-aarch64/stable 4.2026.08-1 all [upgradable from: 4.2025.05-2]
pve-edk2-firmware-legacy/stable 4.2026.08-1 all [upgradable from: 4.2025.05-2]
pve-edk2-firmware-ovmf/stable 4.2026.08-1 all [upgradable from: 4.2025.05-2]
pve-edk2-firmware/stable 4.2026.08-1 all [upgradable from: 4.2025.05-2]
pve-firewall/stable 6.0.6 amd64 [upgradable from: 6.0.4]
pve-firmware/stable 3.18-6 all [upgradable from: 3.18-3]
pve-ha-manager/stable 5.2.5 amd64 [upgradable from: 5.2.4]
pve-i18n/stable 3.10.0 all [upgradable from: 3.7.4]
pve-manager/stable 9.2.20 all [upgradable from: 9.2.2]
pve-qemu-kvm/stable 11.0.3-3 amd64 [upgradable from: 11.0.0-3]
pve-xtermjs/stable 6.0.0-2 all [upgradable from: 6.0.0-1]
pve-yew-mobile-gui/stable 0.8.0 amd64 [upgradable from: 0.7.0]
pve-yew-mobile-i18n/stable 3.10.0 all [upgradable from: 3.7.4]
python3.13-minimal/stable 3.13.5-2+deb13u5 amd64 [upgradable from: 3.13.5-2+deb13u2]
python3.13/stable 3.13.5-2+deb13u5 amd64 [upgradable from: 3.13.5-2+deb13u2]
python3-ceph-argparse/stable,stable 19.2.6-pve4 all [upgradable from: 19.2.3-pve4]
python3-ceph-common/stable,stable 19.2.6-pve4 all [upgradable from: 19.2.3-pve4]
python3-cephfs/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
python3-idna/stable 3.10-1+deb13u1 all [upgradable from: 3.10-1]
python3-rados/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
python3-rbd/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
python3-rgw/stable,stable 19.2.6-pve4 amd64 [upgradable from: 19.2.3-pve4]
python3-urllib3/stable,stable-security 2.3.0-3+deb13u2 all [upgradable from: 2.3.0-3+deb13u1]
qemu-server/stable 9.2.8 amd64 [upgradable from: 9.1.15]
rsync/stable 3.4.1+ds1-5+deb13u4 amd64 [upgradable from: 3.4.1+ds1-5+deb13u2]
samba-common/stable 2:4.22.11+dfsg-0+deb13u1 all [upgradable from: 2:4.22.8+dfsg-0+deb13u1]
samba-libs/stable 2:4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:4.22.8+dfsg-0+deb13u1]
shim-helpers-amd64-signed/stable 1+16.1+2+pmx1 amd64 [upgradable from: 1+16.1+1+pmx1]
shim-signed-common/stable 1.51+pmx1+16.1-2+pmx1 all [upgradable from: 1.48+pmx1+16.1-1+pmx1]
shim-signed/stable 1.51+pmx1+16.1-2+pmx1 amd64 [upgradable from: 1.48+pmx1+16.1-1+pmx1]
shim-unsigned/stable 16.1-2+pmx1 amd64 [upgradable from: 16.1-1+pmx1]
smbclient/stable 2:4.22.11+dfsg-0+deb13u1 amd64 [upgradable from: 2:4.22.8+dfsg-0+deb13u1]
socat/stable 1.8.0.3-1+deb13u1 amd64 [upgradable from: 1.8.0.3-1]
sqlite3/stable 3.46.1-7+deb13u2 amd64 [upgradable from: 3.46.1-7+deb13u1]
tzdata/stable 2026c-0+deb13u1 all [upgradable from: 2026b-0+deb13u1]
util-linux-extra/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
util-linux/stable,stable-security 2.41.5-0+deb13u1 amd64 [upgradable from: 2.41-5]
xfsprogs/stable 6.13.0-2+deb13u1 amd64 [upgradable from: 6.13.0-2+b1]
xz-utils/stable 5.8.1-1+deb13u1 amd64 [upgradable from: 5.8.1-1]
zfs-initramfs/stable 2.4.4-pve1 all [upgradable from: 2.4.2-pve1]
zfsutils-linux/stable 2.4.4-pve1 amd64 [upgradable from: 2.4.2-pve1]
zfs-zed/stable 2.4.4-pve1 amd64 [upgradable from: 2.4.2-pve1]
```

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
