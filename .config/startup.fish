#!/usr/bin/env fish

set HOST (cat /etc/hostname)

sleep 0.1
tmux new-window 'bpytop'
tmux rename-window 'bpytop'

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

    sleep 0.1
    tmux new-window 'while true; steam; read; end'
    tmux rename-window 'steam'

    sleep 0.1
    tmux new-window 'while true; obsidian; read; end'
    tmux rename-window 'obsidian'

    sleep 0.1
    tmux new-window 'discord'
    tmux rename-window 'discord'
end

if test "$HOST" = "office"
    sleep 0.1
    tmux new-window 'amdgpu_top'
    tmux rename-window 'gpu top'

    sleep 0.1
    tmux new-window 'qpwgraph'
    tmux rename-window 'qpwgraph'
end

tmux rename-session monitor
