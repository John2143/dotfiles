# OPTIONAL: pin big's Tesla P4 application clocks to the max supported pair.
# Enable/disable: (un)comment the `./nixos/modules/big-gpu-clocks.nix` import in
# flake.nix (big's module list), then on big:
#   cd ~/dotfiles && sudo nixos-rebuild switch --flake .#big
# Disabling needs no reboot: the switch stops this unit, whose ExecStop runs
# `nvidia-smi -rac` (back to the 885 MHz default), and stops nvidia-persistenced.
#
# Measured 2026-10-03 (Frigate, one 640x640 ONNX detector): inference p50
# 27.95 -> 25.55 ms (~9%), p90 30.13 -> 27.99 ms. Peak 78 C (slowdown 91 C,
# shutdown 94 C); power touches the 75 W cap under load, with no HW/thermal
# throttle events.
#
# Safe because the driver only accepts clock pairs from the card's own
# supported list (`nvidia-smi -q -d SUPPORTED_CLOCKS`), and the firmware's
# 75 W power cap and thermal slowdown/shutdown still apply. If the pair is ever
# rejected (e.g. a different GPU), the unit fails visibly in
# `systemctl --failed` and the GPU keeps running at default clocks.
{config, ...}: let
  smi = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi";
in {
  # Keep the driver initialised with no client attached, so application clocks
  # are not reset while no GPU process is running (e.g. during Frigate rollouts).
  hardware.nvidia.nvidiaPersistenced = true;

  systemd.services.nvidia-p4-app-clocks = {
    description = "Pin Tesla P4 application clocks to max (MEM 3003 / SM 1531)";
    wantedBy = ["multi-user.target"];
    wants = ["nvidia-persistenced.service"];
    after = ["nvidia-persistenced.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${smi} -ac 3003,1531";
      ExecStop = "${smi} -rac";
    };
  };
}
