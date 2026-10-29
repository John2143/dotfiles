# office disk layout (disko + LVM)

Last updated 2026-10-29.

office was reinstalled on 2026-10-29 from `nixos/modules/disko_office.nix`. Its only disk is
`/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NU0W947238F`.

| Device | Size | Filesystem | Mount |
|---|---|---|---|
| p1 ESP (`disk-main-ESP`, label `BOOT`) | 1G | vfat | `/boot` |
| p2 LVM PV (`disk-main-lvm`) → VG `office` | rest | | |
| `office/root` (label `root`) | 1401G | ext4, noatime | `/` (home lives here) |
| `office/longhorn` (label `longhorn`) | 300G | ext4, noatime | `/mnt/longhorn` |
| `office/swap` | 32G | swap | |
| unallocated in VG | ~129G | | |

There is no separate `/home` or games volume. Home, Steam libraries and ollama models
(`~/share/ollama/models`) all live on `root`, so there are no per-volume sizes to manage.
`longhorn` is the only split, and it exists so Longhorn can never fill `/`.

## Growing a volume

Both LVs grow online from the free space in the VG:

```sh
sudo vgs office                         # VFree = what is left
sudo lvextend -r -L +100G office/root   # -r grows the ext4 filesystem in the same step
```

## Longhorn

`/mnt/longhorn` matches the cluster's Longhorn setting `default-data-path`, and
`create-default-disk-labeled-nodes=true` is set. office is still **not** a Longhorn node,
because it is on wifi and carries the taint `wifi=no-network-storage`. Enabling it is a
separate decision; no disk change would be needed.

## Things the reinstall surfaced

- The k3s API VIP `192.168.5.10` is announced by MetalLB over BGP only. Over wifi, office
  ARPs for it on-link, gets no answer, and the agent cannot join. A NetworkManager dispatcher
  script in `office-configuration.nix` routes the VIP via the router `192.168.5.1`.
- The upstream ollama unit sets `ProtectHome=yes`, which hides `/home/john/share`.
  `ollama.nix` turns it off.
