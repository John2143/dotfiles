#!/usr/bin/env bash
# fleet-reboot-cycle: reboot every host that has a newer kernel staged, one host
# at a time, gated the way kured gates itself. Run this on office: it needs
# mikrotik-connect locally and ssh to closet for the admin kubeconfig.
#
#   bash scripts/fleet-reboot-cycle.sh --dry-run   # gates + dry-run drains, no changes
#   bash scripts/fleet-reboot-cycle.sh             # asks before each host
#   bash scripts/fleet-reboot-cycle.sh --yes       # no prompts
#   bash scripts/fleet-reboot-cycle.sh --hosts=big,pite
#
# Per host: cluster gate -> cordon -> withdraw from BGP -> wait for CNPG to move
# its primaries off the node -> selective drain with kured's own stay list ->
# reboot -> wait for Ready and the new kernel -> uncordon -> re-announce -> wait
# for the node's pods and for Longhorn to finish rebuilding.
#
# Not in the default list:
#   office  the workstation this usually runs on; reboot it yourself
#   secu    needs its LUKS unlock USB inserted (nixos/modules/disko_secu.nix)
set -uo pipefail

HOSTS=(pite big closet nas arch)
DRY=0
YES=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --yes|-y)  YES=1 ;;
    --hosts=*) IFS=, read -r -a HOSTS <<<"${a#*=}" ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

# kured's own stay list, copied from its --drain-pod-selector argument.
SEL='!cnpg.io/cluster,longhorn.io/component!=instance-manager,app notin (home-assistant,minecraft,frigate,matter-server),app.kubernetes.io/name notin (za-mullvad,ee-mullvad,tempo),statefulset.kubernetes.io/pod-name notin (loki-write-0,loki-write-1,mimir-1,loki-chunks-cache-0,loki-results-cache-0)'

bold() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
say()  { printf '   %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '\nABORT: %s\n' "$*" >&2; exit 1; }

# admin kubectl lives on closet; a worker's kubeconfig cannot read cluster state
k() { ssh closet bash -s; }

cleanup() {
  warn "leaving $1 cordoned; fix the cause, then:"
  say "ssh closet 'kubectl uncordon $1'"
  [ "$1" = pite ] || say "ssh closet 'kubectl label node $1 node.kubernetes.io/exclude-from-external-load-balancers-'"
}
trap 'printf "\ninterrupted: check for a cordoned node (ssh closet kubectl get nodes) and uncordon it\n"; exit 130' INT TERM

# deadman's own rule, so "needs a reboot" here means what kured means by it
needs_reboot() {
  ssh "$1" bash -s <<'EOF' >/dev/null 2>&1
! [ /run/booted-system/kernel -ef /nix/var/nix/profiles/system/kernel ]
EOF
}

# Everything kured refuses to reboot without, plus the CNPG gate from
# docs/fleet-patching.md "Rebooting a k3s node". Batched: one ssh round trip per
# resource kind, because each is ~0.5s.
cluster_gate() {
  local nodes vols clusters cpods ob bad
  nodes=$(k <<'EOF'
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
EOF
)
  vols=$(k <<'EOF'
kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.metadata.name} {.status.robustness}{"\n"}{end}'
EOF
)
  clusters=$(k <<'EOF'
kubectl get clusters.postgresql.cnpg.io -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.instances} {.status.readyInstances}{"\n"}{end}'
EOF
)
  cpods=$(k <<'EOF'
kubectl get pods -A -l cnpg.io/cluster -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.labels.cnpg\.io/cluster}{"\n"}{end}'
EOF
)
  ob=$(k <<'EOF'
kubectl -n openbao get pods -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
EOF
)

  bad=""
  bad+=$(printf '%s\n' "$nodes"     | awk '$2!="True"{print "  node not Ready: "$1}')
  bad+=$(printf '%s\n' "$vols"      | awk '$2=="degraded"||$2=="faulted"{print "  longhorn volume "$1" is "$2}')
  # a hibernated or scaled-to-zero cluster has no pod: neither inspected nor an obstacle
  bad+=$(printf '%s\n' "$cpods" | awk 'NR==FNR{have[$1]; next} ($1 in have) && $2>0 && $3!=$2 {print "  cnpg "$1" has "$3" of "$2" instances ready"}' - <(printf '%s\n' "$clusters"))
  bad+=$(printf '%s\n' "$ob"        | awk '/^openbao-[0-9]/ && ($2!="Running" || $3!="True"){print "  openbao "$1" is "$2}')

  [ -z "$bad" ] || { printf '%s\n' "$bad"; return 1; }
}

