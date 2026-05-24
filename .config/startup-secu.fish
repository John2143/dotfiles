#!/usr/bin/env fish
# secu 24/7 startup — runs after Hyprland compositor is ready.
# Pulls 6 RTSP per-channel substreams from the Reolink NVR,
# tiled borderless by Hyprland dwindle layout (gaps=0).

# Source camera credentials (decrypted by agenix at boot)
set -l cred_file /run/agenix/camera-credentials
if test -f "$cred_file"
    for line in (cat "$cred_file")
        set -l key (echo "$line" | cut -d= -f1)
        set -l val (echo "$line" | cut -d= -f2-)
        test -n "$key"; and set -gx "$key" "$val"
    end
end
set -l CAM_USER "${CAMERA_USER:-admin}"
set -l CAM_PW "${CAMERA_PASSWORD:-}"

# NVR per-channel RTSP substreams (Preview_All not supported on this firmware).
# Channel numbers 1-6, pulled from NVR at 192.168.1.67.
set -l NVR "192.168.1.67"
set -l channels 1 2 3 4 5 6

# ── Disable screen blanking / DPMS for 24/7 operation ──────────────
hyprctl dispatch dpms on
echo 0 > /sys/module/kernel/parameters/consoleblank 2>/dev/null || true

sleep 2

# ── Set up window rules for camera tiles (borderless, no rounding) ──
hyprctl keyword windowrulev2 "noborder,title:^cam-.*$" 2>/dev/null || true
hyprctl keyword windowrulev2 "norounding,title:^cam-.*$" 2>/dev/null || true

# ── Launch camera grid on workspace A2 ─────────────────────────────
# Hyprland tiles them automatically (dwindle, gaps=0).
set -l cam_workspace "name:A2"
for ch in $channels
    set -l ch_padded (printf "%02d" $ch)
    set -l title "cam-CH$ch_padded"
    set -l rtsp "rtsp://$CAM_USER:$CAM_PW@$NVR/h264Preview_$ch_padded\_sub"

    hyprctl dispatch exec "[workspace $cam_workspace silent] mpv \
        --title=$title \
        --no-border \
        --no-osc \
        --no-input-default-bindings \
        --input-conf=/dev/null \
        --really-quiet \
        --loop-file=inf \
        --cache=yes \
        --cache-secs=2 \
        --demuxer-max-bytes=4M \
        --demuxer-readahead-secs=2 \
        --profile=low-latency \
        --untimed \
        --no-correct-pts \
        $rtsp"

    sleep 0.5
end

# ── Focus camera grid ──────────────────────────────────────────────
sleep 2
hyprctl dispatch workspace name:A2
