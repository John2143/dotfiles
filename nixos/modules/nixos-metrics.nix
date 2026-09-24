# NixOS build identity for Prometheus.
#
# Publishes *which* build this host is running (NixOS version, nixpkgs revision,
# the dotfiles flake revision) and how old that flake revision is, through the
# node_exporter textfile collector. pite's Prometheus scrapes every host as
# job=home-nodes and remote-writes to Mimir, so these series land there with no
# further wiring.
#
# Every value is known at evaluation time, so the .prom file is produced at
# build time and copied into the collector's directory by an activation script —
# there is deliberately no runtime job. The previous implementation ran
# `nixos-version | awk` from a systemd unit whose PATH had no gawk, so it exited
# 127 on every run and never produced a sample.
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.services.nixos-metrics;

  # Values are NixOS version strings and git revisions, both restricted to
  # [A-Za-z0-9._-]; Prometheus label escaping is not needed.
  nixpkgsRevision =
    if config.system.nixos.revision == null
    then "unknown"
    else config.system.nixos.revision;

  flakeRevision =
    if config.system.configurationRevision == null
    then "unknown"
    else config.system.configurationRevision;

  # Commit time of the flake revision this system was built from; absent when
  # the flake is not a git checkout.
  flakeTimestamp = inputs.self.lastModified or null;

  promText = ''
    nixos_info{version="${config.system.nixos.version}",nixpkgs_revision="${nixpkgsRevision}",flake_revision="${flakeRevision}",hostname="${config.networking.hostName}"} 1
  '' + lib.optionalString (flakeTimestamp != null) "nixos_flake_timestamp ${toString flakeTimestamp}\n";
in {
  options.services.nixos-metrics = {
    enable = lib.mkEnableOption "publishing the NixOS build identity as Prometheus metrics";

    text = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = promText;
      description = "Contents of the generated node_exporter textfile.";
    };
  };

  config = lib.mkIf cfg.enable {
    # node_exporter enables every collector by default; this flag only points the
    # textfile collector at a directory. Do not define it anywhere else:
    # extraFlags is a list option, so a second definition duplicates the flag.
    # Do NOT copy the widely-quoted `enabledCollectors = [ "textfile" ];` snippet
    # from blog posts — a non-empty enabledCollectors list disables every other
    # collector, including the `os` collector that produces node_os_info.
    services.prometheus.exporters.node.extraFlags = [
      "--collector.textfile.directory=/var/lib/node_exporter/textfile"
    ];

    # A real file, rewritten on every activation, so node_textfile_mtime_seconds
    # is when this host last applied its configuration rather than the store's
    # 1970 mtime. Absolute store paths only: activation snippets run with
    # PATH=/empty, the same class of mistake that killed the original unit.
    system.activationScripts.nixos-metrics = ''
      ${pkgs.coreutils}/bin/install -D -m 0644 ${pkgs.writeText "nixos.prom" cfg.text} /var/lib/node_exporter/textfile/nixos.prom
    '';
  };
}