node_ip() {
  k <<EOF
kubectl get node $1 -o jsonpath='{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/' | head -1
EOF
}

bgp_prefixes() {
  # the router terminates every value with \r\n, so match digits rather than split
  mikrotik-connect r "/routing bgp session print proplist=remote.address,prefix-count where remote.address=$1" 2>/dev/null |
    tr -d '\r' |
    awk 'match($0, /prefix-count=[0-9]+/) {print substr($0, RSTART+13, RLENGTH-13); exit}'
}

# CNPG moves a primary off a cordoned node by itself; fail the host if one of the
# replicated clusters refuses to. Single-instance clusters cannot move at all.
wait_primaries_off() {
  local node=$1 i left ref still replicated ns cl inst
  left=$(k <<EOF
kubectl get pods -A -l cnpg.io/instanceRole=primary --field-selector spec.nodeName=$node -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.labels.cnpg\.io/cluster}{"\n"}{end}'
EOF
)
  [ -z "$left" ] && return 0
  replicated=""
  while read -r ns cl; do
    [ -n "$ns" ] || continue
    inst=$(k <<EOF
kubectl get cluster.postgresql.cnpg.io $cl -n $ns -o jsonpath='{.spec.instances}'
EOF
)
    if [ "${inst:-0}" -lt 2 ]; then
      warn "$ns/$cl has one instance; it cannot fail over, expect a few seconds of downtime there"
    else
      replicated="$replicated $ns/$cl"
    fi
  done <<<"$left"
  [ -z "$replicated" ] && return 0

  for i in $(seq 1 20); do
    left=$(k <<EOF
kubectl get pods -A -l cnpg.io/instanceRole=primary --field-selector spec.nodeName=$node -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.labels.cnpg\.io/cluster}{"\n"}{end}'
EOF
)
    still=""
    for ref in $replicated; do
      printf '%s\n' "$left" | grep -qx "$ref" && still="$still $ref"
    done
    if [ -z "$still" ]; then say "CNPG moved its primaries off $node"; return 0; fi
    say "still primary on $node:$still"
    sleep 15
  done
  return 1
}

# Volumes with a single replica that lives on this node: they go offline while it
# reboots and come back when it returns. Reported, not blocked on.
single_replica_volumes() {
  local node=$1 vols reps
  vols=$(k <<'EOF'
kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.metadata.name} {.spec.numberOfReplicas}{"\n"}{end}'
EOF
)
  reps=$(k <<'EOF'
kubectl -n longhorn-system get replicas.longhorn.io -o jsonpath='{range .items[*]}{.spec.volumeName} {.spec.nodeID}{"\n"}{end}'
EOF
)
  awk -v n="$node" 'NR==FNR{one[$1]=$2; next} ($2==n && one[$1]==1){print $1}' <(printf '%s\n' "$vols") <(printf '%s\n' "$reps")
}

ready_wait() {
  local node=$1 i left
  for i in $(seq 1 90); do
    left=$(k <<EOF
kubectl get pods -A --field-selector spec.nodeName=$node -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.phase} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | awk '\$2!="Succeeded" && \$3!="True"'
EOF
)
    [ -z "$left" ] && return 0
    sleep 10
  done
  printf '%s\n' "$left" >&2
  return 1
}

# Wait for replica rebuilds: rebooting the next node while a two-replica volume is
# degraded would take it offline entirely.
wait_longhorn() {
  local i vols
  for i in $(seq 1 120); do
    vols=$(k <<'EOF'
kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.metadata.name} {.status.robustness}{"\n"}{end}' | awk '$2=="faulted"||$2=="degraded"'
EOF
)
    [ -z "$vols" ] && return 0
    printf '%s\n' "$vols" | grep -q faulted && { printf '%s\n' "$vols" >&2; return 2; }
    say "$(printf '%s\n' "$vols" | grep -c degraded) volumes still rebuilding"
    sleep 30
  done
  return 1
}

# ---- main ----------------------------------------------------------------
bold "hosts whose staged generation differs from the booted one"
todo=()
for h in "${HOSTS[@]}"; do
  if needs_reboot "$h"; then todo+=("$h"); say "$h needs a reboot"
  else say "$h is already on its staged kernel, skipping"; fi
