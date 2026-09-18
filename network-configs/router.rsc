# 2026-09-17 23:22:51 by RouterOS 7.19.6
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
/interface wireguard
add comment="WireGuard remote access" listen-port=51820 mtu=1420 name=\
    wg-remote
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
/routing bgp template
set default afi=ip,ipv6
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
set discover-interface-list=LAN
/ipv6 settings
set accept-router-advertisements=yes
/interface list member
add comment=defconf interface=bridge list=LAN
add interface=2GWAN list=WAN
/interface wireguard peers
add allowed-address=10.99.0.2/32,10.244.0.0/16 comment=\
    "2143-k8s cluster: postgres client + tunnel" interface=wg-remote name=\
    peer1 public-key="jUMIaOQP8hPqzw3t//WZrpt/WTFkRzkD18LBM27RlEE="
/ip address
add address=192.168.0.2/24 interface=2GWAN network=192.168.0.0
add address=192.168.1.1/24 interface=bridge network=192.168.1.0
add address=192.168.88.254/24 interface=bridge network=192.168.88.0
add address=192.168.6.1/24 interface=bridge network=192.168.6.0
add address=10.99.0.1/24 comment="wg-remote tunnel subnet" interface=*C \
    network=10.99.0.0
add address=10.99.0.1/24 comment="wg-remote tunnel subnet" interface=\
    wg-remote network=10.99.0.0
add address=192.168.5.1/24 comment=defconf interface=bridge network=\
    192.168.5.0
/ip arp
add address=192.168.5.36 interface=bridge mac-address=0C:C4:7A:BD:63:3D
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
add address=192.168.5.76 comment=arch mac-address=98:B7:85:23:48:90
add address=192.168.5.9 client-id=1:dc:a6:32:25:51:6e mac-address=\
    DC:A6:32:25:51:6E server=dchp1
add address=192.168.5.209 client-id=1:c4:3d:1a:f3:e:76 comment=\
    "office k3s node (static)" mac-address=C4:3D:1A:F3:0E:76 server=dchp1
add address=192.168.5.68 client-id=1:bc:24:11:19:22:f9 comment=\
    "big k3s node (static)" mac-address=BC:24:11:19:22:F9 server=dchp1
/ip dhcp-server network
add address=192.168.1.0/24 dns-server=192.168.5.1 gateway=192.168.1.1
add address=192.168.5.0/24 dns-server=192.168.5.1 gateway=192.168.5.1 \
    netmask=24
/ip dns
set allow-remote-requests=yes mdns-repeat-ifaces=bridge,2GWAN servers=\
    1.1.1.1,1.0.0.1
