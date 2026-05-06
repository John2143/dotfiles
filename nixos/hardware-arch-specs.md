# Hardware Specs: arch

**Generated:** 2026-05-06T05:59:01Z

## System Overview

| Field | Value |
|---|---|
| Hostname | arch |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.24 x86_64 |
| Motherboard | ASRock Z390 Taichi |
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
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb ssbd ibrs ibpb stibp tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid mpx rdseed adx smap clflushopt intel_pt xsaveopt xsavec xgetbv1 xsaves dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp vnmi md_clear flush_l1d arch_capabilities |

## Memory

| Type | Size |
|---|---|
| RAM | 31 GiB |
| Swap | 32 GiB (LVM pool1b-swap on nvme0n1) |

## Storage

| Device | Size | Type | Model | Filesystem | Mount |
|---|---|---|---|---|---|
| nvme0n1 | 953.9 GB | NVMe | Intel SSDPEKNW010T8 (660p 1TB) | LVM | |
| nvme0n1p1 | 953.9 GB | partition | | LVM2_member | |
| pool1b-monero (LVM) | 350 GB | lvm | | ext4 | /mnt/monero |
| pool1b-swap (LVM) | 32 GB | lvm | | swap | [SWAP] |
| nvme1n1 | 953.9 GB | NVMe | Intel SSDPEKNW010T8 (660p 1TB) | | |
| nvme1n1p1 | 500 GB | partition | | LVM2_member | |
| pool1a-john_home (LVM) | 300 GB | lvm | | ext4 | /home/john |
| pool1a-games_a (LVM) | 199 GB | lvm | | ext4 | /mnt/games_a |
| nvme1n1p2 | 3 GB | partition | | vfat | /boot |
| nvme1n1p3 | 450.5 GB | partition | | ext4 | / |
| sda | 1.8 TB | SATA | WDC WD20EZRZ-00Z5HB0 | | |
| sda1 | 1.8 TB | partition | | ntfs | /mnt/d |
| sdb | 1.8 TB | USB | Samsung PSSD T7 | crypto_LUKS | (external) |

## GPU

| Device | Description |
|---|---|
| 01:00.0 | NVIDIA GP102 [GeForce GTX 1080 Ti] [10de:1b06] rev a1 |

## Network

| Device | Interface | Description |
|---|---|---|
| 00:1f.6 | eno1 | Intel I219-V Ethernet Connection (7) [8086:15bc] rev 10 |
| 06:00.0 | enp6s0 | Intel I211 Gigabit Network Connection [8086:1539] rev 03 |
| 05:00.0 | wlp5s0 | Intel Dual Band Wireless-AC 3168NGW [8086:24fb] rev 10 |

## PCI Devices

- `00:00.0` Intel 8th/9th Gen Core Host Bridge/DRAM
- `00:01.0` PCIe Controller (x16)
- `00:14.0` Intel Cannon Lake PCH USB 3.1 xHCI
- `00:17.0` Intel Cannon Lake PCH SATA AHCI
- `00:1b.0` PCIe Root Port #17
- `00:1f.0` Intel Z390 LPC/eSPI
- `00:1f.3` Intel Cannon Lake PCH cAVS Audio
- `00:1f.6` Intel I219-V Ethernet
- `01:00.0` NVIDIA GP102 GeForce GTX 1080 Ti
- `02:00.0` Intel SSD 660P (NVMe, on board)
- `03:00.0` ASMedia ASM1184e PCIe Packet Switch
- `05:00.0` Intel Wireless-AC 3168NGW
- `06:00.0` Intel I211 Gigabit Ethernet
- `08:00.0` ASMedia ASM1061 SATA Controller
- `09:00.0` Intel SSD 660P (NVMe, slot)

## USB Devices

- Samsung PSSD T7 (external backup drive)
- FiiO DigiHug USB Audio
- Logitech G502 HERO Gaming Mouse
- Burr-Brown from TI USB Audio CODEC
- HOLDCHIP USB Gaming Keyboard
- winkeyless.kr ps2avrGB (custom keyboard)
- DAREU USB DEVICE (mouse/input)
- Valve Software Steam Controller
- CIDOO QK61 (keyboard)

## Notes

- LVM2 volume groups: `pool1a` (on nvme1n1p1), `pool1b` (on nvme0n1p1)
- External storage encrypted with LUKS (Samsung T7)
