# Hardware Specs: aman

**Generated:** 2026-05-06T05:58:26Z

## System Overview

| Field | Value |
|---|---|
| Hostname | aman |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.24 aarch64 |
| Platform | Likely Raspberry Pi 4 Model B (4GB variant) |

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
| mmcblk0 | 238 GB | SD Card (ID: SD256_0xdebacbba) | | |
| mmcblk0p1 | 30 MB | partition | vfat | (boot) |
| mmcblk0p2 | 238 GB | partition | ext4 | / |

## GPU

**VideoCore VI** (integrated in BCM2711)

## Network

- Gigabit Ethernet (onboard BCM54213PE)
- WiFi (onboard)

## USB

- Bus 001: USB 2.0 (VIA Labs hub)
- Bus 002: USB 3.0 root hub

## Notes

- Mullvad VPN exit node (offers exit node on Tailscale)
- Avahi reflector enabled
- Tailscale connected
- No DMI data (ARM platform)
