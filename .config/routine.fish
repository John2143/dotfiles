#!/usr/bin/env fish
set -x DISPLAY ":0"
set -x DBUS_SESSION_BUS_ADDRESS "unix:path=/run/user/1000/bus"

#fish -c "~/.config/polybar/scripts/sinks.fish s" &
#sleep 1;
playerctl play-pause -p spotify &
killall i3lock &
