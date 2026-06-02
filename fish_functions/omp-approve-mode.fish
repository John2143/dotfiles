# DESCRIPTION: Switch OMP approval mode (normal|edits|auto) for current repo
# Switch the approval mode for the current repo. Writes to .claude/settings.local.json.
# Mode is stored as permissions.defaultMode following Claude Code settings schema.
# Usage: omp-approve-mode normal|edits|auto
# Normal:  prompt for each unlisted bash command
# Edits:   auto-allow in-repo edits, prompt for bash
# Auto:    LLM classifier verifies before running
set -l mode $argv[1]
if test "$mode" != "normal" -a "$mode" != "edits" -a "$mode" != "auto"
  echo "Usage: omp-approve-mode normal|edits|auto" >&2
  return 1
end
set -l dmode default
if test "$mode" = "edits"
  set dmode acceptEdits
else if test "$mode" = "auto"
  set dmode auto
end
set -l file .claude/settings.local.json
if test -f $file
  set -l tmp (mktemp)
  jq --arg m "$dmode" '.permissions.defaultMode = $m' $file > $tmp && mv $tmp $file
else
  mkdir -p .claude
  echo '{"permissions":{"allow":[],"deny":[],"defaultMode":"'$dmode'"}}' | jq . > $file
end
echo "Approval mode: $mode (stored in $file)" >&2
