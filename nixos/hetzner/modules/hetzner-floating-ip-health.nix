# Floating IP Health Checker — auto-reassign floating IP on node failure
#
# Each region has one floating IP that should always point to a healthy node.
# Uses Hetzner Cloud API via hcloud CLI.
# Requires: HCLOUD_TOKEN agenix secret, hcloud CLI on PATH.
{
  config,
  lib,
  pkgs,
  compName,
  ...
}: let
  # Region → floating IP label mapping
  # Floating IPs must be labeled via hcloud floating-ip add-label during provisioning.
  regionLabels = {
    "k3s-ashburn"   = "ashburn";
    "k3s-hillsboro" = "hillsboro";
    "k3s-nuremberg" = "nuremberg";
  };

  myRegion = regionLabels.${compName} or null;
  enabled = myRegion != null;
in {
  # agenix secret: Hetzner Cloud API token for floating IP management
  age.secrets."hetzner/hcloud-token" = {
    file = ../secrets/hetzner/hcloud-token.age;
    owner = "root";
    group = "root";
  };

  systemd.services.floating-ip-health = lib.mkIf enabled {
    description = "Floating IP health check and reassignment for ${myRegion}";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.hcloud pkgs.iproute2 pkgs.python3];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail

      TOKEN="$(cat ${config.age.secrets."hetzner/hcloud-token".path})"
      export HCLOUD_TOKEN="$TOKEN"

      REGION="${myRegion}"
      MY_HOSTNAME="${compName}"

      echo "Floating IP health check for $MY_HOSTNAME (region: $REGION)"

      # Find the floating IP for this region
      python3 <<PYEOF
import json, subprocess, sys

result = subprocess.run(
    ["hcloud", "floating-ip", "list", "-o", "json"],
    capture_output=True, text=True, check=True
)
data = json.loads(result.stdout)
for fip in data:
    labels = fip.get("labels", {})
    if labels.get("region") == "${myRegion}":
        print(json.dumps(fip))
        sys.exit(0)
sys.exit(1)
PYEOF
      FIP_JSON=$(python3 <<PYEOF
import json, os, subprocess, sys

token = os.environ.get("HCLOUD_TOKEN", "")
result = subprocess.run(
    ["hcloud", "floating-ip", "list", "-o", "json"],
    capture_output=True, text=True, check=True
)
data = json.loads(result.stdout)
for fip in data:
    labels = fip.get("labels", {})
    if labels.get("region") == "${myRegion}":
        print(fip["id"], fip["ip"], fip.get("server", {}).get("name", ""))
        sys.exit(0)
sys.exit(1)
PYEOF
) || true

      if [ -z "$FIP_JSON" ]; then
        echo "No floating IP found for region $REGION — skipping"
        exit 0
      fi

      FIP_ID=$(echo "$FIP_JSON" | cut -d' ' -f1)
      FIP_IP=$(echo "$FIP_JSON" | cut -d' ' -f2)
      CURRENT_SERVER=$(echo "$FIP_JSON" | cut -d' ' -f3)

      echo "Floating IP $FIP_IP (ID: $FIP_ID) currently on server: $CURRENT_SERVER"

      # Check if this node is the current holder
      if [ "$CURRENT_SERVER" = "$MY_HOSTNAME" ]; then
        echo "This node ($MY_HOSTNAME) holds the floating IP. Checking health..."

        # Health check: verify k3s is running
        if ! systemctl is-active --quiet k3s 2>/dev/null; then
          echo "k3s is not running — this node is unhealthy. Releasing floating IP."
          hcloud floating-ip unassign "$FIP_ID" 2>/dev/null || true
          echo "Floating IP $FIP_IP released"
          exit 0
        fi

        echo "Node healthy. Ensuring floating IP on local interface..."
        ip addr show dev enp1s0 | grep -q "$FIP_IP" || ip addr add "$FIP_IP/32" dev enp1s0
        ip addr show dev lo | grep -q "$FIP_IP" || ip addr add "$FIP_IP/32" dev lo
        echo "Floating IP $FIP_IP added to local interfaces"
        systemctl restart split-ip-firewall 2>/dev/null || true
        echo "Firewall restarted for floating IP $FIP_IP"
        exit 0

      elif [ -z "$CURRENT_SERVER" ]; then
        echo "Floating IP is not assigned. Claiming for $MY_HOSTNAME..."
        MY_ID=$(python3 <<PYEOF
import json, os, subprocess

token = os.environ.get("HCLOUD_TOKEN", "")
result = subprocess.run(
    ["hcloud", "server", "list", "-o", "json"],
    capture_output=True, text=True, check=True
)
data = json.loads(result.stdout)
for s in data:
    if s["name"] == "${compName}":
        print(s["id"])
        break
PYEOF
)
        if [ -n "$MY_ID" ]; then
          hcloud floating-ip assign "$FIP_ID" "$MY_ID" 2>/dev/null || true
          echo "Floating IP $FIP_IP assigned to $MY_HOSTNAME"
          # Add floating IP to local interfaces
          ip addr show dev enp1s0 | grep -q "$FIP_IP" || ip addr add "$FIP_IP/32" dev enp1s0
          ip addr show dev lo | grep -q "$FIP_IP" || ip addr add "$FIP_IP/32" dev lo
          echo "Floating IP $FIP_IP added to local interfaces"
          # Restart firewall to pick up the new floating IP
          systemctl restart split-ip-firewall 2>/dev/null || true
          echo "Firewall restarted for floating IP \$FIP_IP"

        fi
        exit 0

      else
        echo "Floating IP is on $CURRENT_SERVER (not this node). Checking holder health..."

        # Ping the current holder's floating IP
        if ping -c 2 -W 3 "$FIP_IP" &>/dev/null; then
          echo "Current holder is reachable — no action needed"
          exit 0
        fi

        echo "Current holder $CURRENT_SERVER is unreachable. Checking via Hetzner API..."

        # Double-check via API
        CURRENT_STATUS=$(hcloud server describe "$CURRENT_SERVER" -o json 2>/dev/null | \
          python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status') or 'unknown')" 2>/dev/null || echo "unknown")

        if [ "$CURRENT_STATUS" = "running" ]; then
          echo "Hetzner reports $CURRENT_SERVER as running — no action"
          exit 0
        fi

        echo "Server $CURRENT_SERVER status: $CURRENT_STATUS — claiming floating IP..."
        MY_ID=$(python3 <<PYEOF
import json, os, subprocess

token = os.environ.get("HCLOUD_TOKEN", "")
result = subprocess.run(
    ["hcloud", "server", "list", "-o", "json"],
    capture_output=True, text=True, check=True
)
data = json.loads(result.stdout)
for s in data:
    if s["name"] == "${compName}":
        print(s["id"])
        break
PYEOF
)
        if [ -n "$MY_ID" ]; then
          hcloud floating-ip assign "$FIP_ID" "$MY_ID" 2>/dev/null || true
          echo "Floating IP $FIP_IP reassigned to $MY_HOSTNAME"
          # Restart firewall to pick up the new floating IP
          systemctl restart split-ip-firewall 2>/dev/null || true
          echo "Firewall restarted for floating IP \$FIP_IP"
        fi
      fi
    '';
  };

  # Run every 60 seconds
  systemd.timers.floating-ip-health = lib.mkIf enabled {
    description = "Floating IP health check every 60s for ${myRegion}";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/1";
      OnUnitInactiveSec = "60";
      Persistent = true;
    };
  };
}
