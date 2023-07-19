#!/bin/env fish

set sinks (pactl list short sinks | string split0)

set speakers (echo $sinks | grep analog | grep pci)
set headphones (echo $sinks | grep Schiit)

echo $speakers | not grep RUNNING > /dev/null
set s_active $status
echo $headphones | not grep RUNNING > /dev/null
set h_active $status

# get name of headphone
# string split "." (echo $headphones | choose 1) -f 2

#echo "S: $speakers"
#echo "H: $headphones"

set action $argv[1]

function setsink
    pactl set-default-sink (echo $argv[1] | choose 0)
    sleep 0.1
    polybar-msg action "#audio-output.hook.0"
end

switch $action
    case h headphones
        setsink $headphones
    case s speakers
        setsink $speakers
    case t toggle
        if test $h_active -eq 1
            setsink $speakers
        else
            setsink $headphones
        end
    case p print
        if test $h_active -eq 1
            echo "Headphones ->"
        else if test $s_active -eq 1
            echo "Speakers ->"
        else
            echo "Unknown ->"
        end
    case '*'
        echo "S: $s_active $speakers"
        echo "H: $h_active $headphones"
end
