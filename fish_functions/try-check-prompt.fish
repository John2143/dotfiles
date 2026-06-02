# DESCRIPTION: Verify the approval hook works — triggers the approve/deny confirm dialog
# Run omp with the approval hook and a safe prompt that exercises the
# approve/deny confirm dialog. The prompt instructs the model to run a command
# containing "rm -rf" (echo'd, not executed). Since the hook checks the
# command string for risky patterns, `echo rm -rf <dir>` triggers the
# confirm prompt even though the actual command is harmless.
#
# If the hook is working:
#   - The confirm dialog appears: "Approve tool call?"
#   - Approving runs: echo rm -rf /tmp/omp-hook-test
#   - Denying throws and the tool call is blocked.
#
# If NO dialog appears, the hook may not be wired correctly.
omp --hook=$HOME/.omp/agent/hooks/approve.ts $argv "Run: echo rm -rf /tmp/omp-hook-test  # verify the approval hook"
