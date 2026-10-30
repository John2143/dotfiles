# 2026-10-30 09:37:55 by RouterOS 7.24.5
# software id = 7RHC-3MMG
#
# model = RB5009UPr+S+
# serial number = HKG0AWJZPCK
/interface bridge
add admin-mac=04:F4:1C:E3:71:28 auto-mac=no comment=defconf name=bridge
/interface ethernet
set [ find default-name=ether1 ] comment="WAN: Verizon CR1000B 192.168.0.1" \
    l2mtu=1514 name=2GWAN
set [ find default-name=sfp-sfpplus1 ] comment=\
    "10G uplink to core sfp-sfpplus4" l2mtu=1514 name=10GsfpLAN
set [ find default-name=ether7 ] comment=\
    "Front driveway camera 192.168.1.66, own power" l2mtu=1514 name=cam-front
set [ find default-name=ether2 ] comment=\
    "core switch ether1: PoE power + 1G mgmt. NEVER poe-out=off" l2mtu=1514 \
    name=core-poe
set [ find default-name=ether3 ] comment="unconfirmed peer: link up, no MAC le\
    arned; flaps coincide with nas reboots" l2mtu=1514
set [ find default-name=ether6 ] comment=empty l2mtu=1514
set [ find default-name=ether4 ] comment=\
    "JetKVM 192.168.5.187 (100M link is normal)" l2mtu=1514 name=jetkvm
set [ find default-name=ether8 ] comment=\
    "pite (Raspberry Pi k3s agent) 192.168.5.9" l2mtu=1514 name=pite
set [ find default-name=ether5 ] comment=\
    "U7 Lite AP, PoE. U7 Mesh uplinks wirelessly to it" l2mtu=1514 name=\
    u7-lite
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
/ipv6 dhcp-server option
add code=23 comment="lan-dns: DHCPv6 DNS = router ULA, not Verizon" name=\
    dns-router-ula value=0xfd000001000000000000000000000001
/ipv6 pool
add name=ula-addr-pool prefix=fd00:1::/64 prefix-length=128
/routing bgp instance
add as=65001 name=bgp-instance-1 router-id=192.168.5.1 vrf=main
/routing bgp template
set default afi=ip,ipv6 as=65001
/system logging action
add name=loki remote=192.168.6.25 remote-log-format=syslog src-address=\
    192.168.5.1 syslog-facility=local0 target=remote
/system script
add comment=\
    "lan-dns failover: starts lan-dns-watch once; see argo docs/lan-dns.md" \
    dont-require-permissions=no name=lan-dns-down owner=admin policy=\
    read,write,test source=":if ([:len [/system script job find where script=\
    \"lan-dns-watch\"]] = 0) do={ :execute script=\"/system script run lan-dns\
    -watch\" }"
add comment="lan-dns failover; see argo docs/lan-dns.md" \
    dont-require-permissions=no name=lan-dns-up owner=admin policy=\
    read,write,test source="/ip dns static enable [find comment=\"lan-dns forw\
    ard\"]; /ip dns cache flush; :log warning \"lan-dns up: LAN forwards enabl\
    ed\""
add comment="lan-dns failover loop, started by lan-dns-down; see argo docs/lan\
    -dns.md" dont-require-permissions=no name=lan-dns-watch owner=admin \
    policy=read,write,test source=":local bad 0; :local done false; :log info \
    \"lan-dns watch: netwatch down, re-checking\"; :while ((!\$done) && ([/too\
    l netwatch get [find name=\"lan-dns\"] status] = \"down\")) do={ :local ok\
    \_false; :do { :if ([:resolve john2143.com server=192.168.6.30] in 192.168\
    .0.0/16) do={ :set ok true } } on-error={ :set ok false }; :if (\$ok) do={\
    \_:set bad 0 } else={ :set bad (\$bad + 1) }; :if (\$bad >= 3) do={ /ip dn\
    s static disable [find comment=\"lan-dns forward\"]; /ip dns cache flush; \
    :log warning \"lan-dns down: LAN forwards disabled\"; :set done true } els\
    e={ :delay 5s } }; :if (!\$done) do={ :log info \"lan-dns watch: netwatch \
    up again, no failover\" }"
