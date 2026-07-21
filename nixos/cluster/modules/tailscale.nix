# Tailscale / Headscale VPN client
#
# Parameterized: Home Pi connects to local headscale (http://localhost:6767),
# Hetzner nodes connect to the Home Pi's headscale server via its Tailscale FQDN.
#
# All nodes use a preauth key from agenix to auto-join the tailnet.
{
  config,
  lib,
  ...
}: {
  options.custom.headscaleServer = lib.mkOption {
    type = lib.types.str;
    default = "http://headscale.9s.pics:6767";
    description = "Headscale server URL for tailscale up --login-server";
    example = "http://localhost:6767";
  };

  config = {
    services.tailscale = {
      enable = true;
      extraUpFlags = [
        "--login-server=${config.custom.headscaleServer}"
      ];


    # Preauth key enrollment is handled dynamically by post_deploy.py
    # (create_kubecontrol_preauth_key) — no static authKeyFile needed.
    };
  };
}
