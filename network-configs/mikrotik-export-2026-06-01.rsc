** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded. See https://openssh.com/pq.html
# 2026-06-01 19:45:12 by RouterOS 7.19.6
# software id = 7RHC-3MMG
#
# model = RB5009UPr+S+
# serial number = HKG0AWJZPCK
/interface bridge
add admin-mac=04:F4:1C:E3:71:28 auto-mac=no comment=defconf name=bridge
/interface ethernet
set [ find default-name=ether1 ] name=2GWAN
set [ find default-name=sfp-sfpplus1 ] name=10GsfpLAN
set [ find default-name=ether2 ] name=pi
set [ find default-name=ether8 ] name=to-wifi
/interface list
add comment=defconf name=WAN
add comment=defconf name=LAN
/ip pool
add name=dhcp ranges=192.168.5.50-192.168.5.254
/ip dhcp-server
add address-pool=dhcp interface=bridge name=dchp1
/ipv6 dhcp-server
add address-pool=ula-addr-pool interface=bridge name=ula-dhcp
/ipv6 pool
add name=ula-addr-pool prefix=fd00:1::/64 prefix-length=128
/disk settings
set auto-media-interface=bridge auto-media-sharing=yes auto-smb-sharing=yes
/interface bridge port
add bridge=bridge comment=defconf interface=pi
add bridge=bridge comment=defconf interface=ether3
add bridge=bridge comment=defconf interface=ether4
add bridge=bridge comment=defconf interface=ether5
add bridge=bridge comment=defconf interface=ether6
add bridge=bridge comment=defconf interface=ether7
add bridge=bridge comment=defconf interface=to-wifi
add bridge=bridge comment=defconf interface=10GsfpLAN
/ip neighbor discovery-settings
# ipv6 *accept router advertisements* configuration has changed, please restart device to apply settings
set discover-interface-list=LAN
/ipv6 settings
# ipv6 *accept router advertisements* configuration has changed, please restart device to apply settings
set accept-router-advertisements=yes
/interface list member
add comment=defconf interface=bridge list=LAN
add interface=2GWAN list=WAN
/ip address
add address=192.168.5.1/24 comment=defconf interface=bridge network=\
    192.168.5.0
add address=192.168.0.2/24 interface=2GWAN network=192.168.0.0
add address=192.168.1.1/24 interface=bridge network=192.168.1.0
add address=192.168.88.254/24 interface=bridge network=192.168.88.0
/ip arp
add address=192.168.5.36 interface=bridge mac-address=0C:C4:7A:BD:63:3D
add address=192.168.5.35 interface=bridge mac-address=40:B0:76:D9:69:92
/ip dhcp-client
add comment=defconf interface=2GWAN
/ip dhcp-server lease
add address=192.168.1.66 client-id=1:ec:71:db:3e:2f:21 mac-address=\
    EC:71:DB:3E:2F:21 server=dchp1
add address=192.168.5.170 client-id=1:94:a9:90:6c:70:88 mac-address=\
    94:A9:90:6C:70:88 server=dchp1
add address=192.168.1.65 client-id=1:94:b3:f7:18:52:cc mac-address=\
    94:B3:F7:18:52:CC server=dchp1
add address=192.168.5.165 client-id=1:80:f1:b2:52:f0:c8 mac-address=\
    80:F1:B2:52:F0:C8 server=dchp1
add address=192.168.5.35 client-id=1:40:b0:76:d9:69:92 mac-address=\
    40:B0:76:D9:69:92 server=dchp1
add address=192.168.5.226 client-id=1:70:85:c2:a5:7:cc mac-address=\
    70:85:C2:A5:07:CC server=dchp1
add address=192.168.5.175 client-id=1:e8:4d:d0:c1:54:20 mac-address=\
    E8:4D:D0:C1:54:20 server=dchp1
add address=192.168.1.67 comment="Reolink NVR" mac-address=EC:71:DB:8B:92:93 \
    server=dchp1
add address=192.168.1.60 comment="Back yard" mac-address=78:93:C3:8E:34:9F \
    server=dchp1
add address=192.168.1.61 comment=Garage mac-address=EC:71:DB:F4:DC:49 server=\
    dchp1
add address=192.168.1.63 comment="Front porch" mac-address=EC:71:DB:89:D8:8B \
    server=dchp1
