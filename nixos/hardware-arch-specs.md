# Hardware Specs: arch

**Generated:** 2026-05-24T02:16:59Z

## System Overview

| Field | Value |
|---|---|
| Hostname | arch |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.32 x86_64 |
| Motherboard | ASRock Z390 Taichi () |
| Chassis | Desktop |
| BIOS | American Megatrends Inc. P1.20 (08/22/2018) |

## CPU

| Field | Value |
|---|---|
| Model | Intel(R) Core(TM) i9-9900K CPU @ 3.60GHz |
| Architecture | x86_64 |
| Cores | 8 (16 threads, 2 per core) |
| Sockets | 1 |
| Max Frequency | 5.0 GHz (boost) |
| Min Frequency | 800 MHz |
| L1d Cache | 256 KiB (8 instances) |
| L1i Cache | 256 KiB (8 instances) |
| L2 Cache | 2 MiB (8 instances) |
| L3 Cache | 16 MiB (1 instance) |
| Microcode | 0xf8 |
| Virtualization | VT-x |
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 s… |

## Memory

### Summary

| Type | Size |
|---|---|
| RAM | 31Gi |
| Swap | 31Gi |

_No DIMM details available (requires root/dmidecode on x86)_

## Storage

```
sda                                             1.8T disk                            WDC WD20EZRZ-00Z5HB0    1
└─sda1                                          1.8T part  ntfs        /mnt/d                                1
sdb                                             1.8T disk                            PSSD T7                 0
└─sdb1                                          1.8T part  crypto_LUKS                                       0
  └─luks-9340760b-a19d-4392-9021-8f4b14c794f8   1.8T crypt LVM2_member                                       0
    ├─pool1-longhorn                           1200G lvm   ext4        /mnt/longhorn                         0
    └─pool1-ssdext1                             663G lvm   ext4
sdc                                               0B disk                            USB3.0 CRW -SD          0
sdd                                               0B disk                            USB3.0 CRW -SD          0
nvme0n1                                       953.9G disk                            INTEL SSDPEKNW010T8     0
├─nvme0n1p1                                     500G part  LVM2_member                                       0
│ ├─pool1a-john_home                            300G lvm   ext4        /home/john                            0
│ └─pool1a-games_a                              199G lvm   ext4        /mnt/games_a                          0
├─nvme0n1p2                                       3G part  vfat        /boot                                 0
└─nvme0n1p3                                   450.5G part  ext4        /                                     0
nvme1n1                                       953.9G disk                            INTEL SSDPEKNW010T8     0
└─nvme1n1p1                                   953.9G part  LVM2_member                                       0
  ├─pool1b-monero                               350G lvm   ext4        /mnt/monero                           0
  └─pool1b-swap                                  32G lvm   swap        [SWAP]                                0
```

## GPU

- `01:00.0` NVIDIA Corporation GP102 [GeForce GTX 1080 Ti] [10de:1b06] rev a1

## Network

| Device | Interface | Description |
|---|---|---|
| 00:1f.6 | eno1 | Intel Corporation Ethernet Connection (7) I219-V [8086:15bc] rev 10 |
| 05:00.0 | wlp5s0 | Intel Corporation Dual Band Wireless-AC 3168NGW [Stone Peak] [8086:24fb] rev 10 |
| 06:00.0 | enp6s0 | Intel Corporation I211 Gigabit Network Connection [8086:1539] rev 03 |

## PCI Devices