done
[ ${#todo[@]} -gt 0 ] || { echo "nothing to do"; exit 0; }

bold "cluster gate"
if ! cluster_gate; then die "cluster is not in a reboot-safe state"; fi
say "nodes Ready, no degraded volumes, CNPG and openbao healthy"

for n in "${todo[@]}"; do
  bold "$n"
  if ! cluster_gate; then die "cluster gate failed before $n"; fi

  primaries=$(k <<EOF
kubectl get pods -A -l cnpg.io/instanceRole=primary --field-selector spec.nodeName=$n -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.labels.cnpg\.io/cluster}{"\n"}{end}'
EOF
)
  [ -z "$primaries" ] || say "primaries on $n: $(echo $primaries)"

  lastrepl=$(single_replica_volumes "$n")
  [ -z "$lastrepl" ] || warn "$(printf '%s\n' "$lastrepl" | grep -c .) single-replica volumes go offline while $n reboots: $(printf '%s\n' "$lastrepl" | head -3 | tr '\n' ' ')"

  if [ "$DRY" = 1 ]; then
    say "drain dry-run:"
    k <<EOF
kubectl drain $n --ignore-daemonsets --delete-emptydir-data --force --dry-run=client --pod-selector='$SEL' 2>&1 | grep -E '^evicting|drained' | tail -4
EOF
    continue
  fi

  if [ "$YES" != 1 ]; then
    go=0
    while :; do
      printf 'reboot %s now? [y/n] ' "$n"
      ans=""
      # read the terminal, not stdin: a stray buffered Enter must not answer for you
      if ! read -r ans </dev/tty 2>/dev/null; then say "no answer, skipping $n"; break; fi
      case $ans in
        y|Y) go=1; break ;;
        n|N) say "skipping $n"; break ;;
        *)   warn "answer y or n" ;;
      esac
    done
    [ "$go" = 1 ] || continue
  fi

  say "cordon"
  k <<EOF
kubectl cordon $n
EOF

  if [ "$n" != pite ]; then
    say "withdraw from the edge"
    k <<EOF
kubectl label node $n node.kubernetes.io/exclude-from-external-load-balancers=true --overwrite
EOF
    ip=$(node_ip "$n")
    pc=""
    lastpc=""
    for i in $(seq 1 30); do
      pc=$(bgp_prefixes "$ip")
      [ "${pc:-x}" = 0 ] && break
      [ "$pc" = "$lastpc" ] || say "router still announces ${pc:-?} prefixes for $ip"
      lastpc=$pc
      sleep 10
    done
    # MetalLB/FRR takes 30-60s to withdraw the last prefix, and a Local-policy
    # endpoint can hold one longer. The doc accepts that blip (node-maintenance
    # step 2), so warn and continue rather than wedging the node cordoned.
    if [ "${pc:-x}" != 0 ]; then
      warn "router still announces ${pc:-?} prefixes for $ip after 5 min; continuing — a service with externalTrafficPolicy: Local whose only ready pod is on $n is unreachable until it reschedules"
    fi
  fi

  say "waiting for CNPG primaries to move"
  wait_primaries_off "$n" || { cleanup "$n"; die "a replicated primary stayed on $n"; }

  say "drain"
  if ! k <<EOF
kubectl drain $n --ignore-daemonsets --delete-emptydir-data --force --pod-selector='$SEL' --timeout=30m
EOF
  then
    cleanup "$n"; die "drain of $n failed or timed out; nothing was rebooted"
  fi

  say "reboot"
  ssh "$n" 'sudo -n systemctl reboot' 2>/dev/null
  sleep 20
  st=""
  for i in $(seq 1 60); do
    st=$(k <<EOF
kubectl get node $n -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
EOF
)
    [ "$st" = True ] && break
    sleep 10
  done
  [ "${st:-}" = True ] || { cleanup "$n"; die "$n did not come back Ready"; }

  say "post-boot checks"
  ssh "$n" bash -s <<'EOF' || { cleanup "$n"; die "$n still reports a pending reboot, or deadman locked it"; }
[ /run/booted-system/kernel -ef /nix/var/nix/profiles/system/kernel ] || exit 1
[ ! -e /var/lib/deadman/locked ] || { cat /var/lib/deadman/locked; exit 1; }
echo "   $(uname -r), deadman reports no reboot needed and no lock"
EOF

  say "uncordon"
  k <<EOF
kubectl uncordon $n
EOF
  if [ "$n" != pite ]; then
    k <<EOF
kubectl label node $n node.kubernetes.io/exclude-from-external-load-balancers-
EOF
  fi

  say "waiting for pods on $n"
  ready_wait "$n" || warn "some pods on $n are not Ready yet"

  say "waiting for Longhorn"
  wait_longhorn || die "Longhorn did not settle after $n; stopping here"
done

bold "done"
if [ "$DRY" = 1 ]; then say "would reboot: ${todo[*]} (dry run, nothing changed)"
else say "rebooted: ${todo[*]}"; fi
say "office: reboot it yourself (sudo systemctl reboot)"
say "secu: needs the LUKS USB inserted before rebooting"
