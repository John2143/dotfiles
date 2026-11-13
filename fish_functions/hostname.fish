# DESCRIPTION: Show the system hostname
if test -f /etc/hostname
    /usr/bin/env cat /etc/hostname
else
    command hostname $argv
end
