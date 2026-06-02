# Hardware Specs: closet

**Generated:** 2026-06-02T21:20:39Z

## System Overview

| Field | Value |
|---|---|
| Hostname | closet |
| OS | NixOS 26.11 (Zokor) |
| Kernel | 6.18.33 x86_64 |
| Motherboard | ASUSTeK COMPUTER INC. PRIME A320M-K (Rev X.0x) |
| Chassis | Desktop |
| BIOS | American Megatrends Inc. 4207 (12/07/2018) |

## CPU

| Field | Value |
|---|---|
| Model | AMD Ryzen 5 1600 Six-Core Processor |
| Architecture | x86_64 |
| Cores | 6 (12 threads, 2 per core) |
| Sockets | 1 |
| Max Frequency | 3.2 GHz (boost) |
| Min Frequency | 1550 MHz |
| L1d Cache | 192 KiB (6 instances) |
| L1i Cache | 384 KiB (6 instances) |
| L2 Cache | 3 MiB (6 instances) |
| L3 Cache | 16 MiB (2 instances) |
| Microcode | 0x8001137 |
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16… |

## Memory

### Summary

| Type | Size |
|---|---|
| RAM | 7.7Gi |
| Swap | 8.0Gi |

### DIMM Details

| Slot | Size | Type | Speed | Manufacturer | Part Number |
|---|---|---|---|---|---|
| DIMM_A1 | 8 GiB | DDR4 | 2400 MT/s (configured: 1200 MT/s) | CRUCIAL | BLS8G4D32AESBK.M8FE1 |

## Storage

```
sda           3.6T disk                                                                                                                                            CT4000X9SSD9    1
└─sda1        3.6T part ext4   /mnt                                                                                                                                                1
sdb           9.3G disk ext4   /var/lib/kubelet/pods/c3b9782d-9fff-44c4-a27c-888b1408dbfa/volumes/kubernetes.io~csi/pvc-374214a1-74f2-4143-8c88-3bedafa66f0b/mount VIRTUAL-DISK    1
sdc             5G disk ext4                                                                                                                                       VIRTUAL-DISK    1
sdd           4.7G disk ext4   /var/lib/kubelet/pods/1cfcdbb7-ab54-4b02-8afc-383eff11c970/volumes/kubernetes.io~csi/pvc-a71a966d-8ce7-4b3a-9341-5fe0467f2e6d/mount VIRTUAL-DISK    1
sde           9.3G disk ext4   /var/lib/kubelet/pods/d08289be-86a6-4401-ae00-ee9c2af0141a/volumes/kubernetes.io~csi/pvc-f06012f1-ffff-4279-9905-144359eb15cc/mount VIRTUAL-DISK    1
sdf             1G disk ext4   /var/lib/kubelet/pods/b9f61351-72f9-4615-bb6b-4d898ae0b1a6/volumes/kubernetes.io~csi/pvc-d6926bd9-5fd6-4100-a601-85f675f90e23/mount VIRTUAL-DISK    1
nvme0n1     238.5G disk                                                                                                                                            PCIe SSD        0
├─nvme0n1p1     2G part vfat   /boot                                                                                                                                               0
└─nvme0n1p2 236.5G part ext4   /                                                                                                                                                   0
```

## Network

| Device | Interface | Description |
|---|---|---|
| 06:00.0 | enp6s0 | Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] rev 15 |
| 08:00.0 | enp8s0f0 | Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01 |
| 08:00.1 | enp8s0f1 | Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01 |

## PCI Devices

