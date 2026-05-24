# Hardware Specs: office

**Generated:** 2026-05-24T02:16:59Z

## System Overview

| Field | Value |
|---|---|
| Hostname | office |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.31 x86_64 |
| Motherboard | ASUSTeK COMPUTER INC. TUF GAMING B760M-PLUS WIFI (Rev 1.xx) |
| Chassis | Desktop |
| BIOS | American Megatrends Inc. 1656 (04/18/2024) |

## CPU

| Field | Value |
|---|---|
| Model | Intel(R) Core(TM) i9-14900K |
| Architecture | x86_64 |
| Cores | 23 (32 threads, 2 per core) |
| Sockets | 1 |
| Max Frequency | 6.0 GHz (boost) |
| Min Frequency | 800 MHz |
| L1d Cache | 848 KiB (23 instances) |
| L1i Cache | 1.2 MiB (23 instances) |
| L2 Cache | 30 MiB (11 instances) |
| L3 Cache | 36 MiB (1 instance) |
| Microcode | 0x133 |
| Virtualization | VT-x |
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx smx … |

## Memory

### Summary

| Type | Size |
|---|---|
| RAM | 62Gi |
| Swap | 31Gi |

_No DIMM details available (requires root/dmidecode on x86)_

## Storage

```
sudo: dmidecode: command not found
sda         7.6G disk iso9660                                            USB 2.0 FD                 1
├─sda1      2.2G part iso9660 /run/media/john/nixos-minimal-26.05-x86_64                            1
└─sda2        3M part vfat                                                                          1
nvme0n1     1.8T disk                                                    Samsung SSD 980 PRO 2TB    0
├─nvme0n1p1   1G part vfat    /boot                                                                 0
├─nvme0n1p2  32G part swap    [SWAP]                                                                0
├─nvme0n1p3 500G part ext4    /                                                                     0
├─nvme0n1p6 500G part ext4    /mnt/arch                                                             0
└─nvme0n1p7 798G part ext4    /mnt/share                                                            0
```

## GPU

- `03:00.0` Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M] [1002:744c] rev c8

## Network

| Device | Interface | Description |
|---|---|---|
| 00:14.3 | wlp0s20f3 | Intel Corporation 700 Series Chipset CNVi WiFi [8086:7a70] rev 11 |
| 07:00.0 | eno1 | Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] rev 05 |

## PCI Devices

- `00:00.0` Intel Corporation Raptor Lake-S Host Bridge/DRAM Controller [8086:a700] rev 01
- `00:01.0` Intel Corporation Raptor Lake PCI Express 5.0 Graphics Port (PEG010) [8086:a70d] rev 01
- `00:06.0` Intel Corporation Raptor Lake PCI Express 4.0 Graphics Port [8086:a74d] rev 01
- `00:0a.0` Intel Corporation Raptor Lake Crashlog and Telemetry [8086:a77d] rev 01
- `00:0e.0` Intel Corporation RST Volume Management Device Controller [8086:a77f]
- `00:14.0` Intel Corporation Raptor Lake USB 3.2 Gen 2x2 (20 Gb/s) XHCI Host Controller [8086:7a60] rev 11
- `00:14.2` Intel Corporation Raptor Lake PCH Shared SRAM [8086:7a27] rev 11
- `00:14.3` Intel Corporation 700 Series Chipset CNVi WiFi [8086:7a70] rev 11
- `00:15.0` Intel Corporation Raptor Lake Serial IO I2C Host Controller #0 [8086:7a4c] rev 11
- `00:15.1` Intel Corporation Raptor Lake Serial IO I2C Host Controller #1 [8086:7a4d] rev 11
- `00:15.2` Intel Corporation Raptor Lake Serial IO I2C Host Controller #2 [8086:7a4e] rev 11
- `00:16.0` Intel Corporation Raptor Lake CSME HECI #1 [8086:7a68] rev 11
- `00:17.0` Intel Corporation Raptor Lake SATA AHCI Controller [8086:7a62] rev 11
- `00:1a.0` Intel Corporation Raptor Lake PCI Express Root Port #25 [8086:7a48] rev 11
- `00:1c.0` Intel Corporation Raptor Lake PCI Express Root Port #1 [8086:7a38] rev 11
- `00:1c.2` Intel Corporation Raptor Lake PCI Express Root Port #3 [8086:7a3a] rev 11
- `00:1d.0` Intel Corporation Raptor Lake PCI Express Root Port #15 [8086:7a36] rev 11
- `00:1f.0` Intel Corporation B760 Chipset LPC/eSPI Controller [8086:7a06] rev 11
- `00:1f.3` Intel Corporation Raptor Lake High Definition Audio Controller [8086:7a50] rev 11
- `00:1f.4` Intel Corporation 700 Series Chipset SMBus Controller [8086:7a23] rev 11
- `00:1f.5` Intel Corporation Raptor Lake SPI (flash) Controller [8086:7a24] rev 11
- `01:00.0` Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] rev 10
- `02:00.0` Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479] rev 10
- `03:00.0` Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M] [1002:744c] rev c8
- `03:00.1` Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 HDMI/DP Audio [1002:ab30]
- `04:00.0` Samsung Electronics Co Ltd NVMe SSD Controller PM9A1/PM9A3/980PRO [144d:a80a]
- `06:00.0` ASMedia Technology Inc. ASM2142/ASM3142 USB 3.1 Host Controller [1b21:2142]
- `07:00.0` Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] rev 05

