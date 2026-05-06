# Hardware Specs: secu

**Generated:** 2026-05-06T05:59:01Z

## System Overview

| Field | Value |
|---|---|
| Hostname | secu |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.23 x86_64 |
| Model | HP EliteDesk 800 G3 DM 35W |
| Chassis | Mini Desktop (Ultra Small Form Factor) |
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
| Virtualization | VT-x |
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb pti ssbd ibrs ibpb stibp tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid mpx rdseed adx smap clflushopt intel_pt xsaveopt xsavec xgetbv1 xsaves dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp vnmi md_clear flush_l1d arch_capabilities |

## Memory

| Type | Size |
|---|---|
| RAM | 7.6 GiB |
| Swap | 8 GiB (LUKS encrypted on sda2) |

## Storage

| Device | Size | Type | Model | Filesystem | Mount |
|---|---|---|---|---|---|
| sda | 111.8 GB | SATA SSD | WDC WDS120G2G0A-00JH30 (120GB) | | |
| sda1 | 4 GB | partition | | vfat | /boot |
| sda2 | 8 GB | partition (LUKS) | | swap | [SWAP] |
| sda3 | 99.8 GB | partition (LUKS) | | btrfs (cryptroot) | /home/john/.snapshots |
| sdb | 7.6 GB | USB | PNY USB 2.0 FD | | (removable) |

## GPU

| Device | Description |
|---|---|
| 00:02.0 | Intel Skylake-S GT2 [HD Graphics 530] [8086:1912] rev 06 (integrated) |

## Network

| Device | Interface | Description |
|---|---|---|
| 00:1f.6 | (eno1) | Intel I219-LM Ethernet Connection (5) [8086:15e3] |

## PCI Devices

- `00:00.0` Intel Xeon E3-1200 v5 / 6th Gen Core Host Bridge
- `00:02.0` Intel HD Graphics 530 (integrated)
- `00:14.0` Intel 200 Series USB 3.0 xHCI
- `00:17.0` Intel 200 Series SATA AHCI
- `00:1f.0` Intel Q270 LPC Controller
- `00:1f.3` Intel 200 Series HD Audio
- `00:1f.6` Intel I219-LM Gigabit Ethernet

## Notes

- Full disk encryption (LUKS on sda3 for root, LUKS on sda2 for swap)
- Btrfs root with snapshots
- HP business-class mini PC (DM = Desktop Mini)
- No WiFi (wired Ethernet only)
