#!/usr/bin/env bash
# Fleet patch: optionally bump nixpkgs, switch every NixOS host to the pushed
# commit, report. Never reboots, never drains. Run by fleet-patch.service, or by
# hand as john (see docs/fleet-patching.md).
#   DRY_RUN=1   bump + evaluate + probe only: no commit, push, switch or ntfy
#   BUMP=0      skip the nixpkgs bump; deploy origin/master as-is
#   ONLY="a b"  only these hosts (ring order kept; leaving out office skips the canary)
# Hosts with nixos/modules/deadman.nix: LOCKED hosts are skipped; a switch is judged
# only after the host's own guard confirms it or rolls it back.
# Uses only bash builtins + git/nix/ssh/curl/flock/timeout: an interactive PATH may
# put ripgrep first as `grep`, so the script never calls grep/sed locally.
set -uo pipefail

STATE=/home/john/.local/state/fleet-patch
CLONE=$STATE/dotfiles
ORIGIN=git@github.com:John2143/dotfiles.git
FLAKE_BASE=github:John2143/dotfiles
LOG=$STATE/run.log
REPORT=$STATE/last-run.md
ATTENTION=$STATE/ATTENTION
DRY_RUN=${DRY_RUN:-0}
BUMP=${BUMP:-1}
ONLY=${ONLY:-}
HOST_TIMEOUT=${HOST_TIMEOUT:-1800}   # per-host switch cap; aarch64 source builds can exceed it
KUBE_HOST=192.168.5.36   # closet: john's kubeconfig there works
SUDO=/run/wrappers/bin/sudo
REBUILD=/run/current-system/sw/bin/nixos-rebuild
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes
     -o ServerAliveInterval=30 -o ServerAliveCountMax=10)

# Ring order, control planes last. name:max-jobs:address
HOSTS=(
  office:auto:local
  big:auto:192.168.5.68
  github:auto:192.168.5.108
  steam:1:192.168.5.122
  pite:1:192.168.5.9
  mirror:1:192.168.5.123
  vpin:1:192.168.5.118
  secu:auto:192.168.5.140
  aman:auto:aman
  term:auto:term
  arch:auto:192.168.5.76
  closet:auto:192.168.5.36
  nas:auto:192.168.5.175
)
CONTROL_PLANE=" arch closet nas "
# Not NixOS: probed and reported, never changed. name:user@address
EXTERNAL=(bigp:root@192.168.5.19 unifi-os:john@192.168.5.30)

mkdir -p "$STATE"
exec 9>"$STATE/lock"
flock -n 9 || { echo "fleet-patch already running" >&2; exit 0; }
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.1"
rm -f "$ATTENTION"
printf '# fleet patch %s\n\n' "$(date -Is)" > "$REPORT"

