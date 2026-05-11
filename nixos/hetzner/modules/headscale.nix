# Headscale — Self-hosted Tailscale coordination server
#
# Runs on the Home Pi. All Hetzner nodes + home machines join this tailnet.
# Listens on 0.0.0.0:8080 so closet's Traefik can reverse-proxy to it.
{
  ...
}: {
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;

    settings = {
      server_url = "https://headscale.9s.pics";

      derp = {
        server = {
          enabled = false;
        };
        paths = [];
        auto_update_enable = true;
        urls = [
          "https://raw.githubusercontent.com/2143-Labs/2143-59s/main/base/headscale/derp-map.yaml"
        ];
      };
    };

    # DNS config (new API — moved from settings.dns_config to top-level dns)
    dns = {
      magic_dns = true;
      base_domain = "9s.pics";
      nameservers.global = ["1.1.1.1" "9.9.9.9"];
      override_local_dns = true;
    };
  };

  # Allow external connections to headscale
  networking.firewall.allowedTCPPorts = [8080];

  # systemd: ensure headscale starts before tailscale on the same host
  systemd.services.tailscale = {
    after = ["headscale.service"];
    wants = ["headscale.service"];
  };
}
