#!/usr/bin/env fish

set S (bspc query -D -d focused --names)

set SP (string split " " $S | wc -l)
set MAINTHING (string split " " $S | head -n 1)
set MONO_STR " Z"

if test $SP = 2
    bspc desktop -l tiled
    bspc desktop -n (string replace "$MONO_STR" "" $S)
else
    bspc desktop -l monocle
    bspc desktop -n "$S$MONO_STR"
end

#WINDOW_NAME=$(xprop -id $(xprop -root _NET_ACTIVE_WINDOW | cut -d ' ' -f 5) WM_NAME | awk -F '"' '{print $2}')