- `00:00.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Root Complex [1022:1450]
- `00:00.2` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) I/O Memory Management Unit [1022:1451]
- `00:01.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-1fh) PCIe Dummy Host Bridge [1022:1452]
- `00:01.1` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) PCIe GPP Bridge [1022:1453]
- `00:01.3` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) PCIe GPP Bridge [1022:1453]
- `00:02.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-1fh) PCIe Dummy Host Bridge [1022:1452]
- `00:03.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-1fh) PCIe Dummy Host Bridge [1022:1452]
- `00:03.1` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) PCIe GPP Bridge [1022:1453]
- `00:04.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-1fh) PCIe Dummy Host Bridge [1022:1452]
- `00:07.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-1fh) PCIe Dummy Host Bridge [1022:1452]
- `00:07.1` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Internal PCIe GPP Bridge 0 to Bus B [1022:1454]
- `00:08.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-1fh) PCIe Dummy Host Bridge [1022:1452]
- `00:08.1` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Internal PCIe GPP Bridge 0 to Bus B [1022:1454]
- `00:14.0` Advanced Micro Devices, Inc. [AMD] FCH SMBus Controller [1022:790b] rev 59
- `00:14.3` Advanced Micro Devices, Inc. [AMD] FCH LPC Bridge [1022:790e] rev 51
- `00:18.0` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 0 [1022:1460]
- `00:18.1` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 1 [1022:1461]
- `00:18.2` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 2 [1022:1462]
- `00:18.3` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 3 [1022:1463]
- `00:18.4` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 4 [1022:1464]
- `00:18.5` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 5 [1022:1465]
- `00:18.6` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 6 [1022:1466]
- `00:18.7` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Data Fabric: Device 18h; Function 7 [1022:1467]
- `01:00.0` Phison Electronics Corporation E12 NVMe Controller [1987:5012] rev 01
- `02:00.0` Advanced Micro Devices, Inc. [AMD] A320 USB 3.1 XHCI Host Controller [1022:43bc] rev 02
- `02:00.1` Advanced Micro Devices, Inc. [AMD] A320 Chipset SATA Controller [AHCI mode] [1022:43b8] rev 02
- `02:00.2` Advanced Micro Devices, Inc. [AMD] Device [1022:43b3] rev 02
- `03:04.0` Advanced Micro Devices, Inc. [AMD] 300 Series Chipset PCIe Port [1022:43b4] rev 02
- `03:05.0` Advanced Micro Devices, Inc. [AMD] 300 Series Chipset PCIe Port [1022:43b4] rev 02
- `03:06.0` Advanced Micro Devices, Inc. [AMD] 300 Series Chipset PCIe Port [1022:43b4] rev 02
- `03:07.0` Advanced Micro Devices, Inc. [AMD] 300 Series Chipset PCIe Port [1022:43b4] rev 02
- `06:00.0` Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] rev 15
- `08:00.0` Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01
- `08:00.1` Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection [8086:10fb] rev 01
- `09:00.0` Advanced Micro Devices, Inc. [AMD] Zeppelin/Raven/Raven2 PCIe Dummy Function [1022:145a]
- `09:00.2` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) Platform Security Processor (PSP) 3.0 Device [1022:1456]
- `09:00.3` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) USB 3.0 Host Controller [1022:145c]
- `0a:00.0` Advanced Micro Devices, Inc. [AMD] Zeppelin/Renoir PCIe Dummy Function [1022:1455]
- `0a:00.2` Advanced Micro Devices, Inc. [AMD] FCH SATA Controller [AHCI mode] [1022:7901] rev 51
- `0a:00.3` Advanced Micro Devices, Inc. [AMD] Family 17h (Models 00h-0fh) HD Audio Controller [1022:1457]

## USB Devices

- `1d6b:0002` Linux Foundation 2.0 root hub
- `10c4:ea60` Silicon Labs CP210x UART Bridge
- `1d6b:0003` Linux Foundation 3.0 root hub
- `1d6b:0002` Linux Foundation 2.0 root hub
- `051d:0002` American Power Conversion Uninterruptible Power Supply
- `0a12:0001` Cambridge Silicon Radio, Ltd Bluetooth Dongle (HCI mode)
- `1d6b:0003` Linux Foundation 3.0 root hub
- `0634:5605` Micron Technology, Inc. CT4000X9SSD9

## Disk Identifiers

```
nvme-nvme.1987-3139303831343235363033313134-5043496520535344-00000001
nvme-nvme.1987-3139303831343235363033313134-5043496520535344-00000001-part1
nvme-nvme.1987-3139303831343235363033313134-5043496520535344-00000001-part2
nvme-PCIe_SSD_19081425603114
nvme-PCIe_SSD_19081425603114_1
nvme-PCIe_SSD_19081425603114_1-part1
nvme-PCIe_SSD_19081425603114_1-part2
nvme-PCIe_SSD_19081425603114-part1
nvme-PCIe_SSD_19081425603114-part2
scsi-360000000000000000e00000000010001
ps-360000000000000000e00000000020001
jh-360000000000000000e00000000030001
wb-360000000000000000e00000000040001
oq-360000000000000000e00000000050001
usb-Micron_CT4000X9SSD9_2428E8DB8E58-0:0
usb-Micron_CT4000X9SSD9_2428E8DB8E58-0:0-part1
wwn-0x60000000000000000e00000000010001
wwn-0x60000000000000000e00000000020001
wwn-0x60000000000000000e00000000030001
wwn-0x60000000000000000e00000000040001
wwn-0x60000000000000000e00000000050001
```

## Temperature Sensors

- nvme-pci-0100: Composite — temp1 alarm: 0°C, temp1 crit: 90°C, temp1: 49°C, temp1 max: 70°C
- k10temp-pci-00c3: Tctl — temp1: 35°C

## UPS

| Field | Value |
|---|---|
| Model | APC Back-UPS ES 600M1 |
| Serial | 0B2604L25761 |
| Firmware | 928.a11 .D USB FW:a |
| Battery date | 2026-01-22 |
| Nominal power | 330W |
| Input voltage | 119V |
| Load | 25% (~82W) |
| Battery charge | 98% |
| Runtime remaining | ~29 min |
| Connection | USB (051d:0002) |
| Software | apcupsd 3.14.14 (standalone) |
| Shutdown thresholds | BATTERYLEVEL 10%, MINUTES 5 |

## Notes

- This machine is a K3s node (longhorn host)
- The 4TB storage is an external USB Crucial X9 SSD (CT4000X9SSD9)
- 10GbE Intel 82599ES dual-port SFP+ add-in card installed at `08:00.0` / `08:00.1`
- RAM: one 8 GiB DDR4-2400 stick in DIMM_A1 (Crucial Ballistix BLS8G4D32AESBK.M8FE1); DIMM_B1 empty
- Swap configured (8.0 GiB, on disk via Longhorn volumes)
