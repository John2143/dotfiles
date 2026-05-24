# Hardware Specs: nas

**Generated:** 2026-05-24T02:16:59Z

## System Overview

| Field | Value |
|---|---|
| Hostname | nas |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.31 x86_64 |
| Motherboard | Gigabyte Technology Co., Ltd. Z77X-UD3H (To be filled by O.E.M.) |
| Chassis | Desktop |
| BIOS | American Megatrends Inc. F18 (10/24/2012) |

## CPU

| Field | Value |
|---|---|
| Model | Intel(R) Core(TM) i7-3770K CPU @ 3.50GHz |
| Architecture | x86_64 |
| Cores | 4 (8 threads, 2 per core) |
| Sockets | 1 |
| Max Frequency | 3.9 GHz (boost) |
| Min Frequency | 1600 MHz |
| L1d Cache | 128 KiB (4 instances) |
| L1i Cache | 128 KiB (4 instances) |
| L2 Cache | 1 MiB (4 instances) |
| L3 Cache | 8 MiB (1 instance) |
| Microcode | 0x21 |
| Virtualization | VT-x |
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx rdtscp lm constant_tsc arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx est tm2 ssse3 cx16 xtpr pdcm pc… |

## Memory

### Summary

| Type | Size |
|---|---|
| RAM | 15Gi |
| Swap | 15Gi |

_No DIMM details available (requires root/dmidecode on x86)_

## Storage

```
sda                                              1.8T disk                                                                                                                                                 WDC WDS200T2B0A-00SM50    0
├─sda1                                             4G part  vfat       /boot                                                                                                                                                         0
├─sda2                                             1T part  ext4       /                                                                                                                                                             0
├─sda3                                            16G part                                                                                                                                                                           0
│ └─dev-disk-byx2dpartlabel-diskx2dmainx2dswap    16G crypt swap       [SWAP]                                                                                                                                                        0
├─sda4                                           100G part  zfs_member                                                                                                                                                               0
├─sda5                                           200G part  zfs_member                                                                                                                                                               0
└─sda6                                           519G part  zfs_member                                                                                                                                                               0
sdb                                              7.3T disk                                                                                                                                                 ST8000DM004-2CX188        1
├─sdb1                                           7.3T part  zfs_member                                                                                                                                                               1
└─sdb9                                             8M part                                                                                                                                                                           1
sdc                                              7.3T disk                                                                                                                                                 ST8000DM004-2CX188        1
├─sdc1                                           7.3T part  zfs_member                                                                                                                                                               1
└─sdc9                                             8M part                                                                                                                                                                           1
sdd                                              7.3T disk                                                                                                                                                 ST8000DM004-2CX188        1
├─sdd1                                           7.3T part  zfs_member                                                                                                                                                               1
└─sdd9                                             8M part                                                                                                                                                                           1
sde                                              7.3T disk                                                                                                                                                 ST8000DM004-2CX188        1
├─sde1                                           7.3T part  zfs_member                                                                                                                                                               1
└─sde9                                             8M part                                                                                                                                                                           1
sdf                                            119.2G disk                                                                                                                                                 OCZ-VERTEX4               0
└─sdf1                                           100G part  zfs_member                                                                                                                                                               0
sdg                                                5G disk  ext4       /var/lib/kubelet/pods/df229353-19bc-4e8c-b87e-a20979027405/volumes/kubernetes.io~csi/pvc-0dbbdc7c-61d9-4115-a47c-cd28f0828b30/mount VIRTUAL-DISK              1
sdh                                              1.9G disk  ext4       /var/lib/kubelet/pods/ec60b98c-2032-4d3f-8b21-76be96cf9d9e/volumes/kubernetes.io~csi/pvc-69326882-17a9-4fa6-a258-72f75abda5b6/mount VIRTUAL-DISK              1
sdi                                                1G disk  ext4       /var/lib/kubelet/pods/df229353-19bc-4e8c-b87e-a20979027405/volumes/kubernetes.io~csi/pvc-06073865-fbc6-494e-ac3f-60119ed8400e/mount VIRTUAL-DISK              1
sr0                                             1024M rom                                                                                                                                                  Virtual Media             0
```

