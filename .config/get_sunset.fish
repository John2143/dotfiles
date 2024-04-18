#!/bin/bash

# First obtain a location code from: https://weather.codes/search/

# Insert your location. For example LOXX0001 is a location code for Bratislava, Slovakia
tmpfile=/tmp/sunrise.json

get_weather() {
    wget -q "https://api.sunrise-sunset.org/json?lat=38&lng=-77&tzid=America/New_York" -O "$tmpfile"
}


if [ -e "$tmpfile" ]; then
    age=$(($(date +%s) - $(date +%s -r "$tmpfile")))
    if [[ $age -gt $((3600 * 12)) ]]; then
        get_weather;
    fi
else
    get_weather;
fi

# Obtain sunrise and sunset raw data from weather.com

SUNR=$(jq -r .results.sunrise $tmpfile)
SUNS=$(jq -r .results.sunset $tmpfile)

sunrise=$(date --date="$SUNR" +%R%P)
sunset=$(date --date="$SUNS" +%R%P)

# Use $sunrise and $sunset variables to fit your needs. Example:
echo -n $sunrise > $HOME/data/sunrise
echo -n $sunset > $HOME/data/sunset
