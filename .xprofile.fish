#!/usr/bin/env fish
set HOST (cat /etc/hostname)

# This file is executed on every reload of the x/wayland server.
# Every command should be repeatable.
if test "$HOST" = "office"
    # TODO setup monitors
    #set left_mon "DP-1"
    #set right_mon "DP-2"
    #xrandr --output $left_mon --mode 2560x1440 --rate 239.97 --primary
    #xrandr --output $right_mon --mode 1920x1080 --rate 144.00 --right-of $left_mon
end
if test "$HOST" = "downstairs"
    # WAN
    #sudo ip link set dev enp6s0 up
    #sudo ip addr add 192.168.1.9/24 dev enp6s0
    #sudo ip ro add 192.168.1.0/24 dev enp6s0
    #sudo ip ro add 0.0.0.0/0 via 192.168.1.1

    # WIFI
    #sudo ip link set dev wlp2s0f0u3 up
    #sudo ip addr add 192.168.1.9/24 dev wlp2s0f0u3
    #sudo ip ro add 192.168.1.0/24 dev wlp2s0f0u3
    #sudo ip ro add 0.0.0.0/0 via 192.168.1.1
end

notify-send "Desktop ready"
