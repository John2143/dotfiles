# 2026-06-14 05:25:07 by RouterOS 7.19.6
# software id = 7RHC-3MMG
#
# model = RB5009UPr+S+
# serial number = HKG0AWJZPCK
/interface bridge
add admin-mac=04:F4:1C:E3:71:28 ageing-time=5m arp=enabled arp-timeout=auto \
    auto-mac=no comment=defconf dhcp-snooping=no disabled=no fast-forward=yes \
    forward-delay=15s igmp-snooping=no max-learned-entries=auto \
    max-message-age=20s mtu=auto mvrp=no name=bridge port-cost-mode=long \
    priority=0x8000 protocol-mode=rstp transmit-hold-count=6 vlan-filtering=\
    no
/interface ethernet
set [ find default-name=ether1 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full,2.5G-baseT" arp=\
    enabled arp-timeout=auto auto-negotiation=yes bandwidth=\
    unlimited/unlimited disabled=no l2mtu=1514 loop-protect=default \
    loop-protect-disable-time=5m loop-protect-send-interval=5s mac-address=\
    04:F4:1C:E3:71:27 mtu=1500 name=2GWAN orig-mac-address=04:F4:1C:E3:71:27 \
    poe-out=auto-on poe-priority=10 power-cycle-interval=none \
    !power-cycle-ping-address power-cycle-ping-enabled=no \
    !power-cycle-ping-timeout rx-flow-control=off tx-flow-control=off
set [ find default-name=sfp-sfpplus1 ] advertise="10M-baseT-half,10M-baseT-ful\
    l,100M-baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full,1G-baseX,2.5\
    G-baseT,2.5G-baseX,5G-baseT,10G-baseT,10G-baseSR-LR,10G-baseCR" arp=\
    enabled arp-timeout=auto auto-negotiation=yes bandwidth=\
    unlimited/unlimited disabled=no l2mtu=1514 loop-protect=default \
    loop-protect-disable-time=5m loop-protect-send-interval=5s mac-address=\
    04:F4:1C:E3:71:2F mtu=1500 name=10GsfpLAN orig-mac-address=\
    04:F4:1C:E3:71:2F rx-flow-control=off sfp-ignore-rx-los=no \
    sfp-rate-select=high sfp-shutdown-temperature=95C tx-flow-control=off
set [ find default-name=ether3 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:29 mtu=1500 \
    name=ether3 orig-mac-address=04:F4:1C:E3:71:29 poe-out=auto-on \
    poe-priority=10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
set [ find default-name=ether4 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:2A mtu=1500 \
    name=ether4 orig-mac-address=04:F4:1C:E3:71:2A poe-out=auto-on \
    poe-priority=10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
set [ find default-name=ether5 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:2B mtu=1500 \
    name=ether5 orig-mac-address=04:F4:1C:E3:71:2B poe-out=auto-on \
    poe-priority=10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
set [ find default-name=ether6 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:2C mtu=1500 \
    name=ether6 orig-mac-address=04:F4:1C:E3:71:2C poe-out=auto-on \
    poe-priority=10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
set [ find default-name=ether7 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:2D mtu=1500 \
    name=ether7 orig-mac-address=04:F4:1C:E3:71:2D poe-out=auto-on \
    poe-priority=10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
set [ find default-name=ether2 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:28 mtu=1500 \
    name=pi orig-mac-address=04:F4:1C:E3:71:28 poe-out=auto-on poe-priority=\
    10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
set [ find default-name=ether8 ] advertise="10M-baseT-half,10M-baseT-full,100M\
    -baseT-half,100M-baseT-full,1G-baseT-half,1G-baseT-full" arp=enabled \
    arp-timeout=auto auto-negotiation=yes bandwidth=unlimited/unlimited \
    disabled=no l2mtu=1514 loop-protect=default loop-protect-disable-time=5m \
    loop-protect-send-interval=5s mac-address=04:F4:1C:E3:71:2E mtu=1500 \
    name=to-wifi orig-mac-address=04:F4:1C:E3:71:2E poe-out=auto-on \
    poe-priority=10 power-cycle-interval=none !power-cycle-ping-address \
    power-cycle-ping-enabled=no !power-cycle-ping-timeout rx-flow-control=off \
    tx-flow-control=off
/queue interface
set bridge queue=no-queue
/interface ethernet switch
set 0 cpu-flow-control=yes mirror-egress-target=none name=switch1
/interface ethernet switch port
set 0 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 1 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 2 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 3 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 4 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 5 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 6 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 7 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 8 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
set 9 !egress-rate !ingress-rate mirror-egress=no mirror-ingress=no \
    mirror-ingress-target=none
/interface ethernet switch port-isolation
set 0 !forwarding-override
set 1 !forwarding-override
set 2 !forwarding-override
set 3 !forwarding-override
set 4 !forwarding-override
set 5 !forwarding-override
set 6 !forwarding-override
set 7 !forwarding-override
set 8 !forwarding-override
set 9 !forwarding-override
/interface list
set [ find name=all ] comment="contains all interfaces" exclude="" include="" \
    name=all
set [ find name=none ] comment="contains no interfaces" exclude="" include="" \
    name=none
set [ find name=dynamic ] comment="contains dynamic interfaces" exclude="" \
    include="" name=dynamic
set [ find name=static ] comment="contains static interfaces" exclude="" \
    include="" name=static
add comment=defconf exclude="" include="" name=WAN
add comment=defconf exclude="" include="" name=LAN
/interface lte apn
set [ find default=yes ] add-default-route=yes apn=internet authentication=\
    none default-route-distance=2 ip-type=auto name=default use-network-apn=\
    yes use-peer-dns=yes
/interface macsec profile
set [ find default-name=default ] name=default server-priority=10
/ip dhcp-client option
set clientid_duid code=61 name=clientid_duid value="0xff\$(CLIENT_DUID)"
set clientid code=61 name=clientid value="0x01\$(CLIENT_MAC)"
set hostname code=12 name=hostname value="\$(HOSTNAME)"
/ip hotspot profile
set [ find default=yes ] dns-name="" hotspot-address=0.0.0.0 html-directory=\
    hotspot html-directory-override="" http-cookie-lifetime=3d http-proxy=\
    0.0.0.0:0 install-hotspot-queue=no login-by=cookie,http-chap name=default \
    smtp-server=0.0.0.0 split-user-domain=no use-radius=no
/ip hotspot user profile
set [ find default=yes ] add-mac-cookie=yes address-list="" idle-timeout=none \
    !insert-queue-before keepalive-timeout=2m mac-cookie-timeout=3d name=\
    default !parent-queue !queue-type shared-users=1 status-autorefresh=1m \
    transparent-proxy=no
/ip ipsec mode-config
set [ find default=yes ] name=request-only responder=no use-responder-dns=\
    exclusively
/ip ipsec policy group
set [ find default=yes ] name=default
/ip ipsec profile
set [ find default=yes ] dh-group=modp2048,modp1024 dpd-interval=8s \
    dpd-maximum-failures=4 enc-algorithm=aes-128,3des hash-algorithm=sha1 \
    lifetime=1d name=default nat-traversal=yes proposal-check=obey
/ip ipsec proposal
set [ find default=yes ] auth-algorithms=sha1 disabled=no enc-algorithms=\
    aes-256-cbc,aes-192-cbc,aes-128-cbc lifetime=30m name=default pfs-group=\
    modp1024
/ip pool
add name=dhcp ranges=192.168.5.50-192.168.5.254
/ip dhcp-server
add address-lists="" address-pool=dhcp disabled=no interface=bridge \
    lease-script="" lease-time=30m name=dchp1 use-radius=no use-reconfigure=\
    no
/ip smb users
set [ find default=yes ] disabled=no name=guest read-only=yes
/ipv6 dhcp-server
add address-lists="" address-pool=ula-addr-pool dhcp-option="" disabled=no \
    interface=bridge lease-time=3d name=ula-dhcp preference=255 prefix-pool=\
    static-only rapid-commit=yes route-distance=1 use-radius=no \
    use-reconfigure=no
/ipv6 pool
add name=ula-addr-pool prefix=fd00:1::/64 prefix-length=128
/ppp profile
set *0 address-list="" !bridge !bridge-horizon bridge-learning=default \
    !bridge-path-cost !bridge-port-priority !bridge-port-trusted \
    !bridge-port-vid change-tcp-mss=yes !dns-server !idle-timeout \
    !incoming-filter !insert-queue-before !interface-list !local-address \
    name=default on-down="" on-up="" only-one=default !outgoing-filter \
    !parent-queue !queue-type !rate-limit !remote-address !session-timeout \
    use-compression=default use-encryption=default use-ipv6=yes use-mpls=\
    default use-upnp=default !wins-server
set *FFFFFFFE address-list="" !bridge !bridge-horizon bridge-learning=default \
    !bridge-path-cost !bridge-port-priority !bridge-port-trusted \
    !bridge-port-vid change-tcp-mss=yes !dns-server !idle-timeout \
    !incoming-filter !insert-queue-before !interface-list !local-address \
    name=default-encryption on-down="" on-up="" only-one=default \
    !outgoing-filter !parent-queue !queue-type !rate-limit !remote-address \
    !session-timeout use-compression=default use-encryption=yes use-ipv6=yes \
    use-mpls=default use-upnp=default !wins-server
/queue type
set 0 kind=pfifo name=default pfifo-limit=50
set 1 kind=pfifo name=ethernet-default pfifo-limit=50
set 2 kind=sfq name=wireless-default sfq-allot=1514 sfq-perturb=5
set 3 kind=red name=synchronous-default red-avg-packet=1000 red-burst=20 \
    red-limit=60 red-max-threshold=50 red-min-threshold=10
set 4 kind=sfq name=hotspot-default sfq-allot=1514 sfq-perturb=5
set 5 kind=pcq name=pcq-upload-default pcq-burst-rate=0 pcq-burst-threshold=0 \
    pcq-burst-time=10s pcq-classifier=src-address pcq-dst-address-mask=32 \
    pcq-dst-address6-mask=128 pcq-limit=50KiB pcq-rate=0 \
    pcq-src-address-mask=32 pcq-src-address6-mask=128 pcq-total-limit=2000KiB
set 6 kind=pcq name=pcq-download-default pcq-burst-rate=0 \
    pcq-burst-threshold=0 pcq-burst-time=10s pcq-classifier=dst-address \
    pcq-dst-address-mask=32 pcq-dst-address6-mask=128 pcq-limit=50KiB \
    pcq-rate=0 pcq-src-address-mask=32 pcq-src-address6-mask=128 \
    pcq-total-limit=2000KiB
set 7 kind=none name=only-hardware-queue
set 8 kind=mq-pfifo mq-pfifo-limit=50 name=multi-queue-ethernet-default
set 9 kind=pfifo name=default-small pfifo-limit=10
/queue interface
set "2GWAN" queue=only-hardware-queue
set "10GsfpLAN" queue=only-hardware-queue
set ether3 queue=only-hardware-queue
set ether4 queue=only-hardware-queue
set ether5 queue=only-hardware-queue
set ether6 queue=only-hardware-queue
set ether7 queue=only-hardware-queue
set pi queue=only-hardware-queue
set to-wifi queue=only-hardware-queue
/routing bgp template
set default as=65530 name=default
/snmp community
set [ find default=yes ] addresses=::/0 authentication-protocol=MD5 disabled=\
    no encryption-protocol=DES name=public read-access=yes security=none \
    write-access=no
/system logging action
set 0 memory-lines=1000 memory-stop-on-full=no name=memory target=memory
set 1 disk-file-count=2 disk-file-name=log disk-lines-per-file=1000 \
    disk-stop-on-full=no name=disk target=disk
set 2 name=echo remember=yes target=echo
set 3 name=remote remote=0.0.0.0 remote-log-format=default remote-port=514 \
    remote-protocol=udp src-address=0.0.0.0 syslog-facility=daemon \
    syslog-severity=auto syslog-time-format=bsd-syslog target=remote vrf=main
/user group
set read name=read policy="local,telnet,ssh,reboot,read,test,winbox,password,w\
    eb,sniff,sensitive,api,romon,rest-api,!ftp,!write,!policy" skin=default
set write name=write policy="local,telnet,ssh,reboot,read,write,test,winbox,pa\
    ssword,web,sniff,sensitive,api,romon,rest-api,!ftp,!policy" skin=default
set full name=full policy="local,telnet,ssh,ftp,reboot,read,write,policy,test,\
    winbox,password,web,sniff,sensitive,api,romon,rest-api" skin=default
/certificate settings
set builtin-trust-anchors=not-trusted crl-download=no crl-store=ram crl-use=\
    no
/console settings
set log-script-errors=yes sanitize-names=no
/disk settings
set auto-media-interface=bridge auto-media-sharing=yes auto-smb-sharing=yes \
    auto-smb-user=guest default-mount-point-template="[slot]"
/ip smb
set comment=MikrotikSMB domain=MSHOME enabled=auto interfaces=all
/interface bridge port
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=pi \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=ether3 \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=ether4 \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=ether5 \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=ether6 \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=ether7 \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=to-wifi \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
add auto-isolate=no bpdu-guard=no bridge=bridge broadcast-flood=yes comment=\
    defconf disabled=no edge=auto fast-leave=no frame-types=admit-all \
    horizon=none hw=yes ingress-filtering=yes interface=10GsfpLAN \
    !internal-path-cost learn=auto multicast-router=temporary-query \
    mvrp-applicant-state=normal-participant mvrp-registrar-state=normal \
    !path-cost point-to-point=auto priority=0x80 pvid=1 restricted-role=no \
    restricted-tcn=no tag-stacking=no trusted=no unknown-multicast-flood=yes \
    unknown-unicast-flood=yes
/interface bridge settings
set allow-fast-path=yes use-ip-firewall=no use-ip-firewall-for-pppoe=no \
    use-ip-firewall-for-vlan=no
/ip firewall connection tracking
set enabled=auto generic-timeout=10m icmp-timeout=10s loose-tcp-tracking=yes \
    tcp-close-timeout=10s tcp-close-wait-timeout=10s tcp-established-timeout=\
    1d tcp-fin-wait-timeout=10s tcp-last-ack-timeout=10s \
    tcp-max-retrans-timeout=5m tcp-syn-received-timeout=5s \
    tcp-syn-sent-timeout=5s tcp-time-wait-timeout=10s tcp-unacked-timeout=5m \
    udp-stream-timeout=3m udp-timeout=30s
/ip neighbor discovery-settings
set discover-interface-list=LAN discover-interval=30s lldp-mac-phy-config=no \
    lldp-max-frame-size=no lldp-med-net-policy-vlan=disabled lldp-poe-power=\
    yes lldp-vlan-info=no mode=tx-and-rx protocol=cdp,lldp,mndp
/ip settings
set accept-redirects=no accept-source-route=no allow-fast-path=yes \
    arp-timeout=30s icmp-errors-use-inbound-interface-address=no \
    icmp-rate-limit=10 icmp-rate-mask=0x1818 ip-forward=yes \
    ipv4-multipath-hash-policy=l3 max-neighbor-entries=16384 rp-filter=no \
    secure-redirects=yes send-redirects=yes tcp-syncookies=no tcp-timestamps=\
    random-offset
/ipv6 settings
set accept-redirects=yes-if-forwarding-disabled accept-router-advertisements=\
    yes allow-fast-path=yes disable-ipv6=no disable-link-local-address=no \
    forward=yes max-neighbor-entries=16384 min-neighbor-entries=4096 \
    multipath-hash-policy=l3 soft-max-neighbor-entries=8192 \
    stale-neighbor-detect-interval=30 stale-neighbor-timeout=60
/interface detect-internet
set detect-interface-list=none internet-interface-list=none \
    lan-interface-list=none wan-interface-list=none
/interface ethernet poe settings
set psu1-max-power=96W psu2-max-power=150W
/interface l2tp-server server
set accept-proto-version=all accept-pseudowire-type=all allow-fast-path=no \
    authentication=pap,chap,mschap1,mschap2 caller-id-type=ip-address \
    default-profile=default-encryption enabled=no keepalive-timeout=30 \
    l2tpv3-circuit-id="" l2tpv3-cookie-length=0 l2tpv3-digest-hash=md5 \
    !l2tpv3-ether-interface-list max-mru=1450 max-mtu=1450 max-sessions=\
    unlimited mrru=disabled one-session-per-host=no use-ipsec=no
/interface list member
add comment=defconf disabled=no interface=bridge list=LAN
add disabled=no interface=2GWAN list=WAN
/interface lte settings
set esim-channel=auto firmware-path=firmware link-recovery-timer=120 mode=\
    auto
/interface pptp-server server
# PPTP connections are considered unsafe, it is suggested to use a more modern VPN protocol instead
set authentication=mschap1,mschap2 default-profile=default-encryption \
    enabled=no keepalive-timeout=30 max-mru=1450 max-mtu=1450 mrru=disabled
/interface sstp-server server
set authentication=pap,chap,mschap1,mschap2 certificate=none ciphers=\
    aes256-sha,aes256-gcm-sha384 default-profile=default enabled=no \
    keepalive-timeout=60 max-mru=1500 max-mtu=1500 mrru=disabled pfs=no port=\
    443 tls-version=any verify-client-certificate=no
/interface wifi cap
set enabled=no
/interface wifi capsman
set enabled=no
/ip address
add address=192.168.5.1/24 comment=defconf disabled=no interface=bridge \
    network=192.168.5.0
add address=192.168.0.2/24 disabled=no interface=2GWAN network=192.168.0.0
add address=192.168.1.1/24 disabled=no interface=bridge network=192.168.1.0
add address=192.168.88.254/24 disabled=no interface=bridge network=\
    192.168.88.0
/ip arp
add address=192.168.5.36 disabled=no interface=bridge mac-address=\
    0C:C4:7A:BD:63:3D published=no
add address=192.168.5.35 disabled=no interface=bridge mac-address=\
    40:B0:76:D9:69:92 published=no
/ip cloud
set back-to-home-vpn=revoked-and-disabled ddns-enabled=auto \
    ddns-update-interval=none update-time=yes
/ip cloud advanced
set use-local-address=no
/ip dhcp-client
add add-default-route=yes allow-reconfigure=no check-gateway=none comment=\
    defconf default-route-distance=1 default-route-tables=default \
    dhcp-options=hostname,clientid disabled=no interface=2GWAN use-peer-dns=\
    yes use-peer-ntp=yes
/ip dhcp-server config
set accounting=yes interim-update=0s radius-password=empty store-leases-disk=\
    5m
/ip dhcp-server lease
add address=192.168.1.66 address-lists="" !allow-dual-stack-queue client-id=\
    1:ec:71:db:3e:2f:21 dhcp-option="" disabled=no !insert-queue-before \
    mac-address=EC:71:DB:3E:2F:21 !parent-queue !queue-type server=dchp1
add address=192.168.5.170 address-lists="" !allow-dual-stack-queue client-id=\
    1:94:a9:90:6c:70:88 dhcp-option="" disabled=no !insert-queue-before \
    mac-address=94:A9:90:6C:70:88 !parent-queue !queue-type server=dchp1
add address=192.168.1.65 address-lists="" !allow-dual-stack-queue client-id=\
    1:94:b3:f7:18:52:cc dhcp-option="" disabled=no !insert-queue-before \
    mac-address=94:B3:F7:18:52:CC !parent-queue !queue-type server=dchp1
add address=192.168.5.165 address-lists="" !allow-dual-stack-queue client-id=\
    1:80:f1:b2:52:f0:c8 dhcp-option="" disabled=no !insert-queue-before \
    mac-address=80:F1:B2:52:F0:C8 !parent-queue !queue-type server=dchp1
add address=192.168.5.35 address-lists="" !allow-dual-stack-queue client-id=\
    1:40:b0:76:d9:69:92 dhcp-option="" disabled=no !insert-queue-before \
    mac-address=40:B0:76:D9:69:92 !parent-queue !queue-type server=dchp1
add address=192.168.5.226 address-lists="" !allow-dual-stack-queue client-id=\
    1:70:85:c2:a5:7:cc dhcp-option="" disabled=no !insert-queue-before \
    mac-address=70:85:C2:A5:07:CC !parent-queue !queue-type server=dchp1
add address=192.168.5.175 address-lists="" !allow-dual-stack-queue client-id=\
    1:e8:4d:d0:c1:54:20 dhcp-option="" disabled=no !insert-queue-before \
    mac-address=E8:4D:D0:C1:54:20 !parent-queue !queue-type server=dchp1
add address=192.168.1.67 address-lists="" !allow-dual-stack-queue comment=\
    "Reolink NVR" dhcp-option="" disabled=no !insert-queue-before \
    mac-address=EC:71:DB:8B:92:93 !parent-queue !queue-type server=dchp1
add address=192.168.1.60 address-lists="" !allow-dual-stack-queue comment=\
    "Back yard" dhcp-option="" disabled=no !insert-queue-before mac-address=\
    78:93:C3:8E:34:9F !parent-queue !queue-type server=dchp1
add address=192.168.1.61 address-lists="" !allow-dual-stack-queue comment=\
    Garage dhcp-option="" disabled=no !insert-queue-before mac-address=\
    EC:71:DB:F4:DC:49 !parent-queue !queue-type server=dchp1
add address=192.168.1.63 address-lists="" !allow-dual-stack-queue comment=\
    "Front porch" dhcp-option="" disabled=no !insert-queue-before \
    mac-address=EC:71:DB:89:D8:8B !parent-queue !queue-type server=dchp1
add address=192.168.1.64 address-lists="" !allow-dual-stack-queue comment=\
    "Front Gate" dhcp-option="" disabled=no !insert-queue-before mac-address=\
    EC:71:DB:65:58:A3 !parent-queue !queue-type server=dchp1
add address=192.168.5.127 address-lists="" !allow-dual-stack-queue \
    dhcp-option="" disabled=no !insert-queue-before mac-address=\
    C8:FF:77:57:E0:3D !parent-queue !queue-type server=dchp1
add address=192.168.5.36 address-lists="" !allow-dual-stack-queue comment=\
    "closet 10GbE NIC" dhcp-option="" disabled=no !insert-queue-before \
    mac-address=0C:C4:7A:BD:63:3D !parent-queue !queue-type server=dchp1
add address=192.168.5.76 address-lists="" !allow-dual-stack-queue comment=\
    arch dhcp-option="" disabled=no !insert-queue-before mac-address=\
    98:B7:85:23:48:90 !parent-queue !queue-type
/ip dhcp-server network
add address=192.168.1.0/24 caps-manager="" dhcp-option="" dns-server=\
    192.168.5.1 gateway=192.168.1.1 !next-server ntp-server="" wins-server=""
add address=192.168.5.0/24 caps-manager="" dhcp-option="" dns-server=\
    192.168.5.1 gateway=192.168.5.1 netmask=24 !next-server ntp-server="" \
    wins-server=""
/ip dns
set address-list-extra-time=0s allow-remote-requests=yes cache-max-ttl=1w \
    cache-size=2048KiB doh-max-concurrent-queries=50 \
    doh-max-server-connections=5 doh-timeout=5s max-concurrent-queries=100 \
    max-concurrent-tcp-sessions=20 max-udp-packet-size=4096 \
    mdns-repeat-ifaces=bridge,2GWAN query-server-timeout=2s \
    query-total-timeout=10s servers=1.1.1.1,1.0.0.1 use-doh-server="" \
    verify-doh-cert=no vrf=main
/ip dns static
add address=192.168.5.1 comment=defconf disabled=no name=router.lan ttl=1d \
    type=A
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
    18080 in-interface-list=all protocol=tcp to-addresses=192.168.5.76 \
    to-ports=18080
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=9987 !fragment !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=WAN \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=udp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.10 \
    to-ports=30087 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=30033 !fragment !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=WAN \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=tcp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.10 \
    to-ports=30034 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=80 !fragment !icmp-options !in-bridge-port !in-bridge-port-list \
    !in-interface in-interface-list=WAN !ingress-priority !ipsec-policy \
    !ipv4-options !layer7-protocol !limit log=no log-prefix="" !nth \
    !out-bridge-port !out-bridge-port-list !out-interface !out-interface-list \
    !packet-mark !packet-size !per-connection-classifier !port !priority \
    protocol=tcp !psd !random !routing-mark !src-address !src-address-list \
    !src-address-type !src-mac-address !src-port !tcp-mss !time to-addresses=\
    192.168.5.10 to-ports=80 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=443 !fragment !icmp-options !in-bridge-port !in-bridge-port-list \
    !in-interface in-interface-list=WAN !ingress-priority !ipsec-policy \
    !ipv4-options !layer7-protocol !limit log=no log-prefix="" !nth \
    !out-bridge-port !out-bridge-port-list !out-interface !out-interface-list \
    !packet-mark !packet-size !per-connection-classifier !port !priority \
    protocol=tcp !psd !random !routing-mark !src-address !src-address-list \
    !src-address-type !src-mac-address !src-port !tcp-mss !time to-addresses=\
    192.168.5.10 to-ports=443 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=5432 !fragment !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=all \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=tcp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.35 \
    to-ports=5432 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=30478 !fragment !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=all \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=udp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.10 \
    to-ports=30478 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=25565 !fragment !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=all \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=tcp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.175 \
    to-ports=32565 !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=32565 !fragment !hotspot !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=all \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=tcp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.175 \
    to-ports=32565 !ttl
add action=masquerade chain=srcnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp dst-address=!192.168.0.0/24 !dst-address-list !dst-address-type \
    !dst-limit !dst-port !fragment !hotspot !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface !in-interface-list !ingress-priority \
    !ipsec-policy !ipv4-options !layer7-protocol !limit log=no log-prefix="" \
    !nth !out-bridge-port !out-bridge-port-list out-interface=2GWAN \
    !out-interface-list !packet-mark !packet-size !per-connection-classifier \
    !port !priority !protocol !psd !random !routing-mark !src-address \
    !src-address-list !src-address-type !src-mac-address !src-port !tcp-mss \
    !time !to-addresses !to-ports !ttl
add action=dst-nat chain=dstnat !connection-bytes !connection-limit \
    !connection-mark !connection-rate !connection-type !content disabled=no \
    !dscp !dst-address !dst-address-list !dst-address-type !dst-limit \
    dst-port=11753 !fragment !icmp-options !in-bridge-port \
    !in-bridge-port-list !in-interface in-interface-list=all \
    !ingress-priority !ipsec-policy !ipv4-options !layer7-protocol !limit \
    log=no log-prefix="" !nth !out-bridge-port !out-bridge-port-list \
    !out-interface !out-interface-list !packet-mark !packet-size \
    !per-connection-classifier !port !priority protocol=tcp !psd !random \
    !routing-mark !src-address !src-address-list !src-address-type \
    !src-mac-address !src-port !tcp-mss !time to-addresses=192.168.5.10 \
    to-ports=31753 !ttl
add action=dst-nat chain=dstnat comment="mail-smtp stalwart" dst-port=25 \
    in-interface-list=all protocol=tcp to-addresses=192.168.5.10 to-ports=25
add action=dst-nat chain=dstnat comment="mail-submission stalwart" dst-port=\
    587 in-interface-list=all protocol=tcp to-addresses=192.168.5.10 \
    to-ports=587
add action=dst-nat chain=dstnat comment="mail-imaps stalwart" dst-port=993 \
    in-interface-list=all protocol=tcp to-addresses=192.168.5.10 to-ports=993
/ip firewall service-port
set ftp disabled=no ports=21
set tftp disabled=no ports=69
set irc disabled=yes ports=6667
set h323 disabled=no
set sip disabled=no ports=5060,5061 sip-direct-media=yes sip-timeout=1h
set pptp disabled=no
set rtsp disabled=yes ports=554
set udplite disabled=no
set dccp disabled=no
set sctp disabled=no
/ip hotspot service-port
set ftp disabled=no ports=21
/ip hotspot user
set [ find default=yes ] comment="counters and limits for trial users" \
    disabled=no name=default-trial
/ip ipsec policy
set 0 disabled=no dst-address=::/0 group=default proposal=default protocol=\
    all src-address=::/0 template=yes
/ip ipsec settings
set accounting=yes interim-update=0s xauth-use-radius=no
/ip media settings
set thumbnails=""
/ip nat-pmp
set enabled=no
/ip proxy
# inactivated, not allowed by device-mode
set always-from-cache=no anonymous=no cache-administrator=webmaster \
    cache-hit-dscp=4 cache-on-disk=no cache-path=web-proxy enabled=no \
    max-cache-object-size=2048KiB max-cache-size=unlimited \
    max-client-connections=600 max-fresh-time=3d max-server-connections=600 \
    parent-proxy=:: parent-proxy-port=0 port=8080 serialize-connections=no \
    src-address=::
/ip route
add disabled=no dst-address=192.168.1.0/24 gateway=bridge routing-table=main \
    suppress-hw-offload=no
/ip service
set ftp address="" disabled=no max-sessions=20 port=21 vrf=main
set ssh address="" disabled=no max-sessions=20 port=22 vrf=main
set telnet address="" disabled=no max-sessions=20 port=23 vrf=main
set www-ssl address="" certificate=none disabled=yes max-sessions=20 port=443 \
    tls-version=any vrf=main
set www address="" disabled=no max-sessions=20 port=8081 vrf=main
set winbox address="" disabled=no max-sessions=20 port=8291 vrf=main
set api address="" disabled=no max-sessions=20 port=8728 vrf=main
set api-ssl address="" certificate=none disabled=no max-sessions=20 port=8729 \
    tls-version=any vrf=main
/ip smb shares
set [ find default=yes ] directory=pub disabled=yes invalid-users="" name=pub \
    read-only=no require-encryption=no valid-users=""
/ip socks
# inactivated, not allowed by device-mode
set auth-method=none connection-idle-timeout=2m enabled=no max-connections=\
    200 port=1080 version=4 vrf=main
/ip ssh
set always-allow-password-login=no ciphers=auto forwarding-enabled=no \
    host-key-size=2048 host-key-type=rsa strong-crypto=no
/ip tftp settings
set max-block-size=4096
/ip traffic-flow
set active-flow-timeout=30m cache-entries=256k enabled=no \
    inactive-flow-timeout=15s interfaces=all packet-sampling=no \
    sampling-interval=0 sampling-space=0
/ip traffic-flow ipfix
set bytes=yes dst-address=yes dst-address-mask=yes dst-mac-address=yes \
    dst-port=yes first-forwarded=yes gateway=yes icmp-code=yes icmp-type=yes \
    igmp-type=yes in-interface=yes ip-header-length=yes ip-total-length=yes \
    ipv6-flow-label=yes is-multicast=yes last-forwarded=yes nat-dst-address=\
    yes nat-dst-port=yes nat-events=no nat-src-address=yes nat-src-port=yes \
    out-interface=yes packets=yes protocol=yes src-address=yes \
    src-address-mask=yes src-mac-address=yes src-port=yes sys-init-time=yes \
    tcp-ack-num=yes tcp-flags=yes tcp-seq-num=yes tcp-window-size=yes tos=yes \
    ttl=yes udp-length=yes
/ip upnp
set allow-disable-external-interface=no enabled=no show-dummy-rule=yes
/ipv6 address
add address=2600:4040:25fa:e400:6f4:1cff:fee3:7127/64 advertise=no \
    auto-link-local=yes disabled=no eui-64=no from-pool="" interface=2GWAN \
    no-dad=no
add address=fd00:1::1/64 advertise=yes auto-link-local=yes disabled=no \
    eui-64=no from-pool="" interface=bridge no-dad=no
/ipv6 dhcp-server binding
add address=fd00:1::36/128 address-lists="" !allow-dual-stack-queue \
    dhcp-option="" disabled=no duid=0x48750ccae3a454a0f9f03492c0c3c4ed \
    ia-type=na iaid=2138897477 !insert-queue-before life-time=3d \
    !parent-queue prefix-pool=ula-addr-pool !queue-type server=ula-dhcp
/ipv6 firewall address-list
add address=::/128 comment="defconf: unspecified address" disabled=no \
    dynamic=no list=bad_ipv6
add address=::1/128 comment="defconf: lo" disabled=no dynamic=no list=\
    bad_ipv6
add address=fec0::/10 comment="defconf: site-local" disabled=no dynamic=no \
    list=bad_ipv6
add address=::ffff:0.0.0.0/96 comment="defconf: ipv4-mapped" disabled=no \
    dynamic=no list=bad_ipv6
add address=::/96 comment="defconf: ipv4 compat" disabled=no dynamic=no list=\
    bad_ipv6
add address=100::/64 comment="defconf: discard only " disabled=no dynamic=no \
    list=bad_ipv6
add address=2001:db8::/32 comment="defconf: documentation" disabled=no \
    dynamic=no list=bad_ipv6
add address=2001:10::/28 comment="defconf: ORCHID" disabled=no dynamic=no \
    list=bad_ipv6
add address=3ffe::/16 comment="defconf: 6bone" disabled=no dynamic=no list=\
    bad_ipv6
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
add action=masquerade chain=srcnat out-interface=2GWAN !to-address !to-ports
/ipv6 nd
set [ find default=yes ] advertise-dns=yes advertise-mac-address=yes \
    disabled=no hop-limit=unspecified interface=all \
    managed-address-configuration=yes mtu=unspecified other-configuration=no \
    ra-delay=3s ra-interval=3m20s-10m ra-lifetime=30m ra-preference=medium \
    reachable-time=unspecified retransmit-interval=unspecified
/ipv6 nd prefix default
set autonomous=yes preferred-lifetime=1w valid-lifetime=4w2d
/mpls settings
set allow-fast-path=yes dynamic-label-range=16-1048575 propagate-ttl=yes
/ppp aaa
set accounting=yes enable-ipv6-accounting=no interim-update=0s \
    use-circuit-id-in-nas-port-id=no use-radius=no
/radius incoming
set accept=no port=3799 vrf=main
/routing igmp-proxy
set query-interval=2m5s query-response-interval=10s quick-leave=no
/routing settings
set single-process=no
/snmp
set contact="" enabled=no engine-id-suffix="" location="" src-address=:: \
    trap-community=public trap-generators=temp-exception trap-target="" \
    trap-version=1 vrf=main
/system clock
set time-zone-autodetect=yes time-zone-name=America/New_York
/system clock manual
set dst-delta=+00:00 dst-end="1970-01-01 00:00:00" dst-start=\
    "1970-01-01 00:00:00" time-zone=+00:00
/system health settings
set cpu-overtemp-check=no cpu-overtemp-startup-delay=1m \
    cpu-overtemp-threshold=105C
/system identity
set name=router
/system leds
set 0 disabled=no interface=10GsfpLAN leds=sfp-sfpplus1-led type=\
    interface-activity
/system leds settings
set all-leds-off=never
/system logging
set 0 action=memory disabled=no prefix="" regex="" topics=info
set 1 action=memory disabled=no prefix="" regex="" topics=error
set 2 action=memory disabled=no prefix="" regex="" topics=warning
set 3 action=echo disabled=no prefix="" regex="" topics=critical
/system note
set note="" show-at-cli-login=no show-at-login=yes
/system ntp client
set enabled=no mode=unicast servers="" vrf=main
/system ntp server
set auth-key=none broadcast=no broadcast-addresses="" enabled=no \
    local-clock-stratum=5 manycast=no multicast=no use-local-clock=no vrf=\
    main
/system package local-update mirror
set check-interval=1d enabled=no primary-server=0.0.0.0 secondary-server=\
    0.0.0.0 user=""
/system resource irq
set 0 cpu=auto
set 1 cpu=auto
set 2 cpu=auto
set 3 cpu=auto
set 4 cpu=auto
set 5 cpu=auto
set 6 cpu=auto
set 7 cpu=auto
set 8 cpu=auto
set 9 cpu=auto
set 10 cpu=auto
set 11 cpu=auto
set 12 cpu=auto
set 13 cpu=auto
set 14 cpu=auto
set 15 cpu=auto
/system resource irq rps
set "2GWAN" disabled=yes
set pi disabled=yes
set ether3 disabled=yes
set ether4 disabled=yes
set ether5 disabled=yes
set ether6 disabled=yes
set ether7 disabled=yes
set to-wifi disabled=yes
set "10GsfpLAN" disabled=yes
/system resource usb settings
set authorization=no
/system routerboard reset-button
set enabled=no hold-time=0s..1m on-event=""
/system routerboard settings
set auto-upgrade=no boot-device=nand-if-fail-then-ethernet boot-protocol=\
    bootp force-backup-booter=no preboot-etherboot=disabled \
    preboot-etherboot-server=any protected-routerboot=disabled \
    reformat-hold-button=20s reformat-hold-button-max=10m silent-boot=no
/system watchdog
set auto-send-supout=no automatic-supout=yes ping-start-after-boot=5m \
    ping-timeout=1m watch-address=none watchdog-timer=yes
/tool bandwidth-server
set allocate-udp-ports-from=2000 allowed-addresses4="" allowed-addresses6="" \
    authenticate=yes enabled=yes max-sessions=100
/tool e-mail
set from=<> port=25 server=0.0.0.0 tls=no user="" vrf=main
/tool graphing
set page-refresh=300 store-every=5min
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
/tool mac-server ping
set enabled=yes
/tool romon
# inactivated, not allowed by device-mode
set enabled=no id=00:00:00:00:00:00
/tool romon port
# inactivated, not allowed by device-mode
set [ find default=yes ] cost=100 disabled=no forbid=no interface=all
/tool sms
set allowed-number="" channel=0 polling=no port=none receive-enabled=no \
    sms-storage=sim
/tool sniffer
set file-limit=1000KiB file-name="" filter-cpu="" filter-direction=any \
    filter-dst-ip-address="" filter-dst-ipv6-address="" \
    filter-dst-mac-address="" filter-dst-port="" filter-interface=2GWAN \
    filter-ip-address=108.56.153.222/32 filter-ip-protocol="" \
    filter-ipv6-address="" filter-mac-address="" filter-mac-protocol="" \
    filter-operator-between-entries=or filter-port=18080 filter-size="" \
    filter-src-ip-address="" filter-src-ipv6-address="" \
    filter-src-mac-address="" filter-src-port="" filter-stream=no \
    filter-vlan="" max-packet-size=2048 memory-limit=100KiB memory-scroll=yes \
    only-headers=no quick-rows=20 quick-show-frame=no streaming-enabled=no \
    streaming-server=0.0.0.0:37008
/tool traffic-generator
set latency-distribution-max=100us measure-out-of-order=no \
    stats-samples-to-keep=100 test-id=0
/user aaa
set accounting=yes default-group=read exclude-groups="" interim-update=0s \
    use-radius=no
/user settings
set minimum-categories=0 minimum-password-length=0
