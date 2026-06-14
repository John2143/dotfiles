# DESCRIPTION: SSH to MikroTik devices using age-encrypted ed25519 key
set -l keyfile /run/user/(id -u)/mikrotik-key
if not test -f $keyfile
  if not test -f /run/agenix/mikrotik-credentials
    echo "mikrotik-credentials not found — run: nh os switch ." >&2
    return 1
  end
  set -l _pre_vars (set --names -x)
  envsource /run/agenix/mikrotik-credentials >/dev/null
  if not set -q MIKROTIK_SSH_PRIVATE_KEY_B64
    echo "MIKROTIK_SSH_PRIVATE_KEY_B64 not set in credentials" >&2
    env-cleanup $_pre_vars
    return 1
  end
  echo "$MIKROTIK_SSH_PRIVATE_KEY_B64" | base64 -d > $keyfile
  chmod 600 $keyfile
  env-cleanup $_pre_vars
end
switch "$argv[1]"
  case router r
    ssh -i $keyfile -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR admin@192.168.1.1 $argv[2..-1]
  case core c
    ssh -i $keyfile -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR admin@192.168.5.4 $argv[2..-1]
  case upstairs up u
    ssh -i $keyfile -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR admin@192.168.5.3 $argv[2..-1]
  case upstairs-core uc
    ssh -i $keyfile -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR admin@192.168.5.5 $argv[2..-1]
  case office o
    ssh -i $keyfile -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR admin@192.168.5.2 $argv[2..-1]
  case '-h' '--help'
    echo "Usage: mikrotik-connect <router|core|upstairs|office|upstairs-core> [ssh-args...]" >&2
    echo "  r/c/u/o/uc also accepted as shortcuts" >&2
  case '*'
    echo "Unknown device: $argv[1]" >&2
    echo "Usage: mikrotik-connect <router|core|upstairs|office|upstairs-core> [ssh-args...]" >&2
    echo "  r/c/u/o/uc also accepted as shortcuts" >&2
    return 1
end