add address=192.168.1.64 comment="Front Gate" mac-address=EC:71:DB:65:58:A3 \
    server=dchp1
add address=192.168.5.127 mac-address=C8:FF:77:57:E0:3D server=dchp1
add address=192.168.5.36 comment="closet 10GbE NIC" mac-address=\
    0C:C4:7A:BD:63:3D server=dchp1
/ip dhcp-server network
add address=192.168.1.0/24 dns-server=192.168.5.1 gateway=192.168.1.1
add address=192.168.5.0/24 dns-server=192.168.5.1 gateway=192.168.5.1 \
    netmask=24
/ip dns
set allow-remote-requests=yes mdns-repeat-ifaces=bridge,2GWAN servers=\
    1.1.1.1,1.0.0.1
/ip dns static
add address=192.168.5.1 comment=defconf name=router.lan type=A
/ip firewall filter
add action=accept chain=forward comment="allow inter-subnet routing" \
    dst-address=192.168.0.0/16 src-address=192.168.0.0/16
add action=accept chain=input comment=\
    "defconf: accept established,related,untracked" connection-state=\
    established,related,untracked
add action=drop chain=input comment="defconf: drop invalid" connection-state=\
    invalid
add action=accept chain=input comment="defconf: accept ICMP" protocol=icmp
add action=accept chain=input comment=\
    "defconf: accept to local loopback (for CAPsMAN)" dst-address=127.0.0.1
add action=drop chain=input comment="defconf: drop all not coming from LAN" \
    in-interface-list=!LAN
add action=accept chain=forward comment="defconf: accept in ipsec policy" \
    ipsec-policy=in,ipsec
add action=accept chain=forward comment="defconf: accept out ipsec policy" \
    ipsec-policy=out,ipsec
add action=fasttrack-connection chain=forward comment="defconf: fasttrack" \
    connection-state=established,related hw-offload=yes
add action=accept chain=forward comment=\
    "defconf: accept established,related, untracked" connection-state=\
    established,related,untracked
add action=drop chain=forward comment="defconf: drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment=\
    "defconf: drop all from WAN not DSTNATed" connection-nat-state=!dstnat \
    connection-state=new in-interface-list=WAN
add action=drop chain=forward comment="block camera subnet WAN egress" \
    dst-address=!192.168.0.0/16 src-address=192.168.1.0/24
/ip firewall nat
add action=dst-nat chain=dstnat comment="Monero P2P node (arch)" dst-port=\
    18080 in-interface-list=all protocol=tcp to-addresses=192.168.5.226 \
    to-ports=18080
add action=dst-nat chain=dstnat dst-port=9987 in-interface-list=WAN protocol=\
    udp to-addresses=192.168.5.10 to-ports=30087
add action=dst-nat chain=dstnat dst-port=30033 in-interface-list=WAN \
    protocol=tcp to-addresses=192.168.5.10 to-ports=30034
add action=dst-nat chain=dstnat dst-port=80 in-interface-list=WAN protocol=\
    tcp to-addresses=192.168.5.10 to-ports=80
add action=dst-nat chain=dstnat dst-port=443 in-interface-list=WAN protocol=\
    tcp to-addresses=192.168.5.10 to-ports=443
add action=dst-nat chain=dstnat dst-port=5432 in-interface-list=all protocol=\
    tcp to-addresses=192.168.5.35 to-ports=5432
add action=dst-nat chain=dstnat dst-port=30478 in-interface-list=all \
    protocol=udp to-addresses=192.168.5.10 to-ports=30478
add action=dst-nat chain=dstnat dst-port=25565 in-interface-list=all \
    protocol=tcp to-addresses=192.168.5.175 to-ports=32565
add action=dst-nat chain=dstnat dst-port=32565 in-interface-list=all \
    protocol=tcp to-addresses=192.168.5.175 to-ports=32565
add action=masquerade chain=srcnat dst-address=!192.168.0.0/24 out-interface=\
    2GWAN
add action=dst-nat chain=dstnat dst-port=11753 in-interface-list=all \
    protocol=tcp to-addresses=192.168.5.10 to-ports=31753
/ip route
add disabled=no dst-address=192.168.1.0/24 gateway=bridge routing-table=main \
    suppress-hw-offload=no