## GPU

- `00:02.0` Intel Corporation IvyBridge GT2 [HD Graphics 4000] [8086:0162] rev 09

## Network

| Device | Interface | Description |
|---|---|---|
| 01:00.0 | enp1s0f0 | Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01 |
| 01:00.1 | enp1s0f1 | Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01 |
| 06:00.0 | enp6s0 | Qualcomm Atheros AR8161 Gigabit Ethernet [1969:1091] rev 10 |

## PCI Devices

- `00:00.0` Intel Corporation Xeon E3-1200 v2/3rd Gen Core processor DRAM Controller [8086:0150] rev 09
- `00:01.0` Intel Corporation Xeon E3-1200 v2/3rd Gen Core processor PCI Express Root Port [8086:0151] rev 09
- `00:02.0` Intel Corporation IvyBridge GT2 [HD Graphics 4000] [8086:0162] rev 09
- `00:14.0` Intel Corporation 7 Series/C210 Series Chipset Family USB xHCI Host Controller [8086:1e31] rev 04
- `00:16.0` Intel Corporation 7 Series/C216 Chipset Family MEI Controller #1 [8086:1e3a] rev 04
- `00:1a.0` Intel Corporation 7 Series/C216 Chipset Family USB Enhanced Host Controller #2 [8086:1e2d] rev 04
- `00:1b.0` Intel Corporation 7 Series/C216 Chipset Family High Definition Audio Controller [8086:1e20] rev 04
- `00:1c.0` Intel Corporation 7 Series/C216 Chipset Family PCI Express Root Port 1 [8086:1e10] rev c4
- `00:1c.4` Intel Corporation 7 Series/C210 Series Chipset Family PCI Express Root Port 5 [8086:1e18] rev c4
- `00:1c.5` Intel Corporation 82801 PCI Bridge [8086:244e] rev c4
- `00:1c.6` Intel Corporation 7 Series/C210 Series Chipset Family PCI Express Root Port 7 [8086:1e1c] rev c4
- `00:1c.7` Intel Corporation 7 Series/C210 Series Chipset Family PCI Express Root Port 8 [8086:1e1e] rev c4
- `00:1d.0` Intel Corporation 7 Series/C216 Chipset Family USB Enhanced Host Controller #1 [8086:1e26] rev 04
- `00:1f.0` Intel Corporation Z77 Express Chipset LPC Controller [8086:1e44] rev 04
- `00:1f.2` Intel Corporation 7 Series/C210 Series Chipset Family 6-port SATA Controller [AHCI mode] [8086:1e02] rev 04
- `00:1f.3` Intel Corporation 7 Series/C216 Chipset Family SMBus Controller [8086:1e22] rev 04
- `01:00.0` Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01
- `01:00.1` Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01
- `03:00.0` VIA Technologies, Inc. VL800/801 xHCI USB 3.0 Controller [1106:3432] rev 03
- `04:00.0` Intel Corporation 82801 PCI Bridge [8086:244e] rev 41
- `06:00.0` Qualcomm Atheros AR8161 Gigabit Ethernet [1969:1091] rev 10
- `07:00.0` Marvell Technology Group Ltd. 88SE9172 SATA 6Gb/s Controller [1b4b:9172] rev 11

## USB Devices

- `1d6b:0002` Linux Foundation 2.0 root hub
- `8087:0024` Intel Corp. Integrated Rate Matching Hub
- `1d6b:0002` Linux Foundation 2.0 root hub
- `8087:0024` Intel Corp. Integrated Rate Matching Hub
- `1d6b:0002` Linux Foundation 2.0 root hub
- `1d6b:0003` Linux Foundation 3.0 root hub
- `1d6b:0002` Linux Foundation 2.0 root hub
- `2109:0811` VIA Labs, Inc. Hub
- `1d6b:0104` Linux Foundation Multifunction Composite Gadget
- `1d6b:0003` Linux Foundation 3.0 root hub

