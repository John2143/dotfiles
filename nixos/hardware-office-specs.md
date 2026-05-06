# Hardware Specs: office

**Generated:** 2026-05-06T05:58:56Z

## System Overview

| Field | Value |
|---|---|
| Hostname | office |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.26 x86_64 |
| Motherboard | ASUS TUF GAMING B760M-PLUS WIFI (Rev 1.xx) |
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
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb ssbd ibrs ibpb stibp ibrs_enhanced tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid rdseed adx smap clflushopt clwb intel_pt sha_ni xsaveopt xsavec xgetbv1 xsaves split_lock_detect user_shstk avx_vnni dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req hfi vnmi umip pku ospke waitpkg gfni vaes vpclmulqdq rdpid movdiri movdir64b fsrm md_clear serialize pconfig arch_lbr ibt flush_l1d arch_capabilities |

## Memory

| Type | Size |
|---|---|
| RAM | 64 GiB |
| Swap | 32 GiB (on nvme0n1p2) |

## Storage

| Device | Size | Type | Model | Filesystem | Mount |
|---|---|---|---|---|---|
| nvme0n1 | 1.8 TB | NVMe | Samsung SSD 980 PRO 2TB | | |
| nvme0n1p1 | 1 GB | partition | | vfat | /boot |
| nvme0n1p2 | 32 GB | partition | | swap | [SWAP] |
| nvme0n1p3 | 500 GB | partition | | ext4 | / |
| nvme0n1p6 | 500 GB | partition | | ext4 | /mnt/arch |
| nvme0n1p7 | 798 GB | partition | | ext4 | /mnt/share |
| sda | 7.6 GB | USB | USB 2.0 FD | iso9660 | (removable) |

## GPU

| Device | Description |
|---|---|
| 03:00.0 | AMD Radeon RX 7900 XT/XTX (Navi 31) [1002:744c] rev c8 |

## Network

| Device | Interface | Description |
|---|---|---|
| 07:00.0 | eno1 | Realtek RTL8125 2.5GbE Controller [10ec:8125] rev 05 |
| 00:14.3 | wlp0s20f3 | Intel 700 Series CNVi WiFi [8086:7a70] rev 11 |

## PCI Devices

- `00:00.0` Intel Raptor Lake-S Host Bridge/DRAM Controller
- `00:01.0` PCIe 5.0 Graphics Port (PEG010)
- `00:06.0` PCIe 4.0 Graphics Port
- `00:14.0` Intel Raptor Lake USB 3.2 Gen2x2 XHCI
- `00:14.3` Intel CNVi WiFi
- `00:17.0` Intel Raptor Lake SATA AHCI
- `00:1f.0` Intel B760 LPC/eSPI
- `00:1f.3` Intel Raptor Lake HD Audio
- `01:00.0` AMD Navi 10 XL Upstream Port (PCIe Switch)
- `03:00.0` AMD Navi 31 GPU
- `03:00.1` AMD Navi 31 HDMI/DP Audio
- `04:00.0` Samsung NVMe SSD Controller PM9A1/980PRO
- `06:00.0` ASMedia ASM2142/3142 USB 3.1 Host Controller
- `07:00.0` Realtek RTL8125 2.5GbE

## Temperature Sensors

- Core 0: 52°C, Core 12: 62°C, Core 20: 84°C (highest)
- GPU (edge): 55°C, GPU (junction): 65°C, GPU (memory): 72°C
- SSD: 56°C
- Ambient (ACPI): 27.8°C
