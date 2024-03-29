#!/bin/bash

# The name of polybar bar which houses the main spotify module and the control modules.
PARENT_BAR="1"
PARENT_BAR_PID=$(pgrep -a "polybar" | grep "$PARENT_BAR" | cut -d" " -f1)

# Set the source audio player here.
# Players supporting the MPRIS spec are supported.
# Examples: spotify, vlc, chrome, mpv and others.
# Use `playerctld` to always detect the latest player.
# See more here: https://github.com/altdesktop/playerctl/#selecting-players-to-control

hostname_path="/etc/hostname"
pc_name="downstairs"

if [ -f "$hostname_path" ] && [ -r "$hostname_path" ] && [ "$(cat "$hostname_path")" = "$pc_name" ]; then
    PLAYER="spotifyd"
else
    PLAYER="spotify"
fi

# Sends $2 as message to all polybar PIDs that are part of $1
update_hooks() {
  return #TODO: This was cuasing errors, all it does is update if it is paused
  while IFS= read -r id; do
    polybar-msg -p "$id" hook spotify-play-pause $2 1>/dev/null 2>&1
  done < <(echo "$1")
}

PLAYERCTL_STATUS=$(playerctl --player=$PLAYER status 2>/dev/null)

if [ $? -eq 0 ]; then
  STATUS=$PLAYERCTL_STATUS
else
  STATUS="[No Player]"
fi

# Format of the information displayed
# Eg. {{ artist }} - {{ album }} - {{ title }}
# See more attributes here: https://github.com/altdesktop/playerctl/#printing-properties-and-metadata
FORMAT="{{ title }} :: {{ artist }}"
if [ "$1" == "--status" ]; then
  echo "$STATUS"
else
  if [ "$STATUS" = "Stopped" ]; then
    echo "[No Music]"
  elif [ "$STATUS" = "Paused" ]; then
    update_hooks "$PARENT_BAR_PID" 2
    playerctl --player=$PLAYER metadata --format "$FORMAT"
  elif [ "$STATUS" = "[No Player]" ]; then
    echo "$STATUS"
  else
    update_hooks "$PARENT_BAR_PID" 1
    playerctl --player=$PLAYER metadata --format "$FORMAT"
  fi
fi
