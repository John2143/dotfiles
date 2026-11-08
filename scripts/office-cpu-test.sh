#!/usr/bin/env bash
# Per-core CPU stability screen for office (i9-14900K, Intel Vmin Shift degradation). ~40 min.
# P-cores one at a time, one thread each, 3 min (single-thread load lets the core boost to its
# top bin, where degraded cores fail). Then all E-cores at once, one pinned stress-ng each
# (4 min). Then all cores (6 min), then RAM (6 min). Everything runs with --verify.
# Progress is fsync'd to $LOG so the core under test is known after a crash/auto-reboot.
# Usage (as john):  PHASE=A ~/dotfiles/scripts/office-cpu-test.sh
#   PHASE       label written to the log (A, A2, B1, B2, ...)
#   SKIP_APICS  space-separated APIC IDs of cores to skip, e.g. "0 32 66"
#   E_SERIAL=1  test E-cores one at a time (2 min each) instead of all at once; use after a
#               crash during the parallel E-core stage, to find the E-core that caused it
#   ALLCORE_SECS  seconds for the all-core stage (default 360). Real failures on this box
#               happen during long compiles, so Phase B runs this far longer than Phase A.
#   MEMORY_SECS   seconds for the RAM stage (default 360)
# Exit 0 = everything passed, 1 = at least one failure (summary at the end of $LOG).
set -u
command -v stress-ng >/dev/null || exec nix shell nixpkgs#stress-ng -c bash "$0" "$@"

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/office-cpu-test.log"
mkdir -p "$(dirname "$LOG")"
skip=" ${SKIP_APICS:-} "
allcore_secs="${ALLCORE_SECS:-360}"
memory_secs="${MEMORY_SECS:-360}"
failures=()
start=$(date '+%Y-%m-%d %H:%M:%S')

note() {
  echo "$(date -Is) $*" | tee -a "$LOG"
  sync "$LOG"
}

expand() { # "0-3,8" -> one cpu per line
  local part
  local -a parts
  IFS=, read -ra parts <<<"$1"
  for part in "${parts[@]}"; do
    if [[ $part == *-* ]]; then seq "${part%-*}" "${part#*-}"; else echo "$part"; fi
  done
}

apic_of() { awk -v c="$1" '/^processor/{p=$3} /^apicid/{if (p == c) print $3}' /proc/cpuinfo; }

run() { # label seconds stress-ng-args...
  local label=$1 secs=$2 rc
  shift 2
  note "START $label"
  stress-ng "$@" --verify --timeout "${secs}s" --metrics-brief
  rc=$?
  note "RESULT $label rc=$rc"
  [ "$rc" -eq 0 ] || failures+=("$label rc=$rc")
}

percore() { # type seconds cpulist
  local type=$1 secs=$2 c a first
  for c in $(expand "$3"); do
    first=$(cut -d, -f1 "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list")
    [ "${first%%-*}" = "$c" ] || continue
    a=$(apic_of "$c")
    if [[ $skip == *" $a "* ]]; then note "SKIP $type cpu=$c apic=$a"; continue; fi
    run "$type cpu=$c apic=$a" "$secs" --taskset "$c" --cpu 1 --cpu-method all --zlib 1
  done
}

eparallel() { # seconds cpulist: one pinned stress-ng per E-core, all at once
  local secs=$1 c a i rc
  local -a cpus=() apics=() pids=()
  for c in $(expand "$2"); do
    a=$(apic_of "$c")
    if [[ $skip == *" $a "* ]]; then note "SKIP E cpu=$c apic=$a"; continue; fi
    cpus+=("$c")
    apics+=("$a")
  done
  [ ${#cpus[@]} -gt 0 ] || return 0
  note "START EPAR apics=${apics[*]}"
  for i in "${!cpus[@]}"; do
    stress-ng --taskset "${cpus[$i]}" --cpu 1 --cpu-method all --zlib 1 --verify \
      --timeout "${secs}s" >"$LOG.cpu${cpus[$i]}" 2>&1 &
    pids+=($!)
  done
  for i in "${!cpus[@]}"; do
    wait "${pids[$i]}"
    rc=$?
    note "RESULT E cpu=${cpus[$i]} apic=${apics[$i]} rc=$rc"
    [ "$rc" -eq 0 ] || failures+=("E cpu=${cpus[$i]} apic=${apics[$i]} rc=$rc")
  done
  note "END EPAR"
}

note "=== RUN phase=${PHASE:-unlabeled} bios=$(cat /sys/class/dmi/id/bios_version) online=$(cat /sys/devices/system/cpu/online) offline=$(cat /sys/devices/system/cpu/offline) cap_cpu0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) allcore=${allcore_secs}s mem=${memory_secs}s skip=[${SKIP_APICS:-}]"
note "MAP $(awk '/^processor/{p=$3} /^apicid/{printf "%s:%s ", p, $3}' /proc/cpuinfo)"
percore P 180 "$(cat /sys/devices/cpu_core/cpus)"
if [ "${E_SERIAL:-0}" = 1 ]; then
  percore E 120 "$(cat /sys/devices/cpu_atom/cpus)"
else
  eparallel 240 "$(cat /sys/devices/cpu_atom/cpus)"
fi
run ALLCORE "$allcore_secs" --cpu -1 --cpu-method all
run MEMORY "$memory_secs" --vm 4 --vm-bytes 60% --vm-method all

kern=$(journalctl -k --since "$start" --no-pager | grep -E 'Hardware Error|Machine check|Oops|BUG:|stress-ng.*(segfault|invalid opcode|general protection)')
if [ -n "$kern" ]; then
  note "KERNEL $kern"
  failures+=("KERNEL")
fi

if [ ${#failures[@]} -eq 0 ]; then
  note "=== PASS phase=${PHASE:-unlabeled}"
  exit 0
fi
note "=== FAIL phase=${PHASE:-unlabeled}: ${failures[*]}"
exit 1
