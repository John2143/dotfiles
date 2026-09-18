# 2026-09-17 23:23:00 by RouterOS 7.19.6
# software id = KNIM-QKB7
#
# model = CRS310-8G+2S+
# serial number = HKG0AVERD3V
/interface bridge
add admin-mac=04:F4:1C:E6:7C:0C auto-mac=no comment=defconf name=bridge
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
add address=192.168.5.3/24 comment=defconf interface=bridge network=\
    192.168.5.0
/ip hotspot profile
set [ find default=yes ] html-directory=hotspot
/ip route
add comment="NTP Google" dst-address=216.239.35.12/32 gateway=192.168.5.1
add comment="NTP Cloudflare" dst-address=162.159.200.1/32 gateway=192.168.5.1
/system clock
set time-zone-autodetect=no time-zone-name=America/New_York
/system identity
set name=upstairs-switch
/system ntp client
set enabled=yes
/system ntp client servers
add address=216.239.35.12
add address=162.159.200.1
/tool graphing interface
add allow-address=192.168.5.0/24 interface=ether1 store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether4 store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether6 store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether8 store-on-disk=no
add allow-address=192.168.5.0/24 interface=sfp-sfpplus1 store-on-disk=no
/tool graphing resource
add allow-address=192.168.5.0/24 store-on-disk=no
