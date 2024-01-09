#!/bin/env fish

function getsinks
    pactl list short sinks | string split0
end

set sinks (getsinks)
set speakers (echo $sinks | grep analog | grep pci)
set headphones (echo $sinks | grep Schiit)
set bluetooth_headphones (echo $sinks | grep "bluez_output.AC_80_0A_37_DD_0C")

echo $speakers | not grep RUNNING > /dev/null
set s_active $status
echo $headphones | not grep RUNNING > /dev/null
set h_active $status
echo $bluetooth_headphones | not grep RUNNING > /dev/null
set bt_active $status

# get name of headphone
# string split "." (echo $headphones | choose 1) -f 2

#echo "S: $speakers"
#echo "H: $headphones"

set action $argv[1]

function setsinkloop
    echo "connect AC:80:0A:37:DD:0C" | bluetoothctl
    for i in (seq 15)
        set bluetooth_headphones (getsinks | grep "bluez_output.AC_80_0A_37_DD_0C")
        if test $bluetooth_headphones
            setsink $bluetooth_headphones
        end
        sleep .5
    end
end

function setsink
    echo $argv
    pactl set-default-sink (echo $argv[1] | choose 0) || true
    sleep .1
    polybar-msg action "#audio-output.hook.0"
end

switch $action
    case h headphones
        setsink $headphones 1
    case s speakers
        setsink $speakers 1
    case b bluetooth
        # connect to headphones
        setsinkloop
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
        else if test $bt_active -eq 1
            echo "BT NC ->"
        else
            echo "Unknown ->"
        end
    case '*'
        echo "S: $s_active $speakers"
        echo "H: $h_active $headphones"
        echo "B: $bt_active $bluetooth_headphones"
end
