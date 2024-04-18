#!/usr/bin/env fish

set HOST (cat /etc/hostname)

sleep 0.1
tmux new-window 'while true; steam; read; end'
tmux rename-window 'steam'

sleep 0.1
tmux new-window 'while true; obsidian; read; end'
tmux rename-window 'obsidian'

set color_temp_day 6500
set color_temp_night 3000
set brightness_day 1.0
set brightness_night 0.5
set loc "38.897916:-77.035476"
if test "$HOST" = "arch"
    sleep 0.1
    tmux new-window 'while true; teamspeak3; read; end'
    tmux rename-window 'teamspeak3'

    sleep 0.1
    tmux new-window '/usr/bin/monerod --block-sync-size 100 --data-dir /mnt/other/monero/ --max-concurrency 4 --db-sync-mode=safe:sync'
    tmux rename-window 'monero'

    sleep 0.1
    tmux new-window 'sudo openrgb'
    tmux rename-window 'openrgb'

    sleep 0.1
    tmux new-window 'sudo input-remapper-gtk'
    tmux rename-window 'inputs'

    sleep 0.1
    tmux new-window 'spotify-launcher'
    tmux rename-window 'spotify'
end

if test "$HOST" = "office"
    sleep 0.1
    tmux new-window 'while true; spotifyd -p $SPOTIFY_PASSWORD -u $SPOTIFY_USERNAME --device-name office --device-type computer --bitrate 320 --backend pulseaudio; end'
    tmux rename-window 'spotify'

    sleep 0.1
    tmux new-window "while true; gammastep -l $loc -b $brightness_day:$brightness_night -t $color_temp_day:$color_temp_night; end"
    tmux rename-window 'gammastep'
end

sleep 0.1
tmux new-window 'discord'
tmux rename-window 'discord'

tmux rename-session monitor