## USB Devices

- `1d6b:0002` Linux Foundation 2.0 root hub
- `0b05:19af` ASUSTek Computer, Inc. AURA LED Controller
- `1235:8219` Focusrite-Novation Scarlett 2i2 4th Gen
- `342d:e4c5` Hangsheng MonsGeek Keyboard
- `174c:2074` ASMedia Technology Inc. ASM1074 High-Speed hub
- `8087:0026` Intel Corp. AX201 Bluetooth
- `154b:007a` PNY Classic Attache Flash Drive
- `28de:1142` Valve Software Wireless Steam Controller
- `046d:c547` Logitech, Inc. USB Receiver
- `1d6b:0003` Linux Foundation 3.0 root hub
- `174c:3074` ASMedia Technology Inc. ASM1074 SuperSpeed hub
- `1d6b:0002` Linux Foundation 2.0 root hub
- `1d6b:0003` Linux Foundation 3.0 root hub

## Disk Identifiers

```
nvme-eui.002538b931a3e302
nvme-eui.002538b931a3e302-part1
nvme-eui.002538b931a3e302-part2
nvme-eui.002538b931a3e302-part3
nvme-eui.002538b931a3e302-part6
nvme-eui.002538b931a3e302-part7
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F_1
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F_1-part1
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F_1-part2
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F_1-part3
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F_1-part6
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F_1-part7
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F-part1
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F-part2
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F-part3
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F-part6
nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F-part7
usb-PNY_USB_2.0_FD_ADB0HE03000000002-0:0
usb-PNY_USB_2.0_FD_ADB0HE03000000002-0:0-part1
usb-PNY_USB_2.0_FD_ADB0HE03000000002-0:0-part2
```

## Temperature Sensors

- iwlwifi_1-virtual-0: temp1 — temp1: 68°C
- spd5118-i2c-10-53: temp1 — temp1 crit: 85°C, temp1 crit alarm: 0°C, temp1: 42°C, temp1 lcrit: 0°C
- acpitz-acpi-0: temp1 — temp1: 28°C
- nvme-pci-0400: Composite — temp1 alarm: 0°C, temp1 crit: 85°C, temp1: 58°C, temp1 max: 82°C; Sensor 1 — temp2: 58°C, temp2 max: 65262°C, temp2 min: -273°C; Sensor 2 — temp3: 71°C, temp3 max: 65262°C, temp3 min: -273°C
- coretemp-isa-0000: Package id 0 — temp1 crit: 100°C, temp1 crit alarm: 0°C, temp1: 88°C, temp1 max: 80°C; Core 0 — temp2 crit: 100°C, temp2 crit alarm: 0°C, temp2: 55°C, temp2 max: 80°C; Core 4 — temp6 crit: 100°C, temp6 crit alarm: 0°C, temp6: 60°C, temp6 max: 80°C
- spd5118-i2c-10-51: temp1 — temp1 crit: 85°C, temp1 crit alarm: 0°C, temp1: 44°C, temp1 lcrit: 0°C
- amdgpu-pci-0300: vddgfx — in0: 0.4; fan1 — fan1: 574.0, fan1 max: 3600.0, fan1 min: 0.0; edge — temp1 crit: 100°C, temp1 crit hyst: -273°C, temp1 emergency: 105°C, temp1: 49°C

