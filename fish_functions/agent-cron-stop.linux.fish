# DESCRIPTION: Stop an agent-created timer (and its service). Name must start with 'agent-'.
if test (count $argv) -lt 1
  echo "Usage: agent-cron-stop <unit-name>" >&2
  echo "  e.g. agent-cron-stop agent-check-pr-42" >&2
  return 1
end
set -l unit $argv[1]
if not string match -q "agent-*" $unit
  echo "Error: unit name must start with 'agent-'" >&2
  return 1
end
systemctl --user stop "$unit.timer" "$unit.service" 2>&1
systemctl --user reset-failed "$unit.service" 2>/dev/null
