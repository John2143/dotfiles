# Hardware Specs: closet

**Generated:** 2026-05-06T05:59:01Z

## System Overview

| Field | Value |
|---|---|
| Hostname | closet |
| OS | NixOS 26.05 (Yarara) |
| Kernel | 6.18.24 x86_64 |
| Motherboard | ASUS PRIME A320M-K |
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
| Flags | fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb hw_pstate ssbd ibpb vmmcall fsgsbase bmi1 avx2 smep bmi2 rdseed adx smap clflushopt sha_ni xsaveopt xsavec xgetbv1 clzero xsaveerptr arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif overflow_recov succor smca sev |

## Memory

| Type | Size |
|---|---|
| RAM | 7.7 GiB |
| Swap | None |

## Storage

| Device | Size | Type | Model | Filesystem | Mount |
|---|---|---|---|---|---|
| nvme0n1 | 238.5 GB | NVMe | Phison E12 NVMe (PCIe SSD) | | |
| nvme0n1p1 | 2 GB | partition | | vfat | /boot |
| nvme0n1p2 | 236.5 GB | partition | | ext4 | / |
| sda | 3.6 TB | USB | Micron CT4000X9SSD9 (Crucial X9 4TB) | | |
| sda1 | 3.6 TB | partition | | ext4 | /mnt |

**K3s volumes** (virtual disks):
- sdb (4.7G), sdc (9.3G), sde (9.3G) — ext4, mounted as kubelet PVC volumes

## GPU

**None detected.** (No discrete or integrated GPU visible on PCI bus; system likely uses basic framebuffer.)

## Network

| Device | Interface | Description |
|---|---|---|
| 06:00.0 | (Realtek) | Realtek RTL8111/8168/8211/8411 PCIe Gigabit Ethernet [10ec:8168] rev 15 |

## PCI Devices

- `00:00.0` AMD Family 17h Root Complex
- `00:01.1` PCIe GPP Bridge
- `00:14.0` AMD FCH SMBus
- `00:14.3` AMD FCH LPC Bridge
- `01:00.0` Phison E12 NVMe Controller (boot drive)
- `02:00.0` AMD A320 USB 3.1 XHCI Host Controller
- `02:00.1` AMD A320 SATA Controller
- `06:00.0` Realtek RTL8111 Gigabit Ethernet
- `08:00.2` AMD Platform Security Processor (PSP) 3.0
- `09:00.3` AMD Family 17h HD Audio Controller

## Notes

- This machine is a K3s node (longhorn host)
- The 4TB storage is an external USB Crucial X9 SSD
- No swap configured
