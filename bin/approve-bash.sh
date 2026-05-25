#!/usr/bin/env bash
# PreToolUse hook for openclaude — hard-blocks dangerous bash commands.
# Intended as a safety net below the LLM classifier (--permission-mode auto).
# Reads tool-call JSON from stdin. Outputs a deny decision to block,
# or exits 0 silently to let the normal permission flow handle it.
#
# Blocked patterns are intentionally narrow — only commands that are
# irreversible or system-mutating. The LLM classifier handles everything else.

set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# ---- Hard-block patterns ----
# These commands are never safe for automated execution regardless of mode.

block_patterns=(
  # System mutation
  'nixos-rebuild\s+switch'
  'home-manager\s+switch'
  'nh\s+os\s+switch'
  # Destructive filesystem ops — block ANY rm -rf
  'rm\s+-rf\s+'
  'dd\s+if=.*of=/dev/(sd|nvme|hd)'
  'mkfs\.'
  # Force-push / destructive git
  'git\s+push\s+.*--force.*--no-verify'
  'git\s+push\s+.*--delete\s+origin'
  # Curl-to-shell
  'curl\s+.*\|\s*(ba)?sh'
  'wget\s+.*\|\s*(ba)?sh'
  # nix-collect-garbage
  'nix-collect-garbage\s+-d'
  # chmod 777 on system dirs
  'chmod\s+.*777\s+/(usr|etc|bin|lib|sbin|var|opt)'
  # fork bomb
  ':\s*\(\s*\)\s*\{'
)

for pattern in "${block_patterns[@]}"; do
  if echo "$command" | grep -qP "$pattern"; then
    reason="Destructive system command blocked by safety net: matches '${pattern}'"
    echo "$reason" >&2
    # Output deny decision — Claude Code hook convention.
    jq -n --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
  fi
done

# No decision — let the normal permission flow handle it.
exit 0