add comment="ingress-follow; see argo docs/2026-10-15-fungible-ingress.md" \
    dont-require-permissions=no name=ingress-follow owner=admin policy=\
    read,write,test source="# ingress-follow - RouterOS script source (not an \
    /export). Installed as\
    \n# /system script \"ingress-follow\"; run every minute by the test-script\
    \_of\
    \n# /tool netwatch \"ingress-follow\" (device-mode home blocks /system sch\
    eduler).\
    \n# Points WAN 80/443 at the cluster ingress VIP: john2143.com -> router D\
    NS ->\
    \n# lan-dns -> k8s_gateway -> Gateway address -> Traefik VIP. Answers outs\
    ide\
    \n# 192.168.6.0/24 (resolve failure, or lan-dns down so the router saw the\
    \_public\
    \n# answer) keep the current target. Install/verify: argo docs/2026-10-15-\
    fungible-ingress.md.\
    \n:local ok false\
    \n:local ip\
    \n:do { :set ip [:resolve \"john2143.com\"]; :set ok true } on-error={}\
    \n:if (!\$ok) do={\
    \n  :log warning \"ingress-follow: cannot resolve john2143.com; keeping cu\
    rrent dst-nat target\"\
    \n} else={\
    \n  :if (!(\$ip in 192.168.6.0/24)) do={\
    \n    :log warning (\"ingress-follow: john2143.com resolved to \" . \$ip .\
    \_\" (outside 192.168.6.0/24); keeping current dst-nat target\")\
    \n  } else={\
    \n    :foreach c in={\"ingress http (tcp/80) -> traefik VIP (ingress-follo\
    w)\";\"ingress https (tcp/443) -> traefik VIP (ingress-follow)\"} do={\
    \n      :local ids [/ip firewall nat find comment=\$c]\
    \n      :if ([:len \$ids] != 1) do={\
    \n        :log error (\"ingress-follow: expected 1 nat rule with comment '\
    \" . \$c . \"', found \" . [:len \$ids])\
    \n      } else={\
    \n        :local cur [/ip firewall nat get (\$ids->0) to-addresses]\
    \n        :if (\$cur != [:tostr \$ip]) do={\
    \n          /ip firewall nat set (\$ids->0) to-addresses=\$ip\
    \n          :log warning (\"ingress-follow: \" . \$c . \" \" . \$cur . \" \
    -> \" . \$ip)\
    \n        }\
    \n      }\
    \n    }\
    \n  }\
    \n}\
    \n"
add comment=disarmed dont-require-permissions=no name=fe-revert-pite owner=\
    admin policy=read,write,test source=":delay 6m; :if ([/system script get [\
    find name=\"fe-revert-pite\"] comment] != \"disarmed\") do={ /routing bgp \
    connection enable [find name=\"metallb-pite\"]; :log warning \"fe-revert-p\
    ite: dead-man fired, metallb-pite re-enabled\" } else={ :log info \"fe-rev\
    ert-pite: disarmed\" }"
/disk settings
set auto-media-interface=bridge auto-media-sharing=yes auto-smb-sharing=yes
/interface bridge port
add bridge=bridge comment=defconf interface=core-poe
add bridge=bridge comment=defconf interface=ether3
add bridge=bridge comment=defconf interface=jetkvm
add bridge=bridge comment=defconf interface=u7-lite
add bridge=bridge comment=defconf interface=ether6
add bridge=bridge comment=defconf interface=cam-front
add bridge=bridge comment=defconf interface=pite
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
add address=10.99.0.1/24 comment="wg-remote tunnel subnet" interface=\
    wg-remote network=10.99.0.0
add address=192.168.5.1/24 comment=defconf interface=bridge network=\
    192.168.5.0
/ip arp
add address=192.168.5.36 interface=bridge mac-address=0C:C4:7A:BD:63:3D
/ip dhcp-client
add comment=defconf interface=2GWAN name=2GWAN
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
add comment="lan-dns forward" forward-to=192.168.6.30 match-subdomain=yes \
    name=2143.me type=FWD
add comment="lan-dns forward" forward-to=192.168.6.30 match-subdomain=yes \
    name=aross.studio type=FWD
