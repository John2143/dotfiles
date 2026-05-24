# Hardware Specs: secu

**Generated:** 2026-05-24T02:16:59Z

## System Overview

| Field | Value |
|---|---|
| Hostname | secu |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.28 x86_64 |
| Motherboard | HP 829A (KBC Version 06.29) |
| Chassis | HP EliteDesk 800 G3 DM 35W (Desktop Mini / USFF) |
| BIOS | HP P21 Ver. 02.50 (07/14/2024) |

## CPU

| Field | Value |
|---|---|
| Model | Intel(R) Core(TM) i5-6500T CPU @ 2.50GHz |
| Architecture | x86_64 |
| Cores | 4 (4 threads, 1 per core) |
| Sockets | 1 |
| Max Frequency | 3.1 GHz (boost) |
| Min Frequency | 800 MHz |
| L1d Cache | 128 KiB (4 instances) |
| L1i Cache | 128 KiB (4 instances) |
| L2 Cache | 1 MiB (4 instances) |
| L3 Cache | 6 MiB (1 instance) |
| Microcode | 0xf0 |
| Virtualization | VT-x |
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 s… |

## Memory

### Summary

| Type | Size |
|---|---|
| RAM | 7.6Gi |
| Swap | 8.0Gi |

_No DIMM details available (requires root/dmidecode on x86)_

## Storage

```
sda                                            111.8G disk                                    WDC WDS120G2G0A-00JH30    0
├─sda1                                             4G part  vfat        /boot                                           0
├─sda2                                             8G part                                                              0
│ └─dev-disk-byx2dpartlabel-diskx2dmainx2dswap     8G crypt swap        [SWAP]                                          0
└─sda3                                          99.8G part  crypto_LUKS                                                 0
  └─cryptroot                                   99.8G crypt btrfs       /home/john/.snapshots                           0
sdb                                              7.6G disk                                    USB 2.0 FD                1
└─sdb1                                             3M part                                                              1
```

## GPU

- `00:02.0` Intel Corporation Skylake-S GT2 [HD Graphics 530] [8086:1912] rev 06

## Network

| Device | Interface | Description |
|---|---|---|
| 00:1f.6 | eno1 | Intel Corporation Ethernet Connection (5) I219-LM [8086:15e3] |

## PCI Devices

- `00:00.0` Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor Host Bridge/DRAM Registers [8086:191f] rev 07
- `00:02.0` Intel Corporation Skylake-S GT2 [HD Graphics 530] [8086:1912] rev 06
- `00:14.0` Intel Corporation 200 Series/Z370 Chipset Family USB 3.0 xHCI Controller [8086:a2af]
- `00:14.2` Intel Corporation 200 Series PCH Thermal Subsystem [8086:a2b1]
- `00:16.0` Intel Corporation 200 Series PCH CSME HECI #1 [8086:a2ba]
- `00:16.3` Intel Corporation 200 Series Chipset Family KT Redirection [8086:a2bd]
- `00:17.0` Intel Corporation 200 Series PCH SATA controller [AHCI mode] [8086:a282]
- `00:1f.0` Intel Corporation 200 Series PCH LPC Controller (Q270) [8086:a2c6]
- `00:1f.2` Intel Corporation 200 Series/Z370 Chipset Family Power Management Controller [8086:a2a1]
- `00:1f.3` Intel Corporation 200 Series PCH HD Audio [8086:a2f0]
- `00:1f.4` Intel Corporation 200 Series/Z370 Chipset Family SMBus Controller [8086:a2a3]
- `00:1f.6` Intel Corporation Ethernet Connection (5) I219-LM [8086:15e3]

## USB Devices

- `1d6b:0002` Linux Foundation 2.0 root hub
- `10c4:ea60` Silicon Labs CP210x UART Bridge
- `046d:c52b` Logitech, Inc. Unifying Receiver
- `154b:007a` PNY Classic Attache Flash Drive
- `1d6b:0003` Linux Foundation 3.0 root hub
- `0bda:b812` Realtek Semiconductor Corp. RTL88x2bu [AC1200 Techkey]

## Disk Identifiers

```
ata-WDC_WDS120G2G0A-00JH30_210239448605
ata-WDC_WDS120G2G0A-00JH30_210239448605-part1
ata-WDC_WDS120G2G0A-00JH30_210239448605-part2
ata-WDC_WDS120G2G0A-00JH30_210239448605-part3
dm-name-cryptroot
dm-name-dev-disk-byx2dpartlabel-diskx2dmainx2dswap
dm-uuid-CRYPT-LUKS2-3e38850195d14433902ac1ac168781aa-cryptroot
dm-uuid-CRYPT-PLAIN-dev-disk-byx2dpartlabel-diskx2dmainx2dswap
usb-PNY_USB_2.0_FD_AE26HE03000001011-0:0
usb-PNY_USB_2.0_FD_AE26HE03000001011-0:0-part1
wwn-0x5001b444a7c8b68b
wwn-0x5001b444a7c8b68b-part1
wwn-0x5001b444a7c8b68b-part2
wwn-0x5001b444a7c8b68b-part3
```

## Temperature Sensors

- coretemp-isa-0000: Package id 0 — temp1 crit: 100°C, temp1 crit alarm: 0°C, temp1: 58°C, temp1 max: 84°C; Core 0 — temp2 crit: 100°C, temp2 crit alarm: 0°C, temp2: 56°C, temp2 max: 84°C; Core 1 — temp3 crit: 100°C, temp3 crit alarm: 0°C, temp3: 58°C, temp3 max: 84°C

## Notes




- Full disk encryption (LUKS on sda3 for root, LUKS on sda2 for swap)
- Btrfs root with snapshots
- HP business-class mini PC (DM = Desktop Mini)
- No WiFi (wired Ethernet only)

