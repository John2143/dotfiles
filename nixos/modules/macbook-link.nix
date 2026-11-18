# A direct Ethernet link to the MacBook's USB Ethernet adapter, so Deskflow's
# pointer and keyboard events stay off Wi-Fi: that hop measured 20-330 ms with
# ~100 ms jitter, against sub-millisecond on the wire.
#
# Both desktops serve the **same** host address, so the Mac keeps one host entry
# (`thunderbolt` -> 10.99.0.1) no matter which machine the cable is plugged into
# — the same trick as the Apple cable's 10.77.0.1. Only one machine can have the
# cable at a time, so the duplicated address never collides.
#
# NAT is deliberately not configured: the Mac keeps its internet on Wi-Fi and
# only 10.99.0.0/24 crosses the cable. NetworkManager's `shared` mode installs no
# MASQUERADE rules on these hosts anyway, so sharing the connection this way
# never worked.
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
