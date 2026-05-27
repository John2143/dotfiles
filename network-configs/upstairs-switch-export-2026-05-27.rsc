** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded. See https://openssh.com/pq.html
# 2025-09-17 19:06:31 by RouterOS 7.19.6
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
