# Keep alive the store paths that k3s's extracted data dir symlinks into.
#
# k3s extracts its bundle to /var/lib/rancher/k3s/data/<sha256>/ and documents
# that dir as self-contained (docs.k3s.io "K3s initialization deep dive"): the
# SHA dir holds the binaries, data/current and data/previous are symlinks to
# it, and data/cni/* are symlinks to bin/cni inside it. nixpkgs diverges:
# builder.nix:469-470 replaces bin/cni and bin/containerd-shim-runc-v2 with
# absolute /nix/store symlinks, and everything else is hardlinked, so those two
# are the only files garbage collection can break. When it does, the node stays
# Ready and every new pod sandbox fails with `failed to find plugin "flannel"`
# (nas 2026-10-24, arch 2026-10-25).
#
# Nix keeps the whole closure of a root, so rooting these two links also keeps
# the glibc their ELF interpreter needs.
#
# The tmpfiles rules use the same indirect-root form NixOS uses for
# /nix/var/nix/gcroots/current-system -> /run/current-system. The service covers
# what tmpfiles cannot enumerate: every historical SHA dir, which is what a
# failed system switch leaves the running k3s pointing at.
{
  config,
  lib,
  pkgs,
  ...
}: let
  k3sRooter = pkgs.writeShellScript "k3s-gcroots" ''
    set -eu
    data=/var/lib/rancher/k3s/data
    roots=/nix/var/nix/gcroots
    [ -d "$data" ] || exit 0
    mkdir -p "$roots"
    wanted=" "
    for f in "$data"/*/bin/cni "$data"/*/bin/containerd-shim-runc-v2; do
      [ -L "$f" ] || continue
      [ -e "$f" ] || continue
      dir=$(basename "$(dirname "$(dirname "$f")")")
      den=k3s-$dir-$(basename "$f")
      ln -sfn "$f" "$roots/$den"
      wanted="$wanted$den "
    done
    for r in "$roots"/k3s-*; do
      [ -L "$r" ] || continue
      den=$(basename "$r")
      case $den in
        k3s-current-*|k3s-previous-*) continue ;;
      esac
      case $wanted in
        *" $den "*) ;;
        *) rm -f "$r" ;;
      esac
    done
  '';
in {
  config = lib.mkIf config.services.k3s.enable {
    systemd.tmpfiles.rules = [
      "L+ /nix/var/nix/gcroots/k3s-current-cni - - - - /var/lib/rancher/k3s/data/current/bin/cni"
      "L+ /nix/var/nix/gcroots/k3s-current-shim - - - - /var/lib/rancher/k3s/data/current/bin/containerd-shim-runc-v2"
      "L+ /nix/var/nix/gcroots/k3s-previous-cni - - - - /var/lib/rancher/k3s/data/previous/bin/cni"
      "L+ /nix/var/nix/gcroots/k3s-previous-shim - - - - /var/lib/rancher/k3s/data/previous/bin/containerd-shim-runc-v2"
    ];

    systemd.services.k3s-gcroots = {
      description = "GC-root the store paths k3s extraction dirs symlink to";
      after = ["k3s.service"];
      wantedBy = ["k3s.service" "multi-user.target"];
      path = [pkgs.coreutils];
      # Not RemainAfterExit: a k3s restart may have switched extraction dirs,
      # and this must run again whenever that happens.
      serviceConfig = {Type = "oneshot";};
      script = "${k3sRooter}";
    };

    systemd.timers.k3s-gcroots = {
      description = "Refresh k3s GC roots";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "30min";
      };
    };
  };
}
