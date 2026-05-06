# Hardware Specs: nas

**Generated:** 2026-05-06T05:59:01Z

## System Overview

| Field | Value |
|---|---|
| Hostname | nas |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.26 x86_64 |
| Motherboard | Gigabyte Z77X-UD3H |
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
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx rdtscp lm constant_tsc arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx est tm2 ssse3 cx16 xtpr pdcm pcid sse4_1 sse4_2 popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm cpuid_fault epb pti ssbd ibrs ibpb stibp tpr_shadow flexpriority ept vpid fsgsbase smep erms xsaveopt dtherm ida arat pln pts vnmi md_clear flush_l1d |

## Memory

| Type | Size |
|---|---|
| RAM | 15 GiB |
| Swap | 16 GiB (LUKS encrypted on sdc3) |

## Storage

### OS Drive

| Device | Size | Type | Model | Filesystem | Mount |
|---|---|---|---|---|---|
| sdc | 1.8 TB | SATA SSD | WDC WDS200T2B0A-00SM50 (2TB) | | |
| sdc1 | 4 GB | partition | | vfat | /boot |
| sdc2 | 1 TB | partition | | ext4 | / |
| sdc3 | 16 GB | partition (LUKS) | | swap | [SWAP] |
| sdc4 | 100 GB | partition | | zfs_member | (ZFS) |
| sdc5 | 200 GB | partition | | zfs_member | (ZFS) |
| sdc6 | 519 GB | partition | | zfs_member | (ZFS) |

### Storage Pool

| Device | Size | Type | Model | Filesystem |
|---|---|---|---|---|
| sda | 7.3 TB | SATA HDD | Seagate ST8000DM004-2CX188 | zfs_member |
| sdd | 7.3 TB | SATA HDD | Seagate ST8000DM004-2CX188 | zfs_member |
| sde | 7.3 TB | SATA HDD | Seagate ST8000DM004-2CX188 | zfs_member |
| sdf | 7.3 TB | SATA HDD | Seagate ST8000DM004-2CX188 | zfs_member |

### Cache / Scratch

| Device | Size | Type | Model | Filesystem |
|---|---|---|---|---|
| sdb | 119.2 GB | SATA SSD | OCZ-VERTEX4 | zfs_member |

### Other

| Device | Size | Type | Model |
|---|---|---|---|
| sr0 | 1024 MB | Virtual Media | Virtual Media (IPMI/KVM) |

## GPU

| Device | Description |
|---|---|
| 00:02.0 | Intel IvyBridge GT2 [HD Graphics 4000] [8086:0162] rev 09 (integrated) |

## Network

| Device | Interface | Description |
|---|---|---|
| 01:00.0 | enp1s0f0 | Intel 82599ES 10-Gigabit SFI/SFP+ [8086:10fb] rev 01 |
| 01:00.1 | enp1s0f1 | Intel 82599ES 10-Gigabit SFI/SFP+ [8086:10fb] rev 01 |
| 06:00.0 | enp6s0 | Qualcomm Atheros AR8161 Gigabit Ethernet [1969:1091] rev 10 |

## PCI Devices

- `00:00.0` Intel Xeon E3-1200 v2 / 3rd Gen Core DRAM Controller
- `00:01.0` PCI Express Root Port
- `00:02.0` Intel HD Graphics 4000
- `00:14.0` Intel 7 Series USB xHCI
- `00:1b.0` Intel 7 Series HD Audio
- `00:1f.0` Intel Z77 Express LPC
- `00:1f.2` Intel 7 Series SATA AHCI (6-port)
- `01:00.0/1` Intel 82599ES Dual 10GbE SFP+
- `03:00.0` VIA VL800/801 USB 3.0 Controller
- `06:00.0` Qualcomm Atheros AR8161 Gigabit Ethernet
- `07:00.0` Marvell 88SE9172 SATA 6Gb/s Controller

## USB / KVM

- JetKVM USB Emulation Device (KVM-over-IP)

## Notes

- Primary NAS: 4x 8TB Seagate HDDs in ZFS (likely RAID configuration)
- OS on 2TB WD Blue SSD
- Dual 10GbE SFP+ networking for high-throughput storage access
- K3s agent node
- Longhorn host
- KVM management via JetKVM
