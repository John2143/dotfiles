#!/usr/bin/env fish

set HOST (cat /etc/hostname)

sleep 0.1
tmux new-window 'steam'
tmux rename-window 'steam'

sleep 0.1
tmux new-window 'obsidian'
tmux rename-window 'obsidian'

if test "$HOST" = "arch"
    sleep 0.1
    tmux new-window 'teamspeak3'
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

sleep 0.1
tmux new-window 'discord'
tmux rename-window 'discord'

tmux rename-session monitor
