# DESCRIPTION: Stop the autoclicker daemon and refresh waybar
set -f pid_file /tmp/autoclicker.pid
if test -f "$pid_file"
  set -l pid (cat "$pid_file")
  if kill -0 "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
  end
  rm -f "$pid_file"
end
rm -f /tmp/autoclicker.sock
pkill -RTMIN+15 waybar 2>/dev/null