/ip service
set www port=8081
/ipv6 address
add address=2600:4040:25fa:e400:6f4:1cff:fee3:7127 advertise=no interface=\
    2GWAN
add address=fd00:1::1 interface=bridge
/ipv6 dhcp-server binding
add address=fd00:1::36/128 duid=0x48750ccae3a454a0f9f03492c0c3c4ed ia-type=na \
    iaid=2138897477 life-time=3d prefix-pool=ula-addr-pool server=ula-dhcp
/ipv6 firewall address-list
add address=::/128 comment="defconf: unspecified address" list=bad_ipv6
add address=::1/128 comment="defconf: lo" list=bad_ipv6
add address=fec0::/10 comment="defconf: site-local" list=bad_ipv6
add address=::ffff:0.0.0.0/96 comment="defconf: ipv4-mapped" list=bad_ipv6
add address=::/96 comment="defconf: ipv4 compat" list=bad_ipv6
add address=100::/64 comment="defconf: discard only " list=bad_ipv6
add address=2001:db8::/32 comment="defconf: documentation" list=bad_ipv6
add address=2001:10::/28 comment="defconf: ORCHID" list=bad_ipv6
add address=3ffe::/16 comment="defconf: 6bone" list=bad_ipv6
/ipv6 firewall filter
add action=accept chain=input comment=\
    "defconf: accept established,related,untracked" connection-state=\
    established,related,untracked
add action=drop chain=input comment="defconf: drop invalid" connection-state=\
    invalid
add action=accept chain=input comment="defconf: accept ICMPv6" protocol=\
    icmpv6
add action=accept chain=input comment="defconf: accept UDP traceroute" \
    dst-port=33434-33534 protocol=udp
add action=accept chain=input comment=\
    "defconf: accept DHCPv6-Client prefix delegation." dst-port=546 protocol=\
    udp src-address=fe80::/10
add action=accept chain=input comment="defconf: accept IKE" dst-port=500,4500 \
    protocol=udp
add action=accept chain=input comment="defconf: accept ipsec AH" protocol=\
    ipsec-ah
add action=accept chain=input comment="defconf: accept ipsec ESP" protocol=\
    ipsec-esp
add action=accept chain=input comment=\
    "defconf: accept all that matches ipsec policy" ipsec-policy=in,ipsec
add action=drop chain=input comment=\
    "defconf: drop everything else not coming from LAN" in-interface-list=\
    !LAN
add action=fasttrack-connection chain=forward comment="defconf: fasttrack6" \
    connection-state=established,related
add action=accept chain=forward comment=\
    "defconf: accept established,related,untracked" connection-state=\
    established,related,untracked
add action=drop chain=forward comment="defconf: drop invalid" \
    connection-state=invalid
add action=drop chain=forward comment=\
    "defconf: drop packets with bad src ipv6" src-address-list=bad_ipv6
add action=drop chain=forward comment=\
    "defconf: drop packets with bad dst ipv6" dst-address-list=bad_ipv6
add action=drop chain=forward comment="defconf: rfc4890 drop hop-limit=1" \
    hop-limit=equal:1 protocol=icmpv6
add action=accept chain=forward comment="defconf: accept ICMPv6" protocol=\
    icmpv6
add action=accept chain=forward comment="defconf: accept HIP" protocol=139
add action=accept chain=forward comment="defconf: accept IKE" dst-port=\
    500,4500 protocol=udp
add action=accept chain=forward comment="defconf: accept ipsec AH" protocol=\
    ipsec-ah
add action=accept chain=forward comment="defconf: accept ipsec ESP" protocol=\
    ipsec-esp
add action=accept chain=forward comment=\
    "defconf: accept all that matches ipsec policy" ipsec-policy=in,ipsec
add action=drop chain=forward comment=\
    "defconf: drop everything else not coming from LAN" in-interface-list=\
    !LAN
add action=accept chain=input connection-state=established,related
add action=accept chain=forward connection-state=established,related
/ipv6 firewall nat
add action=masquerade chain=srcnat out-interface=2GWAN
/ipv6 nd
set [ find default=yes ] managed-address-configuration=yes
/system clock
set time-zone-name=America/New_York
/system identity
set name="MikroTik Router"
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
/tool sniffer
set filter-interface=2GWAN filter-ip-address=108.56.153.222/32 filter-port=\
    18080
