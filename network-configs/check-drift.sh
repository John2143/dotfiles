#!/usr/bin/env bash
# Alert-only drift check for the committed RouterOS exports.
#
# Compares a live router export against the committed network-configs/router.rsc
# and shouts if they differ. It deliberately NEVER overwrites or commits the
# baseline: an unexpected live configuration should be looked at by a human,
# and the baseline should only move when someone deliberately refreshes it with
# the exports documented in README.md.
#
# The first line of every export is a timestamp that changes on each run, so it
# is stripped before comparing.
#
# Usage:      ./check-drift.sh            # check, notify on drift, exit 1 on drift
#             ./check-drift.sh --quiet    # only print and exit; no ntfy
#
# Suggested timer (monthly, user scope, survives until reboot):
#   systemd-run --user --on-calendar=monthly --unit=agent-router-drift \
#     /home/john/repos/dotfiles/network-configs/check-drift.sh
# For a durable schedule put the same command in the NixOS configuration as a
# systemd.timers entry instead; nothing here depends on a timer existing.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
baseline="$here/router.rsc"
live="$(mktemp /tmp/router-drift-XXXXXX.rsc)"
trap 'rm -f "$live"' EXIT

quiet=0
[[ "${1:-}" == "--quiet" ]] && quiet=1

notify() {
    local body="$1"
    [[ $quiet -eq 1 ]] && return 0
    local url
    url="$(cat /run/agenix/ntfy-topic-url 2>/dev/null || echo 'https://ntfy.sh/2143-site-outages')"
    curl -sS -m 15 -H "Priority: default" -H "Tags: mikrotik,warning" \
        -H "Title: RouterOS config drift" -d "$body" "$url" >/dev/null 2>&1 \
        || echo "WARN: notification delivery failed" >&2
}

if ! command -v mikrotik-connect >/dev/null 2>&1; then
    echo "ERROR: mikrotik-connect not found on PATH" >&2
    exit 2
fi

if [[ ! -r "$baseline" ]]; then
    echo "ERROR: baseline not readable: $baseline" >&2
    exit 2
fi

if ! mikrotik-connect r '/export' > "$live" 2>/dev/null; then
    echo "ERROR: router export failed; not comparing" >&2
    exit 2
fi

if [[ ! -s "$live" ]] || ! grep -q 'RouterOS' "$live"; then
    echo "ERROR: router export looks empty or malformed; not comparing" >&2
    exit 2
fi

# Compare everything except the export timestamp on line 1. Line endings are
# normalised first: mikrotik-connect allocates a pty, so RouterOS returns CRLF
# on this path while the committed baseline (exported without a pty) is LF.
# Without the tr, every line differs and the check cries wolf on a clean router.
diff_out="$(diff <(tail -n +2 "$baseline" | tr -d '\r') <(tail -n +2 "$live" | tr -d '\r'))"
if [[ -z "$diff_out" ]]; then
    echo "OK: no drift between $baseline and the live router config"
    exit 0
fi

echo "DRIFT DETECTED: live router config differs from $baseline"
echo "$diff_out"
notify "DRIFT DETECTED between the committed router.rsc and the live config. Review the diff before refreshing the baseline; nothing was changed or committed. First lines: $(echo "$diff_out" | head -5 | tr '\n' ' ' | cut -c1-300)"
exit 1
