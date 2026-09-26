# Observability agent for every flake host: SMART disk health metrics +
# optional NVIDIA GPU metrics, scraped by pite's Prometheus and forwarded
# to Mimir (long-term store). Host temps (CPU/GPU/board/ambient) are already
# covered by the shared node_exporter (see shared-cli-configuration.nix)
# scraped as job=home-nodes by pite-canary.nix.
#
# - smartctl_exporter: exposes SMART attributes (Reallocated_Sector_Ct,
#   Current_Pending_Sector, Offline_Uncorrectable, ...) on :9633. Iterates
#   whole-disk ata-*, nvme-*, scsi-*, and wwn-* by-id links at runtime — sdX
#   letters shift across reboots. Hosts without SMART disks (Pi, VM) get an
#   empty device list and serve zero SMART metrics; that is fine.
# - nvidia_gpu_exporter (enableNvidiaGpu): arch's GTX 1080 Ti on :9835.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.observability-agent;
in
{
  options.services.observability-agent = {
    enable = lib.mkEnableOption "the host observability agent (smartctl + optional nvidia metrics)";
    enableNvidiaGpu = lib.mkEnableOption "the NVIDIA GPU exporter (arch GTX 1080 Ti)";
  };

  config = lib.mkIf cfg.enable {

    # Open the scrape port: the exporter binds 0.0.0.0:9633 but NixOS's
    # firewall defaults to deny, so pite's Prometheus (job=smartctl, LAN
    # targets 192.168.5.x:9633) would be refused on every host.
    networking.firewall.allowedTCPPorts = [ 9633 ];
    # smartctl_exporter — Prometheus metrics for SMART health (bad sectors,
    # reallocated/pending/uncorrectable counts) scraped on port 9633.
    # Uses stable whole-disk by-id names; known Longhorn iSCSI virtual LUNs
    # and partition symlinks are skipped.
    systemd.services.smartctl-exporter = {
      description = "smartctl_exporter for Prometheus (SMART metrics)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ pkgs.smartmontools ];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "smartctl-exporter-start" ''
          set -o errexit
          shopt -s nullglob
          # udev may still be probing a large HBA when this unit starts. If the
          # by-id enumeration below runs first it finds nothing, the exporter
          # falls back to discovery, and the Prometheus registry freezes its
          # descriptor set from whatever it saw at registration — every later
          # scrape then fails with "unregistered descriptor" (big, 2026-09-17:
          # 2 devices at start, 34 an hour later, HTTP 500 ever since).
          ${pkgs.udev}/bin/udevadm settle --timeout=60 || true
          # Enumerate whole-disk by-id links across local transports. HBA disks
          # may expose only wwn-*/scsi-* (big has no ata-* links), while NVMe
          # disks expose nvme-* links. Try ata-*/nvme-* first so they win over
          # aliases for the same resolved device.
          # Skip verified IET virtual LUNs and other SMART-disabled devices;
          # exporting either would make the scrape fail.
          declare -A seen
          devices=()
          for dev in /dev/disk/by-id/ata-* /dev/disk/by-id/nvme-* \
                     /dev/disk/by-id/scsi-* /dev/disk/by-id/wwn-*; do
            case "$dev" in
              *-part*) continue ;;
            esac
            real=$(readlink -f "$dev")
            [ -n "''${seen[$real]:-}" ] && continue
            info=$(smartctl -i "$dev" 2>/dev/null) || true
            if grep -Eq '^Vendor:[[:space:]]+IET[[:space:]]*$' <<<"$info" &&
               grep -Eq '^Product:[[:space:]]+VIRTUAL-DISK[[:space:]]*$' <<<"$info"; then
              seen[$real]=1
              continue
            fi
            if grep -Eq '^SMART support is:[[:space:]]+Disabled' <<<"$info"; then
              seen[$real]=1
              continue
            fi
            case "$(basename "$dev")" in
              nvme-*) grep -Eq '^NVMe Version:' <<<"$info" || continue ;;
              *) grep -Eq '^SMART support is:[[:space:]]+(Available|Enabled)([[:space:]]|$)' <<<"$info" || continue ;;
            esac
            seen[$real]=1
            devices+=(--smartctl.device "$dev")
          done
          exec ${pkgs.prometheus-smartctl-exporter}/bin/smartctl_exporter \
            --smartctl.path=${pkgs.smartmontools}/bin/smartctl \
            --web.listen-address=0.0.0.0:9633 \
            "''${devices[@]}"
        '';
        Restart = "on-failure";
      };
    };

    # nvidia_gpu_exporter — arch's GTX 1080 Ti (temps, util, memory). Uses the
    # driver's nvidia-smi via the nvidia-smi-command flag so systemd's minimal
    # PATH cannot hide it. Only enabled when enableNvidiaGpu is true.
    systemd.services.nvidia-gpu-exporter = lib.mkIf cfg.enableNvidiaGpu {
      description = "NVIDIA GPU exporter (arch GTX 1080 Ti)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.prometheus-nvidia-gpu-exporter}/bin/nvidia_gpu_exporter --nvidia-smi-command=${config.hardware.nvidia.package.bin}/bin/nvidia-smi --web.listen-address=:9835";
        Restart = "on-failure";
      };
    };
  };
}