## Disk Identifiers

```
ata-OCZ-VERTEX4_OCZ-VXU63BL632040577
ata-OCZ-VERTEX4_OCZ-VXU63BL632040577-part1
ata-ST8000DM004-2CX188_ZR109DM9
ata-ST8000DM004-2CX188_ZR109DM9-part1
ata-ST8000DM004-2CX188_ZR109DM9-part9
ata-ST8000DM004-2CX188_ZR10RB8J
ata-ST8000DM004-2CX188_ZR10RB8J-part1
ata-ST8000DM004-2CX188_ZR10RB8J-part9
ata-ST8000DM004-2CX188_ZR10RP6D
ata-ST8000DM004-2CX188_ZR10RP6D-part1
ata-ST8000DM004-2CX188_ZR10RP6D-part9
ata-ST8000DM004-2CX188_ZR10TRAD
ata-ST8000DM004-2CX188_ZR10TRAD-part1
ata-ST8000DM004-2CX188_ZR10TRAD-part9
ata-WDC_WDS200T2B0A-00SM50_21085S800292
ata-WDC_WDS200T2B0A-00SM50_21085S800292-part1
ata-WDC_WDS200T2B0A-00SM50_21085S800292-part2
ata-WDC_WDS200T2B0A-00SM50_21085S800292-part3
ata-WDC_WDS200T2B0A-00SM50_21085S800292-part4
ata-WDC_WDS200T2B0A-00SM50_21085S800292-part5
ata-WDC_WDS200T2B0A-00SM50_21085S800292-part6
dm-name-dev-disk-byx2dpartlabel-diskx2dmainx2dswap
dm-uuid-CRYPT-PLAIN-dev-disk-byx2dpartlabel-diskx2dmainx2dswap
scsi-360000000000000000e00000000010001
scsi-360000000000000000e00000000020001
scsi-360000000000000000e00000000030001
usb-JetKVM_Virtual_Media-0:0
wwn-0x5000c500c8d62156
wwn-0x5000c500c8d62156-part1
wwn-0x5000c500c8d62156-part9
wwn-0x5000c500db06a3d1
wwn-0x5000c500db06a3d1-part1
wwn-0x5000c500db06a3d1-part9
wwn-0x5000c500db06f1e2
wwn-0x5000c500db06f1e2-part1
wwn-0x5000c500db06f1e2-part9
wwn-0x5000c500db1f0163
wwn-0x5000c500db1f0163-part1
wwn-0x5000c500db1f0163-part9
wwn-0x5001b448be24504b
wwn-0x5001b448be24504b-part1
wwn-0x5001b448be24504b-part2
wwn-0x5001b448be24504b-part3
wwn-0x5001b448be24504b-part4
wwn-0x5001b448be24504b-part5
wwn-0x5001b448be24504b-part6
wwn-0x5e83a97923abf0ec
wwn-0x5e83a97923abf0ec-part1
wwn-0x60000000000000000e00000000010001
wwn-0x60000000000000000e00000000020001
wwn-0x60000000000000000e00000000030001
```

## Temperature Sensors

- acpitz-acpi-0: temp1 — temp1: 28°C; temp2 — temp2: 30°C
- coretemp-isa-0000: Package id 0 — temp1 crit: 105°C, temp1 crit alarm: 0°C, temp1: 53°C, temp1 max: 85°C; Core 0 — temp2 crit: 105°C, temp2 crit alarm: 0°C, temp2: 50°C, temp2 max: 85°C; Core 1 — temp3 crit: 105°C, temp3 crit alarm: 0°C, temp3: 53°C, temp3 max: 85°C

## Notes




- Primary NAS: 4x 8TB Seagate HDDs in ZFS (likely RAID configuration)
- OS on 2TB WD Blue SSD
- Dual 10GbE SFP+ networking for high-throughput storage access
- K3s agent node
- Longhorn host
- KVM management via JetKVM

