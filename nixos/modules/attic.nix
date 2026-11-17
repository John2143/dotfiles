{
  config,
  pkgs,
  lib,
  ...
}: let
  cacheName = "2143nix";
  # Resolve via Tailscale MagicDNS ("nas" -> 100.64.0.14), NOT mDNS
  # "nas.local": mDNS is flaky over WiFi, yields AAAA-only records on
  # arch, and the NAS itself cannot resolve its own .local name, so its
  # own builds could never read from its own cache. MagicDNS resolves on
  # every host — including the NAS, via its /etc/hosts 127.0.0.2 nas.
  server = "nas";
  endpoint = "http://nas:8280";

  cfg = config.attic.pushHook;

  queueDir = "/var/lib/attic-push-queue";
  queueFile = "${queueDir}/paths";

  # ── post-build-hook (queues newly-built paths for upload) ──────────
  # Runs as root, once per completed derivation, and only appends a line.
  # A network push here costs ~10 s of fixed overhead (token, upstream
  # check, one SQLite write) and atticd serialises those writes, so N
  # concurrent hooks queue behind each other and trip the 300 s timeout
  # (measured 2026-11-17: 6 pushes in one call 11 s, the same 6 in
  # parallel 45 s). The timer below drains the spool in one push.
  # Replaces the `attic watch-store` daemon, which exited on its own after
  # ~20-45 s on the CI runner and uploaded almost nothing (15 paths in 8 h).
  queueHook = pkgs.writeShellScript "attic-queue-built-paths" ''
    # Never fails or stalls the build: no network, no attic, one append.
    # writeShellScript gives a bare bash shebang (no `-e`), and this script
    # depends on that — every failure path exits 0 explicitly.
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${queueDir} 2>/dev/null || exit 0
    printf '%s\n' $OUT_PATHS >> ${queueFile} 2>/dev/null || exit 0
    exit 0
  '';

  # Drains the spool with a single push. Runs as the oneshot unit below;
  # a failed push must never show up as a red unit, so it always exits 0.
  flushHook = pkgs.writeShellScript "attic-push-queue" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.attic-client pkgs.bash ]}
    export XDG_CONFIG_HOME=/etc
    spool=${queueFile}
    work="$spool.work"

    [ -s "$spool" ] || exit 0
    # Off the tailnet: leave the queue untouched and retry next tick.
    timeout 3 bash -c "exec 3<>/dev/tcp/${server}/8280" 2>/dev/null || exit 0

    # Clear a previous run's leftovers, then rotate. An append that races
    # the rotation recreates the spool (O_APPEND), so nothing is lost.
    rm -f "$work" "$work.batch"
    mv "$spool" "$work" && touch "$spool"

    # attic aborts the WHOLE batch on one invalid path ("error: path … is
    # not valid"), and a GC between build and flush produces exactly that,
    # so drop paths that no longer exist before pushing.
    while read -r p; do [ -e "$p" ] && printf '%s\n' "$p"; done < "$work" | sort -u > "$work.batch"

    rc=0
    if [ -s "$work.batch" ]; then
      timeout 900 ${pkgs.attic-client}/bin/attic push ${cacheName} --stdin < "$work.batch" || rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
      rm -f "$work" "$work.batch"
    else
      # Transient failure (NAS restart, expired token): put the paths back.
      # Duplicates are free, attic dedupes; cap the spool so a permanently
      # failing push cannot grow it without bound.
      cat "$work" >> "$spool"
      rm -f "$work" "$work.batch"
      tail -n 20000 "$spool" > "$spool.tmp" && mv "$spool.tmp" "$spool"
      echo "attic-push-queue: push failed (rc=$rc), requeued" >&2
    fi
    exit 0
  '';

  # ── cache semantics (measured 2026-11-10) ──────────────────────────
  # Attic is not a plain binary cache: it serves /_api/v1 and exposes no PUT
  # endpoint, so `nix copy --to ${endpoint}/${cacheName}` fails with HTTP 405.
  # Upload with `attic push ${cacheName} <paths>` (closure by default,
  # --no-closure to restrict). The hook queues paths and the timer pushes them in batches.
  #
  # Do not probe presence with `nix path-info --store <url> <path>`: it answers
  # "path ... is not valid" for anything it cannot resolve, which reads as
  # "missing" whether the path is absent or the query failed. Ask the narinfo
  # endpoint instead — `curl -sS --netrc-file /run/agenix/attic-netrc -o
  # /dev/null -w '%{http_code}' <url>/<hash>.narinfo` -> 200 present, 404 absent.
  #
  # The cache declares cache.nixos.org as an upstream key, so paths available
  # upstream are deliberately not stored: a 404 at attic for e.g. the kernel is
  # expected and costs nothing, since cache.nixos.org serves it. Entries are
  # retained for 90 days (Retention Period 7776000) unless pushed again, so a
  # path last built long ago can legitimately be gone.
