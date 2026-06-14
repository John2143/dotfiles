# 2026-01-29 19:48:28 by RouterOS 7.20.8
# software id = TAKC-K349
#
# model = CRS305-1G-4S+
# serial number = HMB0BED9WV8
/interface bridge
add admin-mac=D0:EA:11:6B:75:F3 auto-mac=no comment=defconf name=bridge
/interface bridge port
add bridge=bridge comment=defconf interface=ether1
add bridge=bridge comment=defconf interface=sfp-sfpplus1
add bridge=bridge comment=defconf interface=sfp-sfpplus2
add bridge=bridge comment=defconf interface=sfp-sfpplus3
add bridge=bridge comment=defconf interface=sfp-sfpplus4
/ip address
add address=192.168.88.1/24 comment=defconf interface=bridge network=\
    192.168.88.0
add address=192.168.5.5/24 interface=bridge network=192.168.5.0
/system identity
set name=upstairs-core
