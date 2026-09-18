# 2026-09-17 23:23:03 by RouterOS 7.19.6
# software id = UL5S-M34T
#
# model = CRS310-8G+2S+
# serial number = HKG0AJ14YM5
/interface bridge
add admin-mac=04:F4:1C:E7:24:3C auto-mac=no comment=defconf name=bridge
/interface bridge port
add bridge=bridge comment=defconf interface=ether1
add bridge=bridge comment=defconf interface=ether2
add bridge=bridge comment=defconf interface=ether3
add bridge=bridge comment=defconf interface=ether4
add bridge=bridge comment=defconf interface=ether5
add bridge=bridge comment=defconf interface=ether6
add bridge=bridge comment=defconf interface=ether7
add bridge=bridge comment=defconf interface=ether8
add bridge=bridge comment=defconf interface=sfp-sfpplus1
add bridge=bridge comment=defconf interface=sfp-sfpplus2
/ip address
add address=192.168.5.2/24 comment=defconf interface=bridge network=\
    192.168.5.0
/ip dns
set allow-remote-requests=yes servers=1.1.1.1
/ip hotspot profile
set [ find default=yes ] html-directory=hotspot
/ip route
add comment="NTP Google" dst-address=216.239.35.12/32 gateway=192.168.5.1
add comment="NTP Cloudflare" dst-address=162.159.200.1/32 gateway=192.168.5.1
/system clock
set time-zone-autodetect=no time-zone-name=America/New_York
/system identity
set name=office-switch
/system ntp client
set enabled=yes
/system ntp client servers
add address=216.239.35.12
add address=162.159.200.1
/tool graphing interface
add allow-address=192.168.5.0/24 interface=sfp-sfpplus1 store-on-disk=no
add allow-address=192.168.5.0/24 interface=sfp-sfpplus2 store-on-disk=no
/tool graphing resource
add allow-address=192.168.5.0/24 store-on-disk=no