log()       { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG" >&2; }
fail()      { : > "$ATTENTION"; log "FAILED: $*"; }
row()       { printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" >> "$REPORT"; }
selected()  { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }
is_cp()     { [[ "$CONTROL_PLANE" == *" $1 "* ]]; }
label()     { local b=${1##*/}; echo "${b#*-}"; }              # store path -> name without hash
kname()     { local d=${1%/*}; d=${d##*/}; echo "${d#*-}"; }   # …/<hash>-linux-6.18.59/bzImage -> linux-6.18.59
count()     { local n=0 l; while IFS= read -r l; do [[ $l == *"$1"* ]] && n=$((n + 1)); done < "$REPORT"; echo "$n"; }
on_host()   { if [ "$1" = local ]; then bash -c "$2"; else "${SSH[@]}" "john@$1" "$2"; fi; }
on_host_t() { local t=$1; shift; if [ "$1" = local ]; then timeout "$t" bash -c "$2"; else timeout "$t" "${SSH[@]}" "john@$1" "$2"; fi; }
reachable() { [ "$1" = local ] || timeout 6 bash -c "exec 3<>/dev/tcp/$1/22" 2>/dev/null; }

notify() {
  [ "$DRY_RUN" = 1 ] && return 0
  local f=/run/agenix/ntfy-topic-url prio=default tags=white_check_mark title
  [ -r "$f" ] || { log "no $f; no notification sent"; return 0; }
  set -a; . "$f"; set +a
  [ -e "$ATTENTION" ] && { prio=high; tags=warning; }
  title="fleet-patch: $(count '| ok |') ok, $(count 'REBOOT NEEDED') need reboot, $(count '| FAILED') failed, $(count '| TIMEOUT') timed out, $(count '| STALE') stale, $(count '| LOCKED') locked, $(count '| ROLLED BACK') rolled back"
  curl -fsS -m 20 -H "Title: $title" -H "Priority: $prio" -H "Tags: $tags" \
    --data-binary @"$REPORT" "${NTFY_TOPIC_URL:?}" >/dev/null || log "ntfy post failed"
}
trap notify EXIT

# --- 1. fresh clone of origin/master (never your working tree) --------------
if [ ! -d "$CLONE/.git" ]; then
  git clone -q "$ORIGIN" "$CLONE" >>"$LOG" 2>&1 || { fail "git clone failed"; exit 1; }
fi
cd "$CLONE" || exit 1
git rebase --abort >/dev/null 2>&1
if ! { git fetch -q origin master && git checkout -q -f -B master origin/master && git clean -qfdx; } >>"$LOG" 2>&1; then
  fail "could not reset the job clone to origin/master"; exit 1
fi

# --- 2. bump inputs; a failed bump never blocks deploying master -------------
# nixpkgs plus oh-my-pi, whose `john` branch is rebased onto upstream/main and
# gated by the full bun test suite in John2143/oh-my-pi's fork-sync workflow
# (daily). This is the weekly step that actually moves omp on office/arch.
bumped=no
if [ "$BUMP" = 1 ]; then
  if ! nix flake update nixpkgs nixpkgs-stable oh-my-pi >>"$LOG" 2>&1; then
    git checkout -q -- flake.lock
    fail "nix flake update failed; deploying origin/master unbumped"
  elif git diff --quiet -- flake.lock; then
    log "inputs already current"
  else
    gate=ok
    for entry in "${HOSTS[@]}"; do
      h=${entry%%:*}
      nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" >>"$LOG" 2>&1 \
        || { gate=bad; fail "bumped lock does not evaluate for $h; bump discarded"; break; }
    done
    if [ "$gate" = bad ]; then
      git checkout -q -- flake.lock
    elif [ "$DRY_RUN" = 1 ]; then
      bumped="would bump (dry run)"
      git checkout -q -- flake.lock
    elif git commit -q -m "chore(fleet): weekly input bump $(date +%Y-%m-%d)" -- flake.lock >>"$LOG" 2>&1 \
         && { git push -q origin master >>"$LOG" 2>&1 \
              || { git pull -q --rebase origin master >>"$LOG" 2>&1 && git push -q origin master >>"$LOG" 2>&1; }; }; then
      bumped=yes
    else
      git rebase --abort >/dev/null 2>&1
      git reset -q --hard origin/master
      fail "could not commit/push the bump; deploying origin/master unbumped"
    fi
  fi
fi

# --- 3. switch every host to the pushed commit, in ring order ---------------
REV=$(git rev-parse HEAD)
FLAKE=$FLAKE_BASE/$REV
printf 'commit `%s` (nixpkgs bumped: %s)\n\n| host | result | kernel running | kernel after reboot |\n|---|---|---|---|\n' \
  "${REV:0:12}" "$bumped" >> "$REPORT"
cp_hold=0
for entry in "${HOSTS[@]}"; do
  IFS=: read -r name jobs addr <<<"$entry"
  selected "$name" || continue
  if is_cp "$name" && [ "$cp_hold" = 1 ]; then row "$name" "HELD (earlier control plane failed)" – –; continue; fi
  if ! want=$(nix eval --raw "$FLAKE#nixosConfigurations.$name.config.system.build.toplevel.outPath" 2>>"$LOG"); then
    row "$name" "FAILED (eval)" – –; fail "$name does not evaluate at $REV"
    [ "$name" = office ] && { log "canary failed; stopping"; exit 1; }
    continue
  fi
  if ! reachable "$addr"; then row "$name" OFFLINE – –; log "$name offline"; continue; fi
  # deadman (nixos/modules/deadman.nix): a locked host returned itself to an older
  # generation after a failed boot or switch. Never move it until an operator
  # runs `sudo deadman unlock` on it.
  lockmsg=$(on_host "$addr" "cat /var/lib/deadman/locked" 2>/dev/null); rc=$?
  if [ "$rc" = 255 ]; then row "$name" "FAILED (ssh)" – –; fail "$name: ssh failed"; continue; fi
  if [ "$rc" = 0 ]; then row "$name" "LOCKED (deadman: ${lockmsg%%$'\n'*})" – –; fail "$name is deadman-locked; skipped"; continue; fi
  # GPU hosts: if the loaded nvidia module differs from the target driver, stage with
  # `boot` instead of `switch` (new NVIDIA userspace on an old module breaks NVML).
  # ssh exits 255 on connection failure; `cat` exits 1 when no nvidia module is loaded.
  mode=switch nvnote=
  loaded=$(on_host "$addr" "cat /sys/module/nvidia/version" 2>/dev/null); rc=$?
  if [ "$rc" = 255 ]; then row "$name" "FAILED (ssh)" – –; fail "$name: ssh failed"; continue; fi
  [ "$rc" = 0 ] || loaded=
  if [ -n "$loaded" ]; then
    if ! wantnv=$(nix eval --raw "$FLAKE#nixosConfigurations.$name.config.hardware.nvidia.package.version" 2>>"$LOG"); then
      row "$name" "FAILED (eval nvidia)" – –; fail "$name: cannot evaluate its nvidia driver version"; continue
    fi
    [ "$wantnv" != "$loaded" ] && { mode=boot; nvnote="nvidia $loaded → $wantnv"; }
  fi
  if [ "$DRY_RUN" = 1 ]; then
    if cur=$(on_host "$addr" "readlink -f /run/current-system" 2>>"$LOG"); then
      row "$name" "DRY RUN $mode${nvnote:+ ($nvnote)}: $(label "$cur") → $(label "$want")" – –
    else
      row "$name" "FAILED (ssh)" – –; fail "$name: ssh failed"
    fi
    continue
  fi
  log "$mode $name${nvnote:+ ($nvnote)}"
  # Bounded: an aarch64 source build on a Pi can run for hours (see
  # docs/fleet-patching.md). Stop waiting, say so, and move on. The remote
  # build keeps going, so a later `ONLY=<host>` usually finds it cached.
  on_host_t "$HOST_TIMEOUT" "$addr" "$SUDO -n $REBUILD $mode --flake '$FLAKE#$name' --max-jobs $jobs" >>"$LOG" 2>&1
  rc=$?
  if [ "$rc" = 124 ]; then
    row "$name" "TIMEOUT ($mode, ${HOST_TIMEOUT}s)" – –
    : > "$ATTENTION"
    log "$name still building after ${HOST_TIMEOUT}s; not failed, rerun ONLY=\"$name\" later"
    is_cp "$name" && { cp_hold=1; fail "holding the remaining control planes"; }
    continue
  fi
  if [ "$rc" != 0 ]; then
    row "$name" "FAILED ($mode)" – –; fail "$name $mode failed"
    [ "$name" = office ] && { log "canary failed; stopping"; exit 1; }
    is_cp "$name" && { cp_hold=1; fail "holding the remaining control planes"; }
    continue
  fi
  # The host's deadman guard confirms or rolls back this switch by itself; judge
  # the host only after its verdict. Hosts without the module return at once.
  if [ "$mode" = switch ]; then
    for ((i = 0; i < 80; i++)); do
      on_host "$addr" "systemctl is-active --quiet deadman-switch-confirm.service" 2>/dev/null || break
      sleep 15
    done
    if lockmsg=$(on_host "$addr" "cat /var/lib/deadman/locked" 2>/dev/null); then
      row "$name" "ROLLED BACK (deadman: ${lockmsg%%$'\n'*})" – –
      fail "$name failed its post-switch health check; rolled back and locked"
      is_cp "$name" && { cp_hold=1; fail "holding the remaining control planes"; }
      continue
    fi
  fi
  sys=/run/current-system; [ "$mode" = boot ] && sys=/nix/var/nix/profiles/system
  mapfile -t p < <(on_host "$addr" "readlink -f $sys $sys/kernel /run/booted-system/kernel" 2>>"$LOG")
  if [ "${#p[@]}" -ne 3 ]; then row "$name" "FAILED (probe)" – –; fail "$name post-$mode probe failed"; continue; fi
  if [ "${p[0]}" != "$want" ]; then res=STALE; fail "$name has $(label "${p[0]}") at $sys, expected $(label "$want")"
  elif [ "$mode" = boot ]; then res="STAGED ($nvnote): REBOOT NEEDED"
  elif [ "${p[1]}" != "${p[2]}" ]; then res="REBOOT NEEDED"
  else res=ok; fi
  row "$name" "$res" "$(kname "${p[2]}")" "$(kname "${p[1]}")"
  log "$name -> $res"
  if is_cp "$name"; then
    sleep 30; settled=0
    for ((i = 0; i < 10; i++)); do
      if "${SSH[@]}" "john@$KUBE_HOST" "kubectl wait --for=condition=Ready node/arch node/closet node/nas --timeout=60s" >>"$LOG" 2>&1; then
        settled=1; break
      fi
      sleep 30
    done
    [ "$settled" = 1 ] || { cp_hold=1; fail "control planes not Ready after $name; holding the rest"; }
  fi
done

# --- 4. hosts this job does not manage: kernel + pending updates ------------
printf '\n### Not managed by this job\n\n| host | kernel running | newest installed | upgradable packages |\n|---|---|---|---|\n' >> "$REPORT"
for entry in "${EXTERNAL[@]}"; do
  name=${entry%%:*}; target=${entry#*:}
  mapfile -t e < <("${SSH[@]}" "$target" 'uname -r; ls /boot | sed -n "s/^vmlinuz-//p" | sort -V | tail -n 1; apt list --upgradable 2>/dev/null | grep -c upgradable' 2>>"$LOG")
  if [ "${#e[@]}" -eq 3 ]; then
    k=${e[0]}; [ "${e[0]}" != "${e[1]}" ] && k="${e[0]} (REBOOT NEEDED)"
    row "$name" "$k" "${e[1]}" "${e[2]}"
  else
    row "$name" UNREACHABLE – –
  fi
done

printf '\nReboot procedure: ~/dotfiles/docs/fleet-patching.md\n' >> "$REPORT"
log "done; report at $REPORT"
[ -e "$ATTENTION" ] && exit 1
exit 0