add comment="lan-dns forward" forward-to=192.168.6.30 match-subdomain=yes \
    name=balabusta.homes type=FWD
add comment="lan-dns forward" forward-to=192.168.6.30 match-subdomain=yes \
    name=chess.dsstar.us type=FWD
add comment="lan-dns forward" forward-to=192.168.6.30 match-subdomain=yes \
    name=mm.b.hero.rehab type=FWD
add comment="lan-dns forward" forward-to=192.168.6.30 match-subdomain=yes \
    name=john2143.com type=FWD
/ip firewall address-list
add address=192.168.5.36 comment=closet list=k8s-nodes
add address=192.168.5.76 comment=arch list=k8s-nodes
add address=192.168.5.175 comment=nas list=k8s-nodes
add address=192.168.5.68 comment=big list=k8s-nodes
add address=192.168.5.9 comment=pite list=k8s-nodes
add address=192.168.5.209 comment=office list=k8s-nodes
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
add action=drop chain=input comment=\
    "bgp: only k8s-nodes (argo docs/node-maintenance.md)" dst-port=179 \
    protocol=tcp src-address-list=!k8s-nodes
add action=drop chain=input comment="defconf: drop all not coming from LAN" \
    in-interface-list=!LAN
add action=accept chain=forward comment="defconf: accept in ipsec policy" \
    ipsec-policy=in,ipsec
add action=accept chain=forward comment="defconf: accept out ipsec policy" \
    ipsec-policy=out,ipsec
add action=fasttrack-connection chain=forward comment="defconf: fasttrack" \
    connection-state=established,related
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
add action=accept chain=forward comment="wg: doks -> temporal" dst-address=\
    192.168.6.20 dst-port=7233 in-interface=wg-remote protocol=tcp
add action=accept chain=forward comment="wg: doks -> seaweed s3" dst-address=\
    192.168.6.31 dst-port=8333 in-interface=wg-remote protocol=tcp
add action=accept chain=forward comment="wg: doks -> mimir" dst-address=\
    192.168.6.23 dst-port=8080 protocol=tcp src-address=10.99.0.2
add action=accept chain=forward comment="wg: doks -> loki" dst-address=\
    192.168.6.24 dst-port=3100 protocol=tcp src-address=10.99.0.2
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
add action=dst-nat chain=dstnat comment=\
    "ingress http (tcp/80) -> traefik VIP (ingress-follow)" dst-port=80 \
    in-interface-list=WAN protocol=tcp to-addresses=192.168.6.6 to-ports=80
add action=dst-nat chain=dstnat comment=\
    "ingress https (tcp/443) -> traefik VIP (ingress-follow)" dst-port=443 \
    in-interface-list=WAN protocol=tcp to-addresses=192.168.6.6 to-ports=443
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
    "steam-lobby coturn relay (udp/45000-45063) -> .6.14" dst-port=\
    45000-45063 in-interface-list=WAN protocol=udp to-addresses=192.168.6.14 \
    to-ports=45000-45063
add action=dst-nat chain=dstnat comment="factorio (udp/34197) -> .6.28" \
    dst-port=34197 in-interface-list=WAN protocol=udp to-addresses=\
    192.168.6.28 to-ports=34197
add action=dst-nat chain=dstnat comment="minecraft (tcp/25565) -> .6.29" \
    dst-port=25565 in-interface-list=WAN protocol=tcp to-addresses=\
    192.168.6.29 to-ports=25565
add action=dst-nat chain=dstnat comment="headscale stun (udp/3479) -> .6.18" \
    dst-port=3479 in-interface-list=WAN protocol=udp to-addresses=\
    192.168.6.18 to-ports=3479
/ip route
add disabled=no dst-address=192.168.1.0/24 gateway=bridge routing-table=main
add blackhole comment="fail-closed: MetalLB v4 pool (unannounced VIPs drop)" \
    distance=250 dst-address=192.168.6.0/24
add blackhole comment="fail-closed: reserved nonprod v4 pool" distance=250 \
    dst-address=192.168.7.0/24
/ipv6 route
add blackhole comment="fail-closed: MetalLB v6 pool (unannounced VIPs drop)" \
    distance=250 dst-address=fd00:6::/64
