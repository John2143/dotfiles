** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded. See https://openssh.com/pq.html
# 2026-01-29 13:58:17 by RouterOS 7.20.8
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