/ip dns static
add address=192.168.5.1 comment=defconf name=router.lan type=A
add address=192.168.6.11 name=argo-webhook.john2143.com type=A
add address=192.168.6.11 name=argocd.ts.2143.me type=A
add address=192.168.6.11 name=au.2143.me type=A
add address=192.168.6.11 name=auth.john2143.com type=A
add address=192.168.6.11 name=cameras.john2143.com type=A
add address=192.168.6.11 name=cameras.ts.2143.me type=A
add address=192.168.6.11 name=cams.ts.2143.me type=A
add address=192.168.6.11 name=chat.2143.me type=A
add address=192.168.6.11 name=containerstore.john2143.com type=A
add address=192.168.6.11 name=element.john2143.com type=A
add address=192.168.6.11 name=files-ui.ts.2143.me type=A
add address=192.168.6.11 name=files.john2143.com type=A
add address=192.168.6.11 name=grafana.john2143.com type=A
add address=192.168.6.11 name=home.ts.2143.me type=A
add address=192.168.6.11 name=images.2143.me type=A
add address=192.168.6.11 name=immich.ts.2143.me type=A
add address=192.168.6.11 name=john2143.com type=A
add address=192.168.6.11 name=livekit.john2143.com type=A
add address=192.168.6.11 name=llm.2143.me type=A
add address=192.168.6.11 name=longhorn.ts.2143.me type=A
add address=192.168.6.11 name=m.2143.me type=A
add address=192.168.6.11 name=matrix.2143.me type=A
add address=192.168.6.11 name=mattermost.john2143.com type=A
add address=192.168.6.11 name=net.2143.me type=A
add address=192.168.6.11 name=net.john2143.com type=A
add address=192.168.6.11 name=pihole.ts.2143.me type=A
add address=192.168.6.11 name=prod.rots.2143.me type=A
add address=192.168.6.11 name=pvp.john2143.com type=A
add address=192.168.6.11 name=rots.2143.me type=A
add address=192.168.6.11 name=seafile.john2143.com type=A
add address=192.168.6.11 name=status.2143.me type=A
add address=192.168.6.11 name=temporal.john2143.com type=A
add address=192.168.6.11 name=temporal.ts.2143.me type=A
add address=192.168.6.11 name=unifi.ts.2143.me type=A
add address=192.168.6.13 name=imap.m.2143.me type=A
add address=192.168.6.13 name=smtp.m.2143.me type=A
add address=192.168.6.20 name=temporal-grpc.john2143.com type=A
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
add action=accept chain=input comment="wireguard remote access" dst-port=\
    51820 in-interface-list=WAN protocol=udp
add action=accept chain=input comment="wg: doks -> router DNS udp" dst-port=\
    53 in-interface=wg-remote protocol=udp
add action=accept chain=input comment="wg: doks -> router DNS tcp" dst-port=\
    53 in-interface=wg-remote protocol=tcp
add action=drop chain=input comment="no public postgres; log attempts" \
    dst-port=5432 in-interface-list=WAN log=yes log-prefix=pg-public-attempt \
    protocol=tcp
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
add action=accept chain=forward comment="wg: doks -> postgres" dst-address=\
    192.168.5.36 dst-port=5432 in-interface=wg-remote protocol=tcp
add action=drop chain=forward comment=\
    "wg: deny tunnel traffic not allowed above" in-interface=wg-remote log=\
    yes log-prefix=wg-drop
/ip firewall nat
add action=dst-nat chain=dstnat comment="monero p2p (tcp/18080) -> .5.76" \
    dst-port=18080 in-interface-list=WAN protocol=tcp to-addresses=\
    192.168.5.76 to-ports=18080
add action=dst-nat chain=dstnat comment="teamspeak voice (udp/9987) -> .6.15" \
    dst-port=9987 in-interface-list=WAN protocol=udp to-addresses=\
    192.168.6.15 to-ports=9987
add action=dst-nat chain=dstnat comment=\
    "teamspeak file transfer (tcp/30033) -> .6.16" dst-port=30033 \
    in-interface-list=WAN protocol=tcp to-addresses=192.168.6.16 to-ports=\
    30033
add action=dst-nat chain=dstnat comment="traefik http (tcp/80) -> .6.11" \
    dst-port=80 in-interface-list=WAN protocol=tcp to-addresses=192.168.6.11 \
    to-ports=80
add action=dst-nat chain=dstnat comment="traefik https (tcp/443) -> .6.11" \
    dst-port=443 in-interface-list=WAN protocol=tcp to-addresses=192.168.6.11 \
    to-ports=443
add action=masquerade chain=srcnat dst-address=!192.168.0.0/24 out-interface=\
    2GWAN
add action=dst-nat chain=dstnat comment="openrct2 (tcp/11753) -> .6.17" \
    dst-port=11753 in-interface-list=WAN protocol=tcp to-addresses=\
    192.168.6.17 to-ports=11753
add action=dst-nat chain=dstnat comment="mail-smtp (tcp/25) -> .6.13" \
    dst-port=25 in-interface-list=WAN protocol=tcp to-addresses=192.168.6.13 \
    to-ports=25