in {
  options.attic.pushHook.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Upload paths built on this host to the Attic cache from Nix's post-build-hook.";
  };

  config = {
    # ── Nix substituter ──────────────────────────────────────────────
    # Our Attic cache is primary (first in list = highest priority).
    # cache.nixos.org is a fallback so we can still build when the
    # NAS is unreachable or cache entries are missing.
    nix.settings.substituters = lib.mkForce [
      "${endpoint}/${cacheName}"
      "https://cache.nixos.org"
    ];
    nix.settings.trusted-public-keys = [
      "2143nix:zqt4fb8dINfCsQPqWQcggPm2eqk9RpotNh1u8QKRQVA="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # ── Admin token (age-encrypted) ──────────────────────────────────
    age.secrets.attic-admin-token = {
      file = ../../secrets/attic-admin-token.age;
      mode = "0400";
      owner = "john";
      group = "users";
    };

    # ── Push hook ────────────────────────────────────────────────────
    # The CI runner's job process runs as `github-runner` (home
    # /var/empty), so it cannot keep a per-user attic config; this shared
    # file is what both it and the root hook read.
    environment.etc."attic/config.toml".text = ''
      default-server = "${server}"
      [servers.${server}]
      endpoint = "${endpoint}"
      token-file = "${config.age.secrets.attic-admin-token.path}"
    '';

    nix.settings.post-build-hook = lib.mkIf cfg.enable (toString queueHook);

    # ── background flush of queued paths ────────────────────────────
    systemd.tmpfiles.rules = lib.mkIf cfg.enable [
      "d ${queueDir} 0700 root root -"
    ];

    systemd.services.attic-push-queue = lib.mkIf cfg.enable {
      description = "Upload queued build paths to the Attic cache";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = flushHook;
        StateDirectory = "attic-push-queue";
        StateDirectoryMode = "0700";
        TimeoutStartSec = "20min";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.attic-push-queue = lib.mkIf cfg.enable {
      description = "Drain the Attic push queue";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitInactiveSec = "2min";
        AccuracySec = "30s";
      };
    };

    # ── attic login (oneshot, for interactive `attic push` in a shell) ─
    systemd.user.services.attic-login = {
      description = "Attic cache login";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "attic-login" ''
          exec ${pkgs.attic-client}/bin/attic login ${server} ${endpoint} "$(cat /run/agenix/attic-admin-token)"
        '';
        RemainAfterExit = true;
        TimeoutStopSec = 10;
      };
      wantedBy = [ "default.target" ];
    };

    # ── netrc (nix binary-cache auth) ───────────────────────────────
    nix.settings.netrc-file = "/run/agenix/attic-netrc";

    system.activationScripts.atticNetrc = {
      deps = [ "agenix" ];
      text = ''
        printf 'machine %s password %s\nmachine nas.local password %s\nmachine localhost password %s\n' \
          ${lib.escapeShellArg server} \
          "$(cat /run/agenix/attic-admin-token)" \
          "$(cat /run/agenix/attic-admin-token)" \
          "$(cat /run/agenix/attic-admin-token)" \
          > /run/agenix/attic-netrc
        chmod 0444 /run/agenix/attic-netrc
      '';
    };
  };
}
