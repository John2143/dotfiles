# A direct Ethernet link to the MacBook's USB Ethernet adapter, so Deskflow's
# pointer and keyboard events stay off Wi-Fi: that hop measured 20-330 ms with
# ~100 ms jitter, against sub-millisecond on the wire.
#
# Both desktops serve the **same** host address, so the Mac keeps one host entry
# (`thunderbolt` -> 10.99.0.1) no matter which machine the cable is plugged into
# — the same trick as the Apple cable's 10.77.0.1. Only one machine can have the
# cable at a time, so the duplicated address never collides.
#
# `ipv4.method = shared` also provides NAT for this link, in its own nftables
# table (`table ip nm-shared-<iface>`, created when the link comes up), so the
# peer gets address, gateway, DNS and internet from this host. Whether the Mac
# uses that as its default route is its own service order, not this module's
# business. Check with `nft list ruleset | grep -A3 nm-shared` — `iptables -t
# nat` never shows NM's own table.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.macbookLink;
in {
  options.services.macbookLink.interfaces = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = ''
      Wired interfaces the MacBook's adapter may be plugged into on this host,
      one profile per port so any of them works. Empty leaves the link
      unconfigured here.
    '';
  };

  config = lib.mkIf (cfg.interfaces != []) {
    networking.networkmanager.ensureProfiles.profiles =
      lib.listToAttrs (map (iface: {
          name = "macbook-link-${iface}";
          value = {
            connection = {
              id = "macbook-link-${iface}";
              type = "ethernet";
              interface-name = iface;
              autoconnect = "true";
              # NetworkManager also auto-creates a "Wired connection N" for the
              # port; the higher priority keeps this profile, and its address,
              # the winner.
              autoconnect-priority = "10";
            };
            ipv4 = {
              method = "shared";
              addresses = "10.99.0.1/24";
            };
            ipv6.method = "ignore";
          };
        })
        cfg.interfaces);
  };
}