- `00:00.0` Intel Corporation 8th/9th Gen Core 8-core Desktop Processor Host Bridge/DRAM Registers [Coffee Lake S] [8086:3e30] rev 0a
- `00:01.0` Intel Corporation 6th-10th Gen Core Processor PCIe Controller (x16) [8086:1901] rev 0a
- `00:12.0` Intel Corporation Cannon Lake PCH Thermal Controller [8086:a379] rev 10
- `00:14.0` Intel Corporation Cannon Lake PCH USB 3.1 xHCI Host Controller [8086:a36d] rev 10
- `00:14.2` Intel Corporation Cannon Lake PCH Shared SRAM [8086:a36f] rev 10
- `00:16.0` Intel Corporation Cannon Lake PCH HECI Controller [8086:a360] rev 10
- `00:17.0` Intel Corporation Cannon Lake PCH SATA AHCI Controller [8086:a352] rev 10
- `00:1b.0` Intel Corporation Cannon Lake PCH PCI Express Root Port #17 [8086:a340] rev f0
- `00:1c.0` Intel Corporation Cannon Lake PCH PCI Express Root Port #7 [8086:a33e] rev f0
- `00:1d.0` Intel Corporation Cannon Lake PCH PCI Express Root Port #9 [8086:a330] rev f0
- `00:1f.0` Intel Corporation Z390 Chipset LPC/eSPI Controller [8086:a305] rev 10
- `00:1f.3` Intel Corporation Cannon Lake PCH cAVS [8086:a348] rev 10
- `00:1f.4` Intel Corporation Cannon Lake PCH SMBus Controller [8086:a323] rev 10
- `00:1f.5` Intel Corporation Cannon Lake PCH SPI Controller [8086:a324] rev 10
- `00:1f.6` Intel Corporation Ethernet Connection (7) I219-V [8086:15bc] rev 10
- `01:00.0` NVIDIA Corporation GP102 [GeForce GTX 1080 Ti] [10de:1b06] rev a1
- `01:00.1` NVIDIA Corporation GP102 HDMI Audio Controller [10de:10ef] rev a1
- `02:00.0` Intel Corporation SSD 660P Series [8086:f1a8] rev 03
- `03:00.0` ASMedia Technology Inc. ASM1184e 4-Port PCIe x1 Gen2 Packet Switch [1b21:1184]
- `04:01.0` ASMedia Technology Inc. ASM1184e 4-Port PCIe x1 Gen2 Packet Switch [1b21:1184]
- `04:03.0` ASMedia Technology Inc. ASM1184e 4-Port PCIe x1 Gen2 Packet Switch [1b21:1184]
- `04:05.0` ASMedia Technology Inc. ASM1184e 4-Port PCIe x1 Gen2 Packet Switch [1b21:1184]
- `04:07.0` ASMedia Technology Inc. ASM1184e 4-Port PCIe x1 Gen2 Packet Switch [1b21:1184]
- `05:00.0` Intel Corporation Dual Band Wireless-AC 3168NGW [Stone Peak] [8086:24fb] rev 10
- `06:00.0` Intel Corporation I211 Gigabit Network Connection [8086:1539] rev 03
- `08:00.0` ASMedia Technology Inc. ASM1061/ASM1062 Serial ATA Controller [1b21:0612] rev 02
- `09:00.0` Intel Corporation SSD 660P Series [8086:f1a8] rev 03

## USB Devices

- `1d6b:0002` Linux Foundation 2.0 root hub
- `05e3:0608` Genesys Logic, Inc. Hub
- `05e3:0608` Genesys Logic, Inc. Hub
- `1b1c:0c12` Corsair H150i Platinum
- `174c:2074` ASMedia Technology Inc. ASM1074 High-Speed hub
- `1b1c:0c0b` Corsair Lighting Node Pro
- `1b1c:1c06` Corsair
- `30be:100c` Schiit Audio Schiit Modi+
- `046d:c08b` Logitech, Inc. G502 SE HERO Gaming Mouse
- `05e3:0608` Genesys Logic, Inc. Hub
- `08bb:2902` Texas Instruments PCM2902 Audio Codec
- `04d9:a0f8` Holtek Semiconductor, Inc. USB Gaming Keyboard
- `04e8:4001` Samsung Electronics Co., Ltd PSSD T7
- `05e3:0610` Genesys Logic, Inc. Hub
- `0b05:190e` ASUSTek Computer, Inc. ASUS USB-BT500
- `20a0:422d` Clay Logic ps2avrGB
- `045b:0209` Hitachi, Ltd
- `28de:1142` Valve Software Wireless Steam Controller
- `8087:0aa7` Intel Corp. Wireless-AC 3168 Bluetooth
- `045b:0209` Hitachi, Ltd
- `36b0:3035` RDMCTMZT CIDOO QK61
- `05ac:024f` Apple, Inc. Aluminium Keyboard (ANSI)
- `0bda:0306` Realtek Semiconductor Corp. USB3.0 Card Reader
- `05e3:0610` Genesys Logic, Inc. Hub
- `1d6b:0003` Linux Foundation 3.0 root hub
- `05e3:0625` Genesys Logic, Inc. USB3.2 Hub
- `174c:3074` ASMedia Technology Inc. ASM1074 SuperSpeed hub

## Disk Identifiers

