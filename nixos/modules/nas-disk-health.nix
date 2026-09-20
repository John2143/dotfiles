# Daily disk health check for nas: zpool + SMART.
# Alerts (journald, exit != 0) on: pool not healthy, SMART health not PASSED,
# pending/uncorrectable sectors > 0, or reallocated-sector growth vs the
# previous run (state in /var/lib/nas-disk-health).
#
# Iterates /dev/disk/by-id/ata-* whole disks — sdX letters shift across
# reboots (WD SSD was sdf, then sdb after a reboot), so names must be stable.
# sdg-sdl are Longhorn iSCSI volumes (no ata-* by-id) and are skipped.
#
# Notes:
# - smartctl -H exits 32 on drives with marginal attributes even when health
#   prints PASSED (Seagate ST8000DM004 airflow-temp history); combined with
#   `set -o pipefail` that made pipelines fail, so output is captured and
#   grepped from a variable instead of chaining in a condition.
# - awk (gawk) is explicitly added to the service PATH.
{ config, lib, pkgs, ... }:

let
  healthScript = pkgs.writeShellScript "nas-disk-health" ''
    set -uo pipefail
    shopt -s nullglob
    state=/var/lib/nas-disk-health
    problems=0

    poolstatus=$(zpool status -x 2>/dev/null)
    if ! echo "$poolstatus" | grep -q "all pools are healthy"; then
      echo "DISK-HEALTH-ALERT: zpool not healthy" >&2
      problems=1
    fi

    # Enumerate across all local transports, not just ata-* — NVMe devices are
    # nvme-*, and disks behind an HBA expose only wwn-*/scsi-*. Order matters:
    # ata-*/nvme-* win over the duplicate wwn-*/scsi-* links for the same device,
    # and the resolved-device check drops the duplicates. Existing ata-* state
    # files keep their names, so reallocated-sector history is preserved.
    declare -A seen
    for dev in /dev/disk/by-id/ata-* /dev/disk/by-id/nvme-* \
               /dev/disk/by-id/scsi-* /dev/disk/by-id/wwn-*; do
      case "$dev" in
        *-part*) continue ;; # partition symlinks would double-scan the same disk
      esac
      real=$(readlink -f "$dev")
      [ -n "''${seen[$real]:-}" ] && continue
      smart=$(smartctl -a "$dev" 2>/dev/null)
      # Skip devices with no SMART (Longhorn iSCSI LUNs, virtual disks) so an
      # absent attribute can never be read as a healthy disk.
      echo "$smart" | grep -qi "SMART support is:.*\(Available\|Enabled\)" || continue
      seen[$real]=1
      name=$(basename "$dev")

      if ! echo "$smart" | grep -qi "PASSED"; then
        echo "DISK-HEALTH-ALERT: $name SMART health not PASSED" >&2
        problems=1
      fi

      pending=$(echo "$smart" | grep "Current_Pending_Sector" | awk '{print $NF}')
      if [ -n "$pending" ] && [ "$pending" -gt 0 ] 2>/dev/null; then
        echo "DISK-HEALTH-ALERT: $name has $pending pending sectors" >&2
        problems=1
      fi

      realloc=$(echo "$smart" | grep "Reallocated_Sector_Ct" | awk '{print $NF}')
      prev=""
      [ -f "$state/$name" ] && prev=$(cat "$state/$name")
      if [ -n "$realloc" ] && [ -n "$prev" ] && [ "$realloc" -gt "$prev" ] 2>/dev/null; then
        echo "DISK-HEALTH-ALERT: $name reallocated sectors grew $prev -> $realloc" >&2
        problems=1
      fi
      [ -n "$realloc" ] && echo "$realloc" > "$state/$name"
    done

    if [ "$problems" -eq 0 ]; then
      echo "DISK-HEALTH-OK: tank and all SMART disks healthy"
    fi
    exit "$problems"
  '';
in
{
  systemd.services.nas-disk-health = {
    description = "Daily disk health check (zpool status + SMART)";
    path = [ pkgs.smartmontools pkgs.zfs pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "nas-disk-health";
    };
    script = ''
      ${healthScript}
    '';
  };

  systemd.timers.nas-disk-health = {
    description = "Daily disk health check for nas";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

}
