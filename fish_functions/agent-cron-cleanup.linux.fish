# DESCRIPTION: Stop and clean up all agent-created timers and services
set -l units (systemctl --user list-units --all --no-pager --plain 2>/dev/null | \
  awk '/agent-.*\.(timer|service)/ {print $1}')
if test -z "$units"
  echo "No agent timers to clean up."
  return 0
end
echo "Stopping: $units"
systemctl --user stop $units
for u in $units
  systemctl --user reset-failed "$u" 2>/dev/null
end
echo "Done."
