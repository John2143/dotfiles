# Public edge on the two cloud voters: nginx passes raw TCP 80/443 to
# Traefik, which runs in the cluster with hostNetwork and binds only to
# 127.0.0.1:9080/9443 (cloud-argo platform/traefik). nginx never terminates
# TLS: it reads the SNI for routing (phase 4 maps home hostnames to the home
# connectors here) and prepends a PROXY v2 header, so Traefik sees the real
# client address and trusts that header only from 127.0.0.1.
#
# Living outside the cluster is deliberate: a broken Traefik rollout, or the
# control plane being down, cannot take the listener or a future home-site
# route with it.
{
  config,
  lib,
  ...
}: let
  self = config.custom.platform;
in {
  config = lib.mkIf self.edge {
    services.nginx = {
      enable = true;
      streamConfig = ''
        # Default: the cluster gateway. Phase 4 adds home hostnames above it.
        map $ssl_preread_server_name $edge_https_upstream {
          default 127.0.0.1:9443;
        }

        server {
          # IPv4 only until the IPv6 edge (card #576) adds AAAA records.
          listen 0.0.0.0:443;
          ssl_preread on;
          proxy_pass $edge_https_upstream;
          proxy_protocol on;
        }

        server {
          listen 0.0.0.0:80;
          proxy_pass 127.0.0.1:9080;
          proxy_protocol on;
        }
      '';
    };

    networking.firewall.allowedTCPPorts = [80 443];
  };
}