```
ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4M2YS41RZ
ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4M2YS41RZ-part1
dm-name-luks-9340760b-a19d-4392-9021-8f4b14c794f8
dm-name-pool1a-games_a
dm-name-pool1a-john_home
dm-name-pool1b-monero
dm-name-pool1b-swap
dm-name-pool1-longhorn
dm-name-pool1-ssdext1
dm-uuid-CRYPT-LUKS2-9340760ba19d439290218f4b14c794f8-luks-9340760b-a19d-4392-9021-8f4b14c794f8
dm-uuid-LVM-dNxSc19lfU7LhZDs3YIIzxXcPijvyqD04RsuuGRR3jZsn8GBfEqSJXiWXAQ1s0dA
dm-uuid-LVM-dNxSc19lfU7LhZDs3YIIzxXcPijvyqD0IfnQdpkFgp8alt3MFnj8cFiRdqtgm8ay
dm-uuid-LVM-udpgOyVkPRr5pheziAPyvVTxd4L9ML6dvrMO8JN1mv6fBewHYRLyDoJeiE0rF3HG
dm-uuid-LVM-XKhWWVWdGUy315MdhGUMhe00uY10NL4yu7azXOxRSInFCdcOS7ACV7kdS14Qj4iq
dm-uuid-LVM-XKhWWVWdGUy315MdhGUMhe00uY10NL4yvWer6M1adFET3E84IJiOv6jpYnW6nXsp
lvm-pv-uuid-QGeK59-3zOU-Ygze-USrw-Eerl-cgCv-CCjLJB
lvm-pv-uuid-rAaEGZ-KjRA-uEdx-KRes-Ka6j-B4Df-IMvo6z
lvm-pv-uuid-TtovES-Ajnz-AbhC-LywS-1JTN-zfOi-vOGSA6
nvme-eui.0000000001000000e4d25c9a846a5001
nvme-eui.0000000001000000e4d25c9a846a5001-part1
nvme-eui.0000000001000000e4d25c9a846a5001-part2
nvme-eui.0000000001000000e4d25c9a846a5001-part3
nvme-eui.0000000001000000e4d25cc756935001
nvme-eui.0000000001000000e4d25cc756935001-part1
nvme-INTEL_SSDPEKNW010T8_BTNH91210JCU1P0B
nvme-INTEL_SSDPEKNW010T8_BTNH91210JCU1P0B_1
nvme-INTEL_SSDPEKNW010T8_BTNH91210JCU1P0B_1-part1
nvme-INTEL_SSDPEKNW010T8_BTNH91210JCU1P0B-part1
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B_1
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B_1-part1
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B_1-part2
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B_1-part3
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B-part1
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B-part2
nvme-INTEL_SSDPEKNW010T8_PHNH852200T11P0B-part3
usb-Generic-_USB3.0_CRW_-SD_201506301013-0:0
usb-Generic-_USB3.0_CRW_-SD_201506301013-0:1
usb-Samsung_PSSD_T7_S7MPNS0X402503Y-0:0
usb-Samsung_PSSD_T7_S7MPNS0X402503Y-0:0-part1
wwn-0x50014ee21032fb24
wwn-0x50014ee21032fb24-part1
```

## Temperature Sensors

- iwlwifi_1-virtual-0: temp1 — temp1: 40°C
- pch_cannonlake-virtual-0: temp1 — temp1: 55°C
- nvme-pci-0200: Composite — temp1 alarm: 0°C, temp1 crit: 80°C, temp1: 36°C, temp1 max: 77°C
- corsairpsu-hid-3-2: v_in — in0: 115.0; v_out +12v — in1 crit: 15.6, in1: 12.2, in1 lcrit: 8.4; v_out +5v — in2 crit: 6.5, in2: 5.0, in2 lcrit: 3.5
- coretemp-isa-0000: Package id 0 — temp1 crit: 115°C, temp1 crit alarm: 0°C, temp1: 64°C, temp1 max: 101°C; Core 0 — temp2 crit: 115°C, temp2 crit alarm: 0°C, temp2: 51°C, temp2 max: 101°C; Core 1 — temp3 crit: 115°C, temp3 crit alarm: 0°C, temp3: 50°C, temp3 max: 101°C
- nvme-pci-0900: Composite — temp1 alarm: 0°C, temp1 crit: 80°C, temp1: 41°C, temp1 max: 77°C

## Notes




- LVM2 volume groups: `pool1a` (on nvme1n1p1), `pool1b` (on nvme0n1p1)
- External storage encrypted with LUKS (Samsung T7)

