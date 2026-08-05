# Daily disk health check for nas: zpool + SMART.
# Alerts (journald, exit != 0) on: pool not healthy, SMART health not PASSED,
# pending/uncorrectable sectors > 0, or reallocated-sector growth vs the
# previous run (state in /var/lib/nas-disk-health).
# Physical disks sda-sdf only. sdg-sdl are Longhorn iSCSI volumes (no SMART).
{ config, lib, pkgs, ... }:

let
  healthScript = pkgs.writeShellScript "nas-disk-health" ''
    set -uo pipefail
    disks="sda sdb sdc sdd sde sdf"
    state=/var/lib/nas-disk-health
    problems=0

    if ! zpool status -x 2>/dev/null | grep -q "all pools are healthy"; then
      echo "DISK-HEALTH-ALERT: zpool not healthy" >&2
      problems=1
    fi

    for d in $disks; do
      dev=/dev/$d
      if ! smartctl -H "$dev" 2>/dev/null | grep -qi "PASSED"; then
        echo "DISK-HEALTH-ALERT: $dev SMART health not PASSED" >&2
        problems=1
      fi
      pending=$(smartctl -a "$dev" 2>/dev/null | awk '/Current_Pending_Sector/ {print $NF}')
      if [ -n "$pending" ] && [ "$pending" -gt 0 ] 2>/dev/null; then
        echo "DISK-HEALTH-ALERT: $dev has $pending pending sectors" >&2
        problems=1
      fi
      realloc=$(smartctl -a "$dev" 2>/dev/null | awk '/Reallocated_Sector_Ct/ {print $NF}')
      prev=""
      [ -f "$state/$d" ] && prev=$(cat "$state/$d")
      if [ -n "$realloc" ] && [ -n "$prev" ] && [ "$realloc" -gt "$prev" ] 2>/dev/null; then
        echo "DISK-HEALTH-ALERT: $dev reallocated sectors grew $prev -> $realloc" >&2
        problems=1
      fi
      [ -n "$realloc" ] && echo "$realloc" > "$state/$d"
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
    path = [ pkgs.smartmontools pkgs.zfs ];
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
