#!/usr/bin/env fish

mullvad help > /dev/null

if test $status = 127
    echo "-"
    exit 0
end

set mvstatus (mullvad status -j | string collect)

set connection_status (echo $mvstatus | jq -r '.state')

if test $connection_status = "connected"
    set city (echo $mvstatus | jq -r '.details.location.city')
    set country (echo $mvstatus | jq -r '.details.location.country')
    set output_text "vpn $city, $country"
else
    set output_text "no vpn"
end

echo $output_text
