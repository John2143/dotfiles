# 2026-05-07 19:03:32 by RouterOS 7.20.8
# software id = BFGZ-NVN3
#
# model = CRS305-1G-4S+
# serial number = HMC0B8ZZ7F2
/interface bridge
add admin-mac=D0:EA:11:70:B9:EB auto-mac=no comment=defconf name=bridge
/interface bridge port
add bridge=bridge comment=defconf interface=ether1
add bridge=bridge comment=defconf interface=sfp-sfpplus1
add bridge=bridge comment=defconf interface=sfp-sfpplus2
add bridge=bridge comment=defconf interface=sfp-sfpplus3
add bridge=bridge comment=defconf interface=sfp-sfpplus4
/ip address
add address=192.168.5.4/24 comment=defconf interface=bridge network=\
    192.168.5.0
/ip route
add gateway=192.168.5.1
/system identity
set name=core-switch
/tool graphing interface
add allow-address=192.168.5.0/24 interface=ether1 store-on-disk=no
add allow-address=192.168.5.0/24 interface=sfp-sfpplus1 store-on-disk=no
add allow-address=192.168.5.0/24 interface=sfp-sfpplus2 store-on-disk=no
add allow-address=192.168.5.0/24 interface=sfp-sfpplus3 store-on-disk=no
add allow-address=192.168.5.0/24 interface=sfp-sfpplus4 store-on-disk=no
/tool graphing resource
add allow-address=192.168.5.0/24 store-on-disk=no