add action=dst-nat chain=dstnat comment="mail-submission (tcp/587) -> .6.13" \
    dst-port=587 in-interface-list=WAN protocol=tcp to-addresses=192.168.6.13 \
    to-ports=587
add action=dst-nat chain=dstnat comment="mail-imaps (tcp/993) -> .6.13" \
    dst-port=993 in-interface-list=WAN protocol=tcp to-addresses=192.168.6.13 \
    to-ports=993
add action=dst-nat chain=dstnat comment=\
    "livekit webrtc tcp (tcp/7881) -> .6.22" dst-port=7881 in-interface-list=\
    WAN protocol=tcp to-addresses=192.168.6.22 to-ports=7881
add action=dst-nat chain=dstnat comment=\
    "steam-lobby coturn TURN (tcp/3478) -> .6.14" dst-port=3478 \
    in-interface-list=WAN protocol=tcp to-addresses=192.168.6.14 to-ports=\
    3478
add action=dst-nat chain=dstnat comment=\
    "steam-lobby coturn TURN (udp/3478) -> .6.14" dst-port=3478 \
    in-interface-list=WAN protocol=udp to-addresses=192.168.6.14 to-ports=\
    3478
add action=dst-nat chain=dstnat comment=\
    "temporal-grpc mtls (tcp/7233) -> .6.20" dst-port=7233 in-interface-list=\
    WAN protocol=tcp to-addresses=192.168.6.20 to-ports=7233
add action=dst-nat chain=dstnat comment=\
    "linkerd multicluster (tcp/4143) -> .5.36" dst-port=4143 \
    in-interface-list=WAN protocol=tcp to-addresses=192.168.5.36 to-ports=\
    4143
add action=dst-nat chain=dstnat comment=\
    "steam-lobby coturn relay (udp/45000-45063) -> .6.14" dst-port=\
    45000-45063 in-interface-list=WAN protocol=udp to-addresses=192.168.6.14 \
    to-ports=45000-45063
add action=dst-nat chain=dstnat comment="factorio (udp/34197) -> .6.28" \
    dst-port=34197 in-interface-list=WAN protocol=udp to-addresses=\
    192.168.6.28 to-ports=34197
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
/routing bgp connection
add afi=ip,ipv6 as=65001 hold-time=3m local.address=192.168.5.1 .role=ebgp \
    name=metallb-arch remote.address=192.168.5.76 .as=65000
add afi=ip,ipv6 as=65001 local.address=192.168.5.1 .role=ebgp name=\
    metallb-closet remote.address=192.168.5.36 .as=65000
add afi=ip,ipv6 as=65001 local.address=192.168.5.1 .role=ebgp name=\
    metallb-nas remote.address=192.168.5.175 .as=65000
add afi=ip,ipv6 as=65001 local.address=192.168.5.1 .role=ebgp name=\
    metallb-big remote.address=192.168.5.68 .as=65000
add afi=ip,ipv6 as=65001 local.address=192.168.5.1 .role=ebgp name=\
    metallb-pite remote.address=192.168.5.9 .as=65000
/system clock
set time-zone-name=America/New_York
/system identity
set name=router
/system ntp client
set enabled=yes
/system ntp server
set enabled=yes
/system ntp client servers
add address=216.239.35.12
add address=162.159.200.1
/tool graphing interface
add allow-address=192.168.5.0/24 interface=2GWAN store-on-disk=no
add allow-address=192.168.5.0/24 interface=10GsfpLAN store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether3 store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether4 store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether6 store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether7 store-on-disk=no
add allow-address=192.168.5.0/24 interface=pi store-on-disk=no
add allow-address=192.168.5.0/24 interface=to-wifi store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether5 store-on-disk=no
/tool graphing resource
add allow-address=192.168.5.0/24 store-on-disk=no
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
/tool sniffer
set filter-interface=2GWAN filter-ip-address=108.56.153.222/32 filter-port=\
    18080
