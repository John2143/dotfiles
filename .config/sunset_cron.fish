#!/usr/bin/env fish

set DISPLAY ":0"

function sunrise
    cat -p ~/data/sunrise
end
function sunset
    cat -p ~/data/sunset
end
function now
    date "+%H:%M"
end
function shorten
    echo $argv | string shorten -m 4 -c ""
end

set rn (shorten (now))
set sr (shorten (sunrise))
set ss (shorten (sunset))

echo "sunrise, sunset"
echo "$sr, $ss"
echo "now"
echo "$rn"

if [ "$rn" = "$sr" ]
    redshift -x
    echo "is sunrise"
end

if [ "$rn" = "$ss" ]
    redshift -x && echo "yes"
    redshift -P -O 3500 && echo "asdf"
    echo "is sunset"
end
