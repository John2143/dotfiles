# Hardware Specs: vpin

**Generated:** 2026-05-06T05:59:01Z

## System Overview

| Field | Value |
|---|---|
| Hostname | vpin |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.24 aarch64 |
| Platform | Likely Raspberry Pi 3 Model B (or B+) |

## CPU

| Field | Value |
|---|---|
| Model | ARM Cortex-A72 |
| Architecture | aarch64 |
| Cores | 4 (1 thread per core) |
| Clusters | 1 (4 cores per cluster) |
| Max Frequency | 1.5 GHz |
| Min Frequency | 600 MHz |
| L1d Cache | 128 KiB (4 instances) |
| L1i Cache | 192 KiB (4 instances) |
| L2 Cache | 1 MiB (1 instance) |
| Stepping | r0p3 |
| Flags | fp asimd evtstrm crc32 cpuid |

## Memory

| Type | Size |
|---|---|
| RAM | 3.7 GiB |
| Swap | None |

## Storage

| Device | Size | Type | Filesystem | Mount |
|---|---|---|---|---|
| mmcblk0 | 59.5 GB | SD Card (ID: SC64G_0xaf7e42fa) | | |
| mmcblk0p1 | 30 MB | partition | vfat | (boot) |
| mmcblk0p2 | 59.4 GB | partition | ext4 | / |

## GPU

**VideoCore IV** or **VideoCore VI** (integrated)

## Network

- Gigabit Ethernet (onboard)
- WiFi (onboard)

## USB

- Bus 001: USB 2.0 (VIA Labs hub)
- Bus 002: USB 3.0 root hub

## Notes

- Mullvad VPN exit node (offers exit node on Tailscale)
- Tailscale connected
- 64GB SD card (smaller than the 238GB cards on pite/aman)
- No DMI data (ARM platform)
