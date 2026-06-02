# DESCRIPTION: Run omp with all hooks from ~/.omp/agent/hooks/
# Run omp with all hooks from ~/.omp/agent/hooks/ loaded. Default `omp`
# runs auto; `omp-safe` prompts before risky bash, force-pushes, etc.
# See `~/.omp/agent/hooks/approve.ts` for the approval rule list.
# Verify with: `try-check-prompt`
set -l hook_args
for hook in $HOME/.omp/agent/hooks/*.ts
  set -a hook_args --hook=$hook
end
omp $hook_args $argv
