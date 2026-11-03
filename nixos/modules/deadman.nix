# Dead man's switch for k3s nodes: see deadman.sh. Imported by k3s-server.nix and
# k3s-agent.nix; a host opts out with custom.deadman.enable = false.
{config, lib, pkgs, ...}: let
  cfg = config.custom.deadman;
  deadman = pkgs.writeShellApplication {
    name = "deadman";
    runtimeInputs = with pkgs; [coreutils gawk gnugrep gnused procps config.systemd.package config.nix.package config.services.k3s.package];
    text = ''
      NODE=${config.networking.hostName}
    '' + builtins.readFile ./deadman.sh;
  };
in {
  options.custom.deadman.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Guard every boot and live switch of this k3s node; roll back and lock on failure.";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [deadman];
      systemd.tmpfiles.rules = ["d /var/lib/deadman 0755 root root -"];
      system.preSwitchChecks.deadman = ''${deadman}/bin/deadman pre-switch "$1" "$2"'';
      # Hardware watchdog: a hung kernel or PID 1 resets the box (nas keeps its 30s).
      systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault "60s";

      systemd.services.deadman-boot-check = {
        description = "deadman: prove this boot healthy, else return to the last good generation";
        wantedBy = ["multi-user.target"];
        requiredBy = ["boot-complete.target"];
        wants = ["network-online.target"];
        after = ["basic.target" "network-online.target" "k3s.service" "sshd.service"];
        before = ["boot-complete.target" "shutdown.target"];
        conflicts = ["shutdown.target"];
        # Without this, multi-user.target would wait up to 15 min for the check.
        unitConfig.DefaultDependencies = false;
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${deadman}/bin/deadman boot-check";
          TimeoutStartSec = "20min";
        };
      };

      systemd.services.deadman-publish = {
        description = "deadman: publish the DeadmanLocked node condition";
        after = ["k3s.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${deadman}/bin/deadman publish";
        };
      };
      systemd.timers.deadman-publish = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "20min";
          OnUnitActiveSec = "15min";
        };
      };
    }
    # Boot-level half: only systemd-boot can count boots and fall back
    # (arch, closet, nas). big (GRUB) and pite (extlinux) get the userspace half only.
    (lib.mkIf config.boot.loader.systemd-boot.enable {
      boot.loader.systemd-boot.bootCounting = {
        enable = true;
        tries = 3;
      };
      # An emergency shell nobody can reach is a hang; reboot so the counter runs down.
      boot.initrd.systemd.services.emergency = {
        serviceConfig.RuntimeMaxSec = "10min";
        unitConfig.FailureAction = "reboot-force";
      };
      systemd.services.emergency = {
        serviceConfig.RuntimeMaxSec = "10min";
        unitConfig.FailureAction = "reboot-force";
      };
    })
  ]);
}
