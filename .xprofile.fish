#!/usr/bin/env fish
set HOST (cat /etc/hostname)

# This file is executed on every reload of the x/wayland server.
# Every command should be repeatable.
set color_temp_day 6500
set color_temp_night 3000
set brightness_day 1.0
set brightness_night 0.75
set loc "38.897916:-77.035476"

if test "$HOST" = "arch"
    set left_mon "DP-4"
    set right_mon "HDMI-1"

    # TODO setup monitors
    #xrandr --output $left_mon --mode 2560x1440 --rate 239.97 --primary
    #xrandr --output $right_mon --mode 1920x1080 --rate 144.00 --right-of $left_mon
    killall spotifyd || true
    spotifyd -p $SPOTIFY_PASSWORD -u $SPOTIFY_USERNAME --device-name office --device-type computer --bitrate 320 --backend pulseaudio &

    killall gammastep || true
    gammastep -l $loc -b $brightness_day:$brightness_night -t $color_temp_day:$color_temp_night &
end

if test "$HOST" = "office"
    # TODO setup monitors
    #set left_mon "DP-1"
    #set right_mon "DP-2"
    #xrandr --output $left_mon --mode 2560x1440 --rate 239.97 --primary
    #xrandr --output $right_mon --mode 1920x1080 --rate 144.00 --right-of $left_mon
    killall spotifyd || true
    spotifyd -p $SPOTIFY_PASSWORD -u $SPOTIFY_USERNAME --device-name office --device-type computer --bitrate 320 --backend pulseaudio &

    killall gammastep || true
    gammastep -l $loc -b $brightness_day:$brightness_night -t $color_temp_day:$color_temp_night &

    echo 0 | sudo tee /sys/devices/system/cpu/cpu8/online
    echo 0 | sudo tee /sys/devices/system/cpu/cpu9/online
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
