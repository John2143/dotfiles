# Headscale — Self-hosted Tailscale coordination server
#
# Runs on the Home Pi. All Hetzner nodes + home machines join this tailnet.
# Tailscale on the same host connects via localhost:8080.
# External nodes connect via the Home Pi's public IP (initial) or Tailscale IP (post-bootstrap).
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;

    settings = {
      server_url = "https://headscale.9s.pics";

      dns_config = {
        override_local_dns = true;
        nameservers = ["1.1.1.1" "9.9.9.9"];
        magic_dns = true;
        base_domain = "9s.pics";
      };

      # DERP relay servers — one per region on raw IPs
      derp = {
        server = {
          enabled = false; # DERP runs as a separate app on each k3s node
        };
        paths = [];
        auto_update_enable = true;
        urls = [
          "https://raw.githubusercontent.com/2143-Labs/2143-59s/main/base/headscale/derp-map.yaml"
        ];
      };

      # ACLs — allow all nodes in the tailnet
      acl_policy_path = "";
    };

    # Default ACL: allow all traffic within the tailnet
    aclPolicy = ''
      {
        "acls": [
          {"action": "accept", "src": ["*"], "dst": ["*:*"]}
        ]
      }
    '';
  };

  # Allow external connections to headscale (for initial join and ongoing coordination)
  # Post-bootstrap, restrict to Tailscale interface only
  networking.firewall.allowedTCPPorts = [443 8080];

  # systemd: ensure headscale starts before tailscale on the same host
  systemd.services.tailscale = {
    after = ["headscale.service"];
    wants = ["headscale.service"];
  };
}