add blackhole comment="fail-closed: reserved nonprod v6 pool" distance=250 \
    dst-address=fd00:7::/64
/ip service
set ftp disabled=yes
set telnet disabled=yes
set reverse-proxy disabled=yes
set www disabled=yes port=8081
set api disabled=yes
set api-ssl disabled=yes
/ipv6 address
add address=fd00:1::1 interface=bridge
/ipv6 dhcp-server
add address-pool=ula-addr-pool dhcp-option=dns-router-ula interface=bridge \
    name=ula-dhcp
/ipv6 dhcp-server binding
add address=fd00:1::36/128 duid=0x000448750ccae3a454a0f9f03492c0c3c4ed \
    ia-type=na iaid=2138897477 life-time=3d prefix-pool=ula-addr-pool server=\
    ula-dhcp
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
/ipv6 firewall nat
add action=masquerade chain=srcnat out-interface=2GWAN
/ipv6 nd
set [ find default=yes ] managed-address-configuration=yes
/routing bfd configuration
add addresses=192.168.5.0/24 comment="metallb speakers: BFD for BGP (argo docs\
    /2026-10-15-fungible-ingress.md)" min-rx=300ms min-tx=300ms multiplier=5
/routing bgp connection
add afi=ip,ipv6 as=65001 comment="MetalLB speakers on any k8s-nodes address (a\
    rgo docs/node-maintenance.md)" connect=no disabled=no input.filter=\
    metallb-in .limit-process-routes-ipv4=1000 .limit-process-routes-ipv6=\
    1000 instance=bgp-instance-1 listen=yes local.address=192.168.5.1 .role=\
    ebgp name=metallb-speakers remote.address=192.168.5.0/24 .allowed-as=\
    metallb-as routing-table=main use-bfd=yes
/routing filter num-list
add comment="MetalLB speaker AS" list=metallb-as range=65000
/routing filter rule
add chain=metallb-in comment="metallb service /32s" rule=\
    "if (dst in 192.168.6.0/24 && dst-len == 32) { accept }"
add chain=metallb-in comment="k3s API VIP" rule=\
    "if (dst == 192.168.5.10/32) { accept }"
add chain=metallb-in comment="metallb service /128s" rule=\
    "if (dst in fd00:6::/64 && dst-len == 128) { accept }"
/system clock
set time-zone-name=America/New_York
/system identity
set name=router
/system logging
add action=loki topics=info
add action=loki topics=warning
add action=loki topics=error
add action=loki topics=critical
/system ntp client
set enabled=yes
/system ntp server
set enabled=yes
/system ntp client servers
add address=216.239.35.12
add address=162.159.200.1
/tool bandwidth-server
set enabled=no
/tool graphing interface
add allow-address=192.168.5.0/24 interface=2GWAN store-on-disk=no
add allow-address=192.168.5.0/24 interface=10GsfpLAN store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether3 store-on-disk=no
add allow-address=192.168.5.0/24 interface=jetkvm store-on-disk=no
add allow-address=192.168.5.0/24 interface=ether6 store-on-disk=no
add allow-address=192.168.5.0/24 interface=cam-front store-on-disk=no
add allow-address=192.168.5.0/24 interface=core-poe store-on-disk=no
add allow-address=192.168.5.0/24 interface=pite store-on-disk=no
add allow-address=192.168.5.0/24 interface=u7-lite store-on-disk=no
/tool graphing resource
add allow-address=192.168.5.0/24 store-on-disk=no
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
/tool netwatch
add comment="lan-dns failover" dns-server=192.168.6.30 down-script=\
    "/system script run lan-dns-down" host=john2143.com interval=10s name=\
    lan-dns record-type=A timeout=3s type=dns up-script=\
    "/system script run lan-dns-up"
add comment="ingress-follow: runs the follower every minute (test-script; devi\
    ce-mode home blocks scheduler); see argo docs/2026-10-15-fungible-ingress.\
    md" host=john2143.com interval=1m name=ingress-follow test-script=\
    "/system script run ingress-follow" timeout=3s type=dns
/tool sniffer
set filter-interface=2GWAN filter-ip-address=108.56.153.222/32 filter-port=\
    18080
