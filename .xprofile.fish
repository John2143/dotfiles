#!/usr/bin/env fish
set HOST (cat /etc/hostname)

if test "$HOST" = "downstairs"
    xrandr --output HDMI-A-0 --mode 1920x1080 --rate 60 --primary
    sudo ip link set dev enp6s0 up
    sudo ip addr add 192.168.1.9/24 dev enp6s0
    sudo ip ro add 192.168.1.1 dev enp6s0
    sudo ip ro add 0.0.0.0/0 via 192.168.1.1

    killall spotifyd || true
    spotifyd -p $SPOTIFY_PASSWORD -u $SPOTIFY_USERNAME --device-name downstairs --device-type computer --bitrate 320 --backend pulseaudio &
else # arch
    xrandr --output DP-4 --mode 2560x1440 --rate 144.0 --primary
    xrandr --output DP-0 --mode 2560x1440 --rate 144.0 --right-of DP-4
    xrandr --output DP-2 --off
end

setxkbmap -option "ctrl:nocaps"
dbus-update-activation-environment --systemd DBUS_SESSION_BUS_ADDRESS DISPLAY XAUTHORITY
kdeconnect-cli --refresh

killall polybar
killall sxhkd

sleep .1

if test "$HOST" = "downstairs"
    polybar -r 3 &
else # arch
    polybar -r 1 &
    polybar -r 2 &
end

sxhkd &
#killall nitrogen
#nitrogen --restore &

xset dpms 6000 6000 12000

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

if test "$HOST" = "downstairs"
    bspc monitor HDMI-A-0 -d A1 A2 A3 A4 A5 B1 B2 B3 B4 ts spotify disc steam obsidian
else
    bspc monitor DP-4 -d A1 A2 A3 A4 A5 A6 A7 A8 A9
    bspc monitor DP-0 -d B1 B2 B3 B4 B5 B6 B7 ts spotify disc steam obsidian
end

sleep 1

if test "$HOST" = "arch"
    sudo systemctl restart dnscrypt-proxy
    sudo modprobe i2c-dev
    sudo modprobe i2c-i801
end

notify-send "Desktop ready"

