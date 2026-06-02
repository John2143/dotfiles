# DESCRIPTION: List agent-created transient timers and their next trigger time
systemctl --user list-timers --all --no-pager 2>/dev/null | \
  awk 'NR==1 || /agent-/ || /NEXT/' | \
  awk 'BEGIN { count=0 } /agent-/ { count++ } { print } END { if (count==0) print "(no agent timers)" }'
