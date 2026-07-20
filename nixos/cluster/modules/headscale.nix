# Headscale — Self-hosted Tailscale coordination server
#
# Runs on the Home Pi. All Hetzner nodes + home machines join this tailnet.
# Tailscale on the same host connects via localhost:6767.
# External nodes connect via headscale.9s.pics (routed through closet's Traefik).
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 6767;

    settings = {
      server_url = "http://headscale.9s.pics:6767";

      dns = {
        magic_dns = true;
        base_domain = "ts.9s.pics";
        override_local_dns = true;
        nameservers.global = ["1.1.1.1" "9.9.9.9"];
      };

      # DERP relay servers — one per region on raw IPs
      # DERP relay servers — Tailscale's public DERP map
      derp = {
        urls = ["https://controlplane.tailscale.com/derpmap/default"];
        paths = [];
        auto_update_enabled = true;
        server.enabled = false;
      };

      policy.path = "/etc/headscale/policy.json";
    };
  };

  # Deny-by-default grants policy — only tag:kube-control can reach each other on 6443 + internet for DERP
  environment.etc."headscale/policy.json" = {
    text = ''
      {
        "acls": [
          {"action": "accept", "src": ["tag:kube-control"], "dst": ["tag:kube-control:6443"]},
          {"action": "accept", "src": ["tag:kube-control"], "dst": ["*:*"]}
        ],
        "tagOwners": {
          "tag:kube-control": ["hetzner-nodes@"]
        },
        "autoApprovers": {
          "routes": {
            "192.168.5.10/32": ["hetzner-nodes@"]
          }
        }
      }
    '';
    mode = "0440";
    user = "headscale";
    group = "headscale";
  };

  # systemd: ensure headscale starts before tailscale on the same host
  systemd.services.tailscaled = {
    after = ["headscale.service"];
    wants = ["headscale.service"];
  };
  # Open firewall for headscale API (headscale.nix:58)
  networking.firewall.allowedTCPPorts = [
    6767 # headscale HTTP API
  ];

}
