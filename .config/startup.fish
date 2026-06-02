#!/usr/bin/env fish


set HOST (cat /etc/hostname)


if tmux has-session -t monitor 2>/dev/null
    exit
end

sleep 0.1
tmux new-window 'btop'
tmux rename-window 'btop'

sleep 0.1
tmux new-window 'while true; steam; end'
tmux rename-window 'steam'

sleep 0.1
tmux new-window 'flatpak run md.obsidian.Obsidian'
tmux rename-window 'obsidian'

sleep 0.1
tmux new-window 'flatpak run dev.vencord.Vesktop'
tmux rename-window 'discord'

sleep 0.1
tmux new-window 'flatpak run com.spotify.Client'
tmux rename-window 'spotify'

if test "$HOST" = "arch"
    sleep 0.1
    tmux new-window 'monerod --block-sync-size 100 --data-dir /mnt/monero/monero/ --max-concurrency 4 --db-sync-mode=safe:sync'
    tmux rename-window 'monero'
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
