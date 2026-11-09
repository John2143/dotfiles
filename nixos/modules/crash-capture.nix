# Kernel crash capture, archival and self-recovery.
#
# Written after the 2026-11-07 office oops: free_pages_and_swap_cache() faulted
# on a wild stack index while media-player-status exec'd (see the EFI pstore
# record under /var/lib/systemd/pstore). The kernel does not always survive an
# mm oops, it panicked two seconds later, and with kernel.panic = 0 the box sat
# dead until it was power-cycled ~10 minutes after the fact.
#
# Three gaps this closes:
#
#  1. Nothing durable. journald's SyncIntervalSec defaults to 5 minutes, so the
#     last minutes before a panic or power cut are lost; userspace context
#     survived here only by luck. Set to 1s.
#  2. Nothing archived or announced. systemd-pstore already moves EFI records to
#     /var/lib/systemd/pstore and stops there (firmware truncates them — parts
#     1-6 of the follow-up panic record were dropped). pstore-archive copies
#     each new record to a stable tree and pushes the identifying lines to ntfy,
#     so a crash is both preserved and noticed.
#  3. No recovery. panic=0 hangs forever; a wedged CPU hangs silently. panic=<n>
#     reboots n seconds after a panic, hardlockup_panic turns a wedged CPU into
#     a panic, and RuntimeWatchdogSec resets the box when PID 1 stops petting
#     the hardware watchdog.
#
# panic_on_oops is 1 at runtime (set outside this module) and must stay 1: an
# oops then becomes a panic, which is exactly what ramoops captures. Setting it
# to 0 would make oops-class faults reboot silently and leave no record.
{config, lib, pkgs, ...}: let
  cfg = config.custom.crashCapture;

  pstore-archive = pkgs.writeShellApplication {
    name = "pstore-archive";
    runtimeInputs = with pkgs; [coreutils gnugrep curl];
    text = ''
      PSTOREDIR=/var/lib/systemd/pstore
      ARCHIVE_DIR=${cfg.archiveDir}
      NOTIFY=${if cfg.notify then "1" else "0"}
    '' + builtins.readFile ./crash-capture.sh;
  };
in {
  options.custom.crashCapture = {
    enable = lib.mkEnableOption "kernel crash capture, pstore archival and self-recovery";

    panicTimeout = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Seconds between a kernel panic and the automatic reboot (kernel.panic / panic=).";
    };

    watchdogSec = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "systemd runtime watchdog: hard-reset the box when PID 1 stops petting the hardware watchdog.";
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Push a one-line crash signature to ntfy (uses the ntfy-topic-url age secret).";
    };

    archiveDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/crash-archive";
      description = "Where EFI pstore records are copied after a crash.";
    };

    ramoops = {
      enable = lib.mkEnableOption "capture kernel panics in a reserved RAM region instead of EFI variables";

      memAddress = lib.mkOption {
        type = lib.types.str;
        default = "0x10000000";
        description = ''
          Physical address of the 4 MiB ramoops region. Must lie inside a usable
          RAM range in the firmware memory map and be 4 MiB aligned.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # --- self-recovery ---------------------------------------------------
    # EFI pstore cannot hold a dump on this board (efivarfs is 77% full, 45K free,
    # dumps are 112-180K). A reserved RAM region has no such limit and survives
    # the warm reset that panic= performs. 0x10000000 sits inside
    # [mem 0x100000-0x5dd2afff] usable, clear of the first reserved block at
    # 0x5dd2b000. ecc=1 protects against a reset that leaves RAM partly corrupt.
    boot.kernelParams =
      ["panic=${toString cfg.panicTimeout}"]
      ++ lib.optionals cfg.ramoops.enable [
        ("memmap=4096K" + "$" + cfg.ramoops.memAddress)
        "ramoops.mem_address=${cfg.ramoops.memAddress}"
        "ramoops.mem_size=0x400000"
        "ramoops.record_size=0x100000"
        "ramoops.console_size=0x100000"
        "ramoops.pmsg_size=0x2000"
        "ramoops.ecc=1"
      ];
    boot.kernelModules = lib.optionals cfg.ramoops.enable ["ramoops"];
    boot.kernel.sysctl = {
      "kernel.panic" = cfg.panicTimeout;
      "kernel.hardlockup_panic" = 1;
    };
    systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault cfg.watchdogSec;

    # --- durable logging -------------------------------------------------
    # Journald syncs its files every 5 minutes by default; a panic or power cut
    # otherwise discards exactly the lines that explain it.
    services.journald.settings.Journal = {
      SyncIntervalSec = "1s";
    };

    systemd.tmpfiles.rules = ["d ${cfg.archiveDir} 0755 root root -"];

    systemd.services.pstore-archive = {
      description = "Archive new EFI pstore crash records and announce them";
      wantedBy = ["multi-user.target"];
      after = ["systemd-pstore.service" "network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pstore-archive}/bin/pstore-archive";
      };
    };
  };
}
