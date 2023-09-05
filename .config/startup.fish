#!/usr/bin/env fish
if test -e /tmp/startedup
    return
else
    touch /tmp/startedup
end

sleep 5

tmux new-session

tmux new-window '/usr/bin/monerod --block-sync-size 100 --data-dir /mnt/other/monero/ --max-concurrency 4 --db-sync-mode=safe:sync'
tmux split -h 'sudo openrgb'
tmux split 'sudo input-remapper-gtk'

tmux new-window 'steam'
tmux split -h 'spotify-launcher'
tmux split -h 'obisidan'

tmux new-window 'ts3'
tmux split -h 'discord'

tmux rename-session monitor
