# Swap behaviour for the whole fleet.
#
# Disk-backed swap: keep anonymous pages resident and let the kernel reclaim
# page cache (and the ZFS ARC) first. Hosts whose swap is compressed override
# this to "100" — zram is the cheap tier — see remote-cli-config.nix (pite,
# aman, vpin) and mirror-configuration.nix. arch overrides to "60": its
# anonymous working set (24.5 GiB resident + 19.8 GiB swapped on 32 GiB) needs
# swap as a safety valve rather than as displaced page cache.
{lib, ...}: {
  boot.kernel.sysctl."vm.swappiness" = lib.mkDefault "10";
}
