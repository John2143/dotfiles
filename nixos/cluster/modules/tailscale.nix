# Tailscale / Headscale VPN client
#
# All nodes join the in-cluster headscale (argo workloads/headscale, reached
# over HTTPS at net.john2143.com, base_domain ts.2143.me).
#
# All nodes use a preauth key from agenix to auto-join the tailnet.
{
  config,
  lib,
  ...
}: {
  options.custom.headscaleServer = lib.mkOption {
    type = lib.types.str;
    default = "https://net.john2143.com";
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
