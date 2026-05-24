# Hardware Specs: pite

**Generated:** 2026-05-24T02:16:59Z

## System Overview

| Field | Value |
|---|---|
| Hostname | pite |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.22 aarch64 |
| Motherboard |   () |
| Chassis | Desktop |
| BIOS |   () |

## CPU

| Field | Value |
|---|---|
| Model | Cortex-A72 |
| Architecture | aarch64 |
| Cores | 4 (4 threads) |
| Max Frequency | 1.5 GHz (boost) |
| Min Frequency | 600 MHz |
| L1d Cache | 128 KiB (4 instances) |
| L1i Cache | 192 KiB (4 instances) |
| L2 Cache | 1 MiB (1 instance) |
| Flags | fp asimd evtstrm crc32 cpuid… |

## Memory

### Summary

| Type | Size |
|---|---|
| RAM | 1.8Gi |
| Swap | 8.0Gi |

_No DIMM details available (requires root/dmidecode on x86)_

## Storage

```
sudo: dmidecode: command not found
mmcblk0     238.3G disk                            0
├─mmcblk0p1    30M part vfat                       0
└─mmcblk0p2 238.3G part ext4   /                   0
```

## PCI Devices

- `00:00.0` Broadcom Inc. and subsidiaries BCM2711 PCIe Bridge [14e4:2711] rev 10
- `01:00.0` VIA Technologies, Inc. VL805/806 xHCI USB 3.0 Controller [1106:3483] rev 01

## USB Devices

- `1d6b:0002` Linux Foundation 2.0 root hub
- `2109:3431` VIA Labs, Inc. Hub
- `1d6b:0003` Linux Foundation 3.0 root hub

## Disk Identifiers

```
mmc-SN256_0x71e4d1d0
mmc-SN256_0x71e4d1d0-part1
mmc-SN256_0x71e4d1d0-part2
```

## Temperature Sensors

- cpu_thermal-virtual-0: temp1 — temp1: 80°C
- rpi_volt-isa-0000: in0 — in0 lcrit alarm: 0.0

## Notes




- K3s agent node
- Tailscale connected
- No DMI data available (ARM platform)

