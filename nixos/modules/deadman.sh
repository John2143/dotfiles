# deadman: a k3s node must prove itself healthy after every boot and every live
# switch. If it cannot, it returns to the last generation that did, locks itself
# against automation (fleet-patch skips it, kured holds all reboots) and
# publishes Node condition DeadmanLocked=True until an operator runs
# `sudo deadman unlock`. Wired up by nixos/modules/deadman.nix.
#
# It is also kured's reboot sentinel, so the cluster-health gate lives here:
# needs-reboot answers "yes" only when this node's boot is healthy, the node is
# not locked or mid-switch, and the whole cluster passes cluster_ok(). Any
# error, including an unreachable API, answers "no" (fail closed).

STATE=/var/lib/deadman
LOCK=$STATE/locked
LAST_GOOD=$STATE/last-good
RESULT=$STATE/last-result
CHECKED_BOOT=$STATE/checked-boot-id
GCROOT=/nix/var/nix/gcroots/deadman-last-good
PROFILE=/nix/var/nix/profiles/system
NODE_KUBECONFIG=/var/lib/rancher/k3s/agent/kubelet.kubeconfig
# Cluster-wide reads need the server's admin kubeconfig; only control planes have
# it (/etc/rancher/k3s/k3s.yaml). Overridable for testing the fail-closed path.
ADMIN_KUBECONFIG=${DEADMAN_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
BOOT_DEADLINE=900     # seconds a freshly booted generation has to become healthy
SWITCH_DEADLINE=600   # seconds a freshly switched generation has to become healthy
STC_WAIT=1800         # longest wait for a running switch-to-configuration to finish

if [ "$(id -u)" = 0 ]; then mkdir -p "$STATE"; fi

now()    { date -u +%Y-%m-%dT%H:%M:%SZ; }
record() { printf '%s %s\n' "$(now)" "$*" > "$RESULT"; echo "deadman: $*"; }
lock()   { printf '%s %s\n' "$(now)" "$*" >> "$LOCK"; chmod 0644 "$LOCK"; echo "deadman: LOCKED: $*"; }
kc()     { k3s kubectl --kubeconfig "$NODE_KUBECONFIG" --request-timeout=10s "$@"; }
ac()     { k3s kubectl --kubeconfig "$ADMIN_KUBECONFIG" --request-timeout=15s "$@"; }
pin_last_good() { printf '%s\n' "$1" > "$LAST_GOOD"; ln -sfn "$1" "$GCROOT"; }

# healthy SINCE_EPOCH: k3s and sshd run, the API says this node is Ready, and the
# node's lease was renewed after SINCE_EPOCH (a Ready left over from before a
# fast reboot does not count).
healthy() {
  local since=$1 ready renew
  systemctl is-active --quiet k3s.service sshd.service || return 1
  ready=$(kc get node "$NODE" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null) || return 1
  [ "$ready" = True ] || return 1
  renew=$(kc get lease -n kube-node-lease "$NODE" -o 'jsonpath={.spec.renewTime}' 2>/dev/null) || return 1
  [ -n "$renew" ] || return 1
  [ "$(date -d "$renew" +%s)" -ge "$since" ]
}

wait_healthy() {
  local end
  end=$(( $(date +%s) + $2 ))
  until healthy "$1"; do
    if [ "$(date +%s)" -ge "$end" ]; then return 1; fi
    sleep 15
  done
}

# cluster_ok: the whole cluster must be in a state where losing one more node is
# safe. Fail closed: every read must succeed and must return usable output.
cluster_ok() {
  local nodes vols pods
  nodes=$(ac get nodes -o 'jsonpath={range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null) || return 1
  [ -n "$nodes" ] || return 1
  if printf '%s\n' "$nodes" | grep -qxv True; then return 1; fi
  vols=$(ac -n longhorn-system get volumes.longhorn.io -o 'jsonpath={range .items[*]}{.status.robustness}{"\n"}{end}' 2>/dev/null) || return 1
  [ -n "$vols" ] || return 1
  if printf '%s\n' "$vols" | grep -qE '^(degraded|faulted)$'; then return 1; fi
  pods=$(ac get pods -A -o 'jsonpath={range .items[*]}{.metadata.name} {.status.phase} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null) || return 1
  [ -n "$pods" ] || return 1
  printf '%s\n' "$pods" | awk '
    $1 ~ /^openbao-[0-9]+$/ || $1 ~ /-db-[0-9]+$/ {
      seen++
      if ($2 != "Running" || $3 != "True") bad++
      if ($1 ~ /^openbao-[0-9]+$/) ob++
    }
    END { exit (bad > 0 || ob != 3 || seen < 6) }'
}

# The node's own credential may not GET nodes/status (kubectl's subresource patch
# does that first, and the node authorizer refuses), but it may server-side apply
# the status subresource. SSA merges conditions by their `type` key, so the other
# conditions are untouched.
publish() {
  local t f lt cur prev prevt
  t=$(now)
  cur=$(kc get node "$NODE" -o 'jsonpath={range .status.conditions[?(@.type=="DeadmanLocked")]}{.status}:{.lastTransitionTime}{end}' 2>/dev/null) || cur=
  prev=${cur%%:*}
  prevt=${cur#*:}
  lt=$t
  if [ "$prev" = "$1" ] && [ -n "$prevt" ]; then lt=$prevt; fi
  f=$(mktemp)
  printf '{"apiVersion":"v1","kind":"Node","metadata":{"name":"%s"},"status":{"conditions":[{"type":"DeadmanLocked","status":"%s","reason":"%s","message":"%s","lastHeartbeatTime":"%s","lastTransitionTime":"%s"}]}}\n' \
    "$NODE" "$1" "$2" "$3" "$t" "$lt" >"$f"
  if ! kc apply --server-side --force-conflicts --subresource=status -f "$f" >/dev/null 2>&1; then
    echo "deadman: could not publish DeadmanLocked=$1; deadman-publish.timer retries every 15 min" >&2
  fi
  rm -f "$f"
}

publish_state() {
  local first
  if [ -e "$LOCK" ]; then
    first=$(head -n 1 "$LOCK" | tr -d '"' | tr -d '\134' | cut -c 1-200)
    publish True Locked "$first"
  else
    publish False Unlocked "automation allowed"
  fi
}

cmd_gate() {   # manual: would kured be allowed to reboot this node now?
  if cluster_ok; then echo "cluster healthy: a reboot would be allowed"; exit 0; fi
  echo "cluster NOT healthy, or the API is unreachable: a reboot would be held" >&2
  exit 1
}

cmd_needs_reboot() {   # kured sentinel: exit 0 = reboot now, 1 = do not
  [ ! -e "$LOCK" ] || exit 1
  if systemctl is-active --quiet deadman-switch-confirm.service; then exit 1; fi
  if [ /run/booted-system/kernel -ef "$PROFILE/kernel" ] \
     && [ /run/booted-system/kernel-modules -ef "$PROFILE/kernel-modules" ]; then
    exit 1
  fi
  if ! cluster_ok; then
    echo "deadman: holding the reboot: cluster not healthy or API unreachable" >&2
    exit 1
  fi
  exit 0
}

cmd_boot_check() {
  local boot_id booted current default boot_epoch good
  boot_id=$(cat /proc/sys/kernel/random/boot_id)
  if [ "$(cat "$CHECKED_BOOT" 2>/dev/null || true)" = "$boot_id" ]; then exit 0; fi
  printf '%s\n' "$boot_id" > "$CHECKED_BOOT"
  booted=$(readlink -f /run/booted-system)
  current=$(readlink -f /run/current-system)
  default=$(readlink -f "$PROFILE")
  if [ "$current" != "$booted" ]; then
    # Started by switch-to-configuration on first install, not by a boot.
    record "boot-check skipped: system switched since boot"
    publish_state
    exit 0
  fi
  boot_epoch=$(( $(date +%s) - $(cut -d . -f 1 /proc/uptime) ))
  if [ "$default" != "$booted" ]; then
    # systemd-boot skipped a generation whose boot counter ran out (or someone
    # picked an older entry by hand). Make the running generation the default.
    lock "boot fallback: booted $booted while the default was $default"
    nix-env -p "$PROFILE" --set "$booted"
    DEADMAN_ROLLBACK=1 "$booted/bin/switch-to-configuration" boot
    record "boot-fallback $booted (default was $default)"
    if wait_healthy "$boot_epoch" "$BOOT_DEADLINE"; then pin_last_good "$booted"; fi
    publish_state
    exit 0
  fi
  if wait_healthy "$boot_epoch" "$BOOT_DEADLINE"; then
    pin_last_good "$booted"
    record "boot-ok $booted"
    publish_state
    exit 0
  fi
  good=$(cat "$LAST_GOOD" 2>/dev/null || true)
  if [ -e "$LOCK" ]; then
    record "boot-unhealthy $booted (already locked; not rolling back again)"
    publish_state
    exit 1
  fi
  if [ -z "$good" ] || [ "$good" = "$booted" ] || [ ! -e "$good/bin/switch-to-configuration" ]; then
    lock "boot unhealthy: $booted not healthy within ${BOOT_DEADLINE}s; no other known-good generation"
    record "boot-unhealthy $booted (nothing to roll back to)"
    publish_state
    exit 1
  fi
  lock "boot unhealthy: $booted not healthy within ${BOOT_DEADLINE}s; rolled back to $good"
  nix-env -p "$PROFILE" --set "$good"
  DEADMAN_ROLLBACK=1 "$good/bin/switch-to-configuration" boot
  record "boot-rolled-back $booted -> $good; rebooting"
  systemctl --no-block reboot
  exit 1
}

cmd_pre_switch() {   # system.preSwitchChecks hook: must always exit 0
  local new action prev
  new=$1
  action=$2
  case "$action" in switch|test) ;; *) exit 0 ;; esac
  if [ -n "${DEADMAN_ROLLBACK:-}" ]; then exit 0; fi
  if [ -e "$LOCK" ]; then
    echo "deadman: $NODE is LOCKED; this switch is not guarded (see: deadman status)" >&2
    exit 0
  fi
  prev=$(readlink -f /run/current-system)
  if [ "$prev" = "$(readlink -f "$new")" ]; then exit 0; fi
  systemctl stop deadman-switch-confirm.service 2>/dev/null || true
  if ! systemd-run --no-block --collect --unit=deadman-switch-confirm \
      --description="deadman: confirm the switch to $new" \
      --property=RuntimeMaxSec=1h \
      "$0" confirm-switch "$prev" "$new" "$(date +%s)"; then
    echo "deadman: could not arm the switch guard; this switch is not guarded" >&2
  fi
  exit 0
}

cmd_confirm_switch() {   # runs as transient unit deadman-switch-confirm
  local prev new since end current
  prev=$1
  new=$2
  since=$3
  new=$(readlink -f "$new")
  end=$(( $(date +%s) + STC_WAIT ))
  while pgrep -f /bin/switch-to-configuration >/dev/null; do
    if [ "$(date +%s)" -ge "$end" ]; then break; fi
    sleep 10
  done
  current=$(readlink -f /run/current-system)
  if [ "$current" != "$new" ]; then
    record "switch-abandoned $new (current is $current)"
    exit 0
  fi
  if wait_healthy "$since" "$SWITCH_DEADLINE"; then
    pin_last_good "$current"
    record "switch-confirmed $current"
    exit 0
  fi
  lock "switch unhealthy: $current not healthy within ${SWITCH_DEADLINE}s; rolled back to $prev"
  nix-env -p "$PROFILE" --set "$prev"
  DEADMAN_ROLLBACK=1 "$prev/bin/switch-to-configuration" switch || true
  record "switch-rolled-back $current -> $prev"
  wait_healthy "$(date +%s)" "$SWITCH_DEADLINE" || true
  publish_state
  exit 1
}

cmd_status() {
  local l
  echo "node:        $NODE"
  if [ -e "$LOCK" ]; then
    echo "state:       LOCKED"
    while IFS= read -r l; do echo "             $l"; done < "$LOCK"
  else
    echo "state:       unlocked"
  fi
  echo "last-good:   $(cat "$LAST_GOOD" 2>/dev/null || echo none)"
  echo "last-result: $(cat "$RESULT" 2>/dev/null || echo none)"
  echo "booted:      $(readlink -f /run/booted-system)"
  echo "current:     $(readlink -f /run/current-system)"
  echo "default:     $(readlink -f "$PROFILE")"
}

cmd_unlock() {
  if [ "$(id -u)" != 0 ]; then echo "run as root: sudo deadman unlock" >&2; exit 1; fi
  if [ ! -e "$LOCK" ]; then echo "deadman: $NODE is not locked"; publish_state; exit 0; fi
  mv "$LOCK" "$STATE/unlocked-$(date -u +%Y%m%dT%H%M%SZ)"
  record "unlocked by ${SUDO_USER:-root}"
  publish_state
}

case "${1:-}" in
  gate)           cmd_gate ;;
  needs-reboot)   cmd_needs_reboot ;;
  boot-check)     cmd_boot_check ;;
  pre-switch)     cmd_pre_switch "$2" "$3" ;;
  confirm-switch) cmd_confirm_switch "$2" "$3" "$4" ;;
  publish)        publish_state ;;
  status)         cmd_status ;;
  unlock)         cmd_unlock ;;
  *) echo "usage: deadman status | deadman gate | sudo deadman unlock" >&2; exit 2 ;;
esac
