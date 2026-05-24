# Hardware Specs Methodology

## How specs were gathered

Each host was enumerated remotely from the `office` machine over SSH via Tailscale. Commands were chosen to be **read-only** and **non-invasive** -- no packages were permanently installed, no system state was modified.

### Commands used

| Command | Package | Source | Purpose |
|---|---|---|---|
| `lscpu` | util-linux | System PATH | CPU model, cores, cache, frequencies, vulnerabilities |
| `free -h` | coreutils | System PATH | RAM and swap size |
| `sudo dmidecode -t memory` | dmidecode | `nix shell nixpkgs#dmidecode -c sudo dmidecode -t memory` | RAM type (DDR4/5), speed (MT/s), DIMM count, manufacturer, part numbers — requires root |

| `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA` | util-linux | System PATH | Block devices, disk models, partition layout |
| `lspci -nn` | pciutils | `nix shell nixpkgs#pciutils -c lspci -nn` | PCI device tree |
| `lsusb` | usbutils | `nix shell nixpkgs#usbutils -c lsusb` | USB devices |
| `cat /sys/class/dmi/id/*` | kernel sysfs | Direct read | Motherboard vendor, model, BIOS version (x86 only) |
| `nix run nixpkgs#lshw -- -short` | lshw | `nix run` | Hardware tree summary |
| `sensors -j` | lm_sensors | `nix run nixpkgs#lm_sensors` | Temperature sensors (when available) |
| `ls /dev/disk/by-id/` | udev | Direct read | Disk serial numbers and identifiers |
| `uname -a` | coreutils | System PATH | Kernel version |
| `cat /etc/os-release` | system | Direct read | OS version |

### Why `nix run` / `nix shell` instead of installing

- `nix run nixpkgs#pkg` downloads and runs a package in a temporary environment without touching the system profile.
- `nix shell nixpkgs#pkg -c cmd` similarly makes the tool available temporarily.
- This avoids `environment.systemPackages` changes or any persistent modification.

### Hosts that were unreachable

`security` and `term` were not found on the Tailscale network at enumeration time. Placeholder files were created; re-run the enumeration when they are online.

### Limitations

- ARM devices (pite, aman, vpin) do not have DMI sysfs data and have limited PCI/USB information.
- `lshw` output may vary in detail depending on kernel permissions (some fields require root).
- Disk models from `lsblk` may be empty for virtual or some NVMe devices; serial number lookup via `/dev/disk/by-id/` provides fallback identification.
- RAM type and speed via `dmidecode` requires root; without `sudo`, the command will fail. Some kernels expose limited info via `/sys/class/dmi/id/` but this does not include SPD details.
- Temperature sensors depend on kernel driver availability and may not be present on all hardware.

## Re-running

To re-gather specs for any host:

```bash
ssh <host> "nix shell nixpkgs#pciutils nixpkgs#usbutils -c sh -c '
  echo \"=== CPU ===\" && lscpu
  echo \"=== MEMORY ===\" && free -h
  echo "=== RAM DETAILS ===" && sudo dmidecode -t memory
  echo \"=== BLOCK DEVICES ===\" && lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA
  echo \"=== PCI ===\" && lspci -nn
  echo \"=== USB ===\" && lsusb
  echo \"=== DMI ===\" && for f in /sys/class/dmi/id/*\; do echo \"\$(basename \$f): \$(cat \$f 2>/dev/null)\"; done
  echo \"=== DISK ID ===\" && ls /dev/disk/by-id/
  echo \"=== KERNEL ===\" && uname -a
  echo \"=== OS ===\" && cat /etc/os-release
'"
```
