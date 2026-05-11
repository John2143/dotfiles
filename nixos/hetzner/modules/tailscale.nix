# Tailscale / Headscale VPN
#
# Currently points at tailscale.com. Once Headscale is running on the Home Pi,
# swap to:
#   services.tailscale.extraUpFlags = ["--login-server=https://headscale.<YOUR_DOMAIN>"];
#
# The Home Pi runs: services.headscale.enable = true
# Hetzner nodes are Headscale clients — same tailscale binary, different server.
{...}: {
  services.tailscale.enable = true;
}
