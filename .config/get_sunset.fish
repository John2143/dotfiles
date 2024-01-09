#!/bin/bash

# First obtain a location code from: https://weather.codes/search/

# Insert your location. For example LOXX0001 is a location code for Bratislava, Slovakia
location="USMD0602"
tmpfile=/tmp/$location.out

get_weather() {
    wget -q "https://weather.com/weather/today/l/$location" -O "$tmpfile"
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

SUNR=$(grep SunriseSunset "$tmpfile" | grep -oE '((1[0-2]|0?[1-9]):([0-5][0-9]) ?([AaPp][Mm]))' | head -1)
SUNS=$(grep SunriseSunset "$tmpfile" | grep -oE '((1[0-2]|0?[1-9]):([0-5][0-9]) ?([AaPp][Mm]))' | tail -1)


sunrise=$(date --date="$SUNR" +%R)
sunset=$(date --date="$SUNS" +%R)

# Use $sunrise and $sunset variables to fit your needs. Example:
echo -n $sunrise > $HOME/data/sunrise
echo -n $sunset > $HOME/data/sunset
