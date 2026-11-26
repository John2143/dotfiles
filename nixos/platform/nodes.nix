# The voters of the US platform cluster (plan: us-platform-cluster-plan.md,
# phases 1-2 in ~/repos/bigp-tofu and argo/platform-argo).
#
# One place for every per-node fact: the flake turns each entry into a host,
# bigp-tofu/platform describes the VM at home, and the k3s flags in phase 2
# read wgAddress. Addresses are static; none of the three uses DHCP for its
# real configuration (the installers do, briefly).
#
#   publicIPv4  null unless the node is a public edge (the two cloud voters).
#   wgAddress   wg-plat mesh address: k3s --node-ip/--advertise-address and
#               the flannel VXLAN interface live here, so this is the node's
#               identity inside the cluster.
#   mac         must match the NIC exactly; the network config matches on the
#               MAC, never on the interface name (it is not stable across
#               kernels or providers).
{
  plat-bos = {
    site = "hostinger-bos";
    publicIPv4 = "2.25.220.79";
    wgAddress = "10.98.1.11";
    voter = true;
    edge = true;
    diskDevice = "/dev/sda";
    useEFI = false;
    mac = "e2:e8:d4:c6:53:d2";
    address = "2.25.220.79/24";
    gateway = "2.25.220.254";
    nameservers = ["1.1.1.1" "9.9.9.9"];
  };

  plat-home = {
    site = "bigp";
    publicIPv4 = null;
    wgAddress = "10.98.1.13";
    voter = true;
    edge = false;
    diskDevice = "/dev/sda";
    useEFI = false;
    mac = "bc:24:11:00:00:50";
    address = "192.168.5.50/24";
    gateway = "192.168.5.1";
    nameservers = ["192.168.5.1"];
  };

  # Captured from the running Ubuntu 2026-11-26 (cloud-init netplan, lsblk,
  # lspci): KVM, virtio-scsi + virtio-net, legacy BIOS (no /sys/firmware/efi),
  # one 100 GB disk. The 00:50:56 MAC prefix is Contabo's allocation, not
  # VMware. IPv6 (2605:a144:2378:9787::1/64 via fe80::1) is not configured
  # yet; nothing in the platform needs it.
  plat-nyc = {
    site = "contabo-us-east";
    publicIPv4 = "31.132.60.154";
    wgAddress = "10.98.1.12";
    voter = true;
    edge = true;
    diskDevice = "/dev/sda";
    useEFI = false;
    mac = "00:50:56:69:f8:c7";
    address = "31.132.60.154/22";
    gateway = "31.132.60.1";
    nameservers = ["209.126.15.53" "195.179.224.53"];
  };
}
