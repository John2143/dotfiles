#!/usr/bin/env fish
set HOST (cat /etc/hostname)

# This file is executed on every reload of the x/wayland server.
# Every command should be repeatable.
set color_temp_day 6500
set color_temp_night 3500
set brightness_day 1.0
set brightness_night 0.75
set loc "38.897916:-77.035476"

# Set up monitorss
if test "$HOST" = "downstairs"
    set left_mon "DP-1"
    set right_mon "DP-2"
    xrandr --output $left_mon --mode 2560x1440 --rate 239.97 --primary
    xrandr --output $right_mon --mode 1920x1080 --rate 144.00 --right-of $left_mon

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

if test "$HOST" = "arch"
    set left_mon "DP-0"
    set right_mon "HDMI-1"

    xrandr --output $left_mon --mode 2560x1440 --rate 239.97 --primary
    xrandr --output $right_mon --mode 2560x1440 --rate 144.0 --right-of $left_mon

    # TODO also select the right device by default
    echo "power on" > bluetoothctl
    sleep .1

    setxkbmap -option "ctrl:nocaps"
    dbus-update-activation-environment --systemd DBUS_SESSION_BUS_ADDRESS DISPLAY XAUTHORITY
    kdeconnect-cli --refresh
    killall polybar

    # killall swhks || true
    # sudo killall xwhkd || true
    # swhks &

    killall sxhkd || true
    sxhkd &

    # sudo pkexec fish -c "set -x XDG_CONFIG_HOME '$XDG_CONFIG_HOME'; set -x XDG_RUNTIME_DIR '$XDG_RUNTIME_DIR'; "(which swhkd)

    bspc config border_width         0
    bspc config window_gap           1
    bspc config focused_border_color \#ffffff
    bspc config normal_border_color  \#1d2021

    bspc config split_ratio          0.52
    bspc config borderless_monocle   false
    bspc config gapless_monocle      false

    #bspc rule -a firefoxdeveloperedition desktop='^1'
    # https://github.com/baskerville/bspwm/issues/291
    # only works due to https://github.com/dasJ/spotifywm
    #bspc rule -a Spotify desktop='^6' state=pseudo_tiled
    #bspc rule -a ulauncher focus=on
    #bspc rule -a sxiv state=floating center=true
    bspc rule -a polybar border=off manage=off
    bspc rule -a steam floating=on follow=no desktop='steam'
    bspc rule -a steamwebhelper floating=on follow=no desktop='steam'
    bspc rule -a Spotify desktop='spotify'
    bspc rule -a discord desktop='disc'
    bspc rule -a obsidian desktop='obsidian'
    bspc rule -a "TeamSpeak 3" desktop='ts'

    xset dpms 6000 6000 12000

    fish -c "polybar -r 1 &"
    fish -c "polybar -r 2 &"

    bspc monitor $left_mon -d A1 A2 A3 A4 A5 A6 A7 A8 A9
    bspc monitor $right_mon -d B1 B2 B3 B4 B5 B6 B7 ts spotify disc steam obsidian

    sudo systemctl restart dnscrypt-proxy
    #sudo modprobe i2c-dev
    #sudo modprobe i2c-i801

    killall redshift || true
    fish -c "sleep 5 ; redshift -l $loc -b $brightness_day:$brightness_night -t $color_temp_day:$color_temp_night &"
end

if test "$HOST" = "office"
    killall spotifyd || true
    spotifyd -p $SPOTIFY_PASSWORD -u $SPOTIFY_USERNAME --device-name office --device-type computer --bitrate 320 --backend pulseaudio &

    killall gammastep || true
    gammastep -l $loc -b $brightness_day:$brightness_night -t $color_temp_day:$color_temp_night &
end

notify-send "Desktop ready"
