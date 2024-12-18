#!/usr/bin/env fish

set HOST (cat /etc/hostname)

sleep 0.1
tmux new-window 'btop'
tmux rename-window 'btop'

sleep 0.1
tmux new-window 'while true; steam; read; end'
tmux rename-window 'steam'

sleep 0.1
tmux new-window 'while true; obsidian; read; end'
tmux rename-window 'obsidian'

sleep 0.1
tmux new-window 'vesktop'
tmux rename-window 'discord'

if test "$HOST" = "arch"
    #sleep 0.1
    #tmux new-window 'while true; ts3client; read; end'
    #tmux rename-window 'ts3client'

    sleep 0.1
    tmux new-window 'monerod --block-sync-size 100 --data-dir /mnt/other/monero/ --max-concurrency 4 --db-sync-mode=safe:sync'
    tmux rename-window 'monero'

    #sleep 0.1
    #tmux new-window 'sudo openrgb'
    #tmux rename-window 'openrgb'

    #sleep 0.1
    #tmux new-window 'sudo input-remapper-gtk'
    #tmux rename-window 'inputs'

    #sleep 0.1
    #tmux new-window 'spotify-launcher'
    #tmux rename-window 'spotify'
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
