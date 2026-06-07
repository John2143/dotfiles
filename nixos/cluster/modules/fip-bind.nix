# Floating IP Loopback Binding
#
# On Hetzner Cloud, floating IP traffic arrives on the primary interface
# but responses must use the FIP as source address. This module binds the
# FIP to the loopback interface and sets up policy routing so outbound
# responses to FIP traffic use the FIP source.
#
# On clouds with true dual-IP (AWS, DO), this is not needed — the FIP
# appears as a secondary address on the primary interface.
#
# FIP is discovered from the fip-registry ConfigMap in k8gb namespace.
# Falls back gracefully if ConfigMap is not yet present.
{
  config,
  lib,
  pkgs,
  ...
}: let
  fipBindingScript = pkgs.writeShellScript "fip-loopback-bind" ''
    set -euo pipefail

    # Try to read FIP from Kubernetes ConfigMap
    FIP=""
    if KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get configmap fip-registry -n k8gb -o json 2>/dev/null | \
       ${pkgs.python3}/bin/python3 -c "
import json, sys
try:
    cm = json.load(sys.stdin)
    fips = json.loads(cm.get('data', {}).get('fips.json', '{}'))
    hostname = '$(hostname)'
    # Map hostname to region: hetzner-ashburn-k3s -> ashburn
    parts = hostname.split('-')
    if len(parts) >= 3:
        region = parts[1]
        for r, info in fips.items():
            if r == region or info.get('geo', '').endswith(region):
                print(info['ip'])
                break
except: pass
" 2>/dev/null; then
      FIP=$(${pkgs.python3}/bin/python3 -c "
import json, sys
try:
    cm = json.load(sys.stdin)
    fips = json.loads(cm.get('data', {}).get('fips.json', '{}'))
    hostname = '$(hostname)'
    parts = hostname.split('-')
    if len(parts) >= 3:
        region = parts[1]
        for r, info in fips.items():
            if r == region or info.get('geo', '').endswith(region):
                print(info['ip'])
                break
except: pass
" < <(KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get configmap fip-registry -n k8gb -o json 2>/dev/null))
    fi

    if [ -z "$FIP" ]; then
      echo "fip-loopback-bind: FIP not found in ConfigMap, skipping"
      exit 0
    fi

    # Check if already bound
    if ip addr show dev lo | grep -q "$FIP"; then
      echo "fip-loopback-bind: FIP $FIP already bound to lo"
      exit 0
    fi

    echo "fip-loopback-bind: Binding FIP $FIP to loopback"
    ip addr add "$FIP/32" dev lo

    # Policy routing: responses to FIP traffic must use FIP as source
    FIP_TABLE="fip"
    if ! ip rule show | grep -q "from $FIP"; then
      ip rule add from "$FIP" table "$FIP_TABLE" pref 100 2>/dev/null || true
      ip route add default via "$(ip -4 route get 8.8.8.8 | grep -oP 'via \K[\d.]+')" \
        dev "$(ip -4 route get 8.8.8.8 | grep -oP 'dev \K\S+')" \
        table "$FIP_TABLE" 2>/dev/null || true
    fi
  '';
in {
  systemd.services.fip-loopback-bind = {
    description = "Bind Floating IP to loopback interface";
    after = ["k3s.service" "network-online.target"];
    wants = ["k3s.service" "network-online.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.iproute2 pkgs.k3s pkgs.python3];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${fipBindingScript}";
  };
}
