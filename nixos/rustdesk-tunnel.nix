# `rd <arch|office>`: open an SSH tunnel to that host's RustDesk listener and
# start a RustDesk session through it. RustDesk is reachable only from the
# host's loopback (modules/remote-desktop.nix), so this tunnel is the gate.
# Shared by arch, office (via the module) and the MacBook (darwin-macbook.nix).
# Runbook: docs/remote-desktop.md.
{pkgs}: let
  # The only host keys rd accepts. Collected over the tailnet with ssh-keyscan
  # on 2026-11-24; arch's matches the LAN pin in modules/fleet-patching.nix.
  # A reinstalled host fails closed here: update its line, never disable the check.
  knownHosts = pkgs.writeText "rd-known-hosts" ''
    arch.ts.2143.me ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZx+UeGOlNlL08WTwYps1TkGZkedaEmUuZ3Iy4O5gK2
    office.ts.2143.me ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKf5HRPeKfVHALjx7Evp3T9Z7ik9sewpNqOAWOy8dS8
  '';
in
  pkgs.writeShellApplication {
    name = "rd";
    runtimeInputs = [pkgs.openssh pkgs.netcat];
    text = ''
      usage() {
        echo "usage: rd <arch|office> [--stop]" >&2
        echo "  rd <host>         open the SSH tunnel if needed and start a RustDesk session" >&2
        echo "  rd <host> --stop  close that host's tunnel" >&2
      }

      # MagicDNS names, not short ones: /etc/hosts maps "arch" to 127.0.0.2 on
      # arch itself. Ports are fixed per host so a password RustDesk remembers
      # for 127.0.0.1:<port> always belongs to the same machine.
      target="''${1-}"
      case $target in
        arch)   host=arch.ts.2143.me;   port=21201 ;;
        office) host=office.ts.2143.me; port=21203 ;;
        *)      usage; exit 2 ;;
      esac

      if [ "$(hostname -s)" = "$target" ]; then
        echo "rd: $target is this machine" >&2
        exit 2
      fi

      peer="127.0.0.1:$port"
      forward="$peer:127.0.0.1:21118"

      if [ "''${2-}" = "--stop" ]; then
        pkill -f -- "-L $forward" 2>/dev/null || true
        echo "tunnel to $target closed"
        exit 0
      fi

      # Detached and idempotent: the tunnel outlives the session, and the probe
      # keeps a second call from opening a second listener. -f returns only once
      # the forward exists (ExitOnForwardFailure), and set -e stops here if not.
      if ! nc -z -w 2 127.0.0.1 "$port" 2>/dev/null; then
        ssh -N -f -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 \
          -o ServerAliveCountMax=3 \
          -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${knownHosts} \
          -o GlobalKnownHostsFile=/dev/null \
          -L "$forward" -- "$host"
      fi

      # Hand the session to RustDesk: the running instance receives it over
      # D-Bus (Linux) or IPC (macOS); otherwise a new GUI opens it.
      launcher=""
      if command -v rustdesk >/dev/null 2>&1; then
        launcher=$(command -v rustdesk)
      elif [ -x /Applications/RustDesk.app/Contents/MacOS/RustDesk ]; then
        launcher=/Applications/RustDesk.app/Contents/MacOS/RustDesk
      fi

      if [ -n "$launcher" ]; then
        nohup "$launcher" --connect "$peer" >/dev/null 2>&1 &
        echo "rd: opening RustDesk session to $target ($peer)"
      else
        echo "rd: RustDesk not found; connect it to $peer"
      fi
    '';
  }
