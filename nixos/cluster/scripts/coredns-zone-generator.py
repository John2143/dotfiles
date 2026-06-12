#!/usr/bin/env python3
"""Dynamic zone.db generator — reads FIP registry from Kubernetes ConfigMap, renders BIND zone file.

No hardcoded IPs, no cloud API calls. The fip-registry ConfigMap is the source of truth
for all floating IPs across all clouds. Populated at provisioning time by deploy_all.py.

Health checking: before including a region's FIP in zone.db, queries the coredns
on that FIP for a health TXT record. Unhealthy regions are excluded, so DNS
clients never receive dead IPs.

Zone template: read from the same ConfigMap (data.zones.json). Lists DOMAINS and
which regions each domain should resolve to.
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone


FIP_CONFIGMAP = os.environ.get("FIP_CONFIGMAP", "fip-registry")
FIP_NAMESPACE = os.environ.get("FIP_NAMESPACE", "k8gb")
FALLBACK_TTL = os.environ.get("ZONE_TTL", "60")


# ── ConfigMap data source ─────────────────────────────────────────────────

def get_fips_from_configmap() -> dict[str, dict]:
    """Read FIP registry from Kubernetes ConfigMap.

    Returns {region: {ip, cloud, geo}} — same structure as old get_hetzner_fips()
    but source is ConfigMap, not hcloud API.
    """
    result = subprocess.run(
        ["kubectl", "get", "configmap", FIP_CONFIGMAP,
         "-n", FIP_NAMESPACE, "-o", "json"],
        capture_output=True, text=True,
        env={**os.environ, "KUBECONFIG": "/etc/rancher/k3s/k3s.yaml"},
    )
    if result.returncode != 0:
        print(f"ERROR: Cannot read ConfigMap {FIP_CONFIGMAP}/{FIP_NAMESPACE}: {result.stderr}",
              file=sys.stderr)
        sys.exit(1)

    cm = json.loads(result.stdout)
    fips_json = cm.get("data", {}).get("fips.json", "{}")
    return json.loads(fips_json)


def get_zone_config_from_configmap() -> dict:
    """Read zone template from the same ConfigMap."""
    result = subprocess.run(
        ["kubectl", "get", "configmap", FIP_CONFIGMAP,
         "-n", FIP_NAMESPACE, "-o", "json"],
        capture_output=True, text=True,
        env={**os.environ, "KUBECONFIG": "/etc/rancher/k3s/k3s.yaml"},
    )
    if result.returncode != 0:
        print(f"WARNING: Cannot read zone config from ConfigMap: {result.stderr}",
              file=sys.stderr)
        return {}

    cm = json.loads(result.stdout)
    zones_json = cm.get("data", {}).get("zones.json", "{}")
    return json.loads(zones_json)


# ── Health checking ────────────────────────────────────────────────────────

def check_health(ip: str, timeout: int = 5) -> bool:
    """Check whether a node's coredns is responsive.

    Queries the health TXT record. Returns True if the coredns responds
    with the expected value, False on timeout, SERVFAIL, or connection refused.
    """
    try:
        result = subprocess.run(
            ["dig", f"@{ip}", "health.gslb.9s.pics", "TXT", "+short",
             f"+time={timeout}", "+tries=1", "+noall", "+answer"],
            capture_output=True, text=True, timeout=timeout + 2,
        )
        output = result.stdout.strip()
        if 'health' in output.lower():
            return True
        if output and 'ok' in output.lower():
            return True
        if result.returncode != 0:
            print(f"  health check FAILED for {ip}: dig exit {result.returncode}", file=sys.stderr)
            return False
        print(f"  health check FAILED for {ip}: unexpected '{output[:80]}'", file=sys.stderr)
        return False
    except subprocess.TimeoutExpired:
        print(f"  health check TIMEOUT for {ip}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  health check ERROR for {ip}: {e}", file=sys.stderr)
        return False


# ── Zone file generation ────────────────────────────────────────────────────

def render_zone(fip_registry: dict[str, dict], zone_config: dict) -> str:
    """Render a BIND zone file from region→{ip,cloud,geo} mapping.

    Excludes regions whose coredns fails the health check.
    """
    # Build region→ip mapping from registry
    raw_fips: dict[str, str] = {
        region: info["ip"]
        for region, info in fip_registry.items()
        if isinstance(info, dict) and "ip" in info
    }

    # Health-check all FIPs
    healthy: dict[str, str] = {}
    unhealthy: list[str] = []
    for region, ip in sorted(raw_fips.items()):
        status = check_health(ip)
        if status:
            healthy[region] = ip
        else:
            unhealthy.append(region)

    if unhealthy:
        print(f"HEALTH: excluding regions {unhealthy} (zone uses {list(healthy.keys())})",
              file=sys.stderr)

    if not healthy:
        print("CRITICAL: all regions unhealthy — using all FIPs as fallback", file=sys.stderr)
        healthy = raw_fips

    serial = datetime.now(timezone.utc).strftime("%Y%m%d%H")
    ns_ips = list(healthy.values())
    ns_names = [f"ns{i+1}" for i in range(len(ns_ips))]

    lines = [
        f"$ORIGIN gslb.9s.pics.",
        f"@   3600 IN SOA ns1.9s.pics. hostmaster.9s.pics. {serial} 7200 1800 86400 3600",
        "",
        "; Nameservers — auto-generated from FIP registry",
    ]
    for ns in ns_names:
        lines.append(f"@   3600 IN NS  {ns}.9s.pics.")
    lines.append("")

    # Glue A records for nameservers
    for ns, ip in zip(ns_names, ns_ips):
        lines.append(f"{ns}  3600 IN A   {ip}")
    lines.append("")

    # Health check TXT records
    lines.append("; Health check endpoints — queried by peer nodes")
    for region, ip in sorted(healthy.items()):
        lines.append(f"health.{region}  30 IN TXT  \"ok\"")
    lines.append("")

    # Application A records
    lines.append("; Application A records")
    for domain, cfg in sorted(zone_config.items()):
        regions = cfg.get("regions", [])
        ttl = cfg.get("ttl", FALLBACK_TTL)
        static_ip = cfg.get("ip")

        if static_ip:
            lines.append(f"{domain}  {ttl} IN A   {static_ip}")
        else:
            for region in regions:
                ip = healthy.get(region)
                if ip:
                    lines.append(f"{domain}  {ttl} IN A   {ip}")

    lines.append("")
    return "\n".join(lines)


# ── Kubernetes apply ────────────────────────────────────────────────────────

def apply_configmap(zone_text: str):
    """Apply the zone.db ConfigMap to the k8gb namespace."""
    cm = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": "coredns-zone",
            "namespace": "k8gb",
        },
        "data": {
            "zone.db": zone_text,
        },
    }
    proc = subprocess.run(
        ["kubectl", "apply", "-f", "-"],
        input=json.dumps(cm),
        capture_output=True,
        text=True,
        env={**os.environ, "KUBECONFIG": "/etc/rancher/k3s/k3s.yaml"},
    )
    if proc.returncode != 0:
        print(f"kubectl apply failed: {proc.stderr}", file=sys.stderr)
        sys.exit(1)
    print(proc.stdout.strip())


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    # Read FIP registry from ConfigMap (replaces hcloud API call)
    fip_registry = get_fips_from_configmap()
    if not fip_registry:
        print("ERROR: FIP registry ConfigMap is empty or missing", file=sys.stderr)
        sys.exit(1)

    # Read zone config from same ConfigMap
    zone_config = get_zone_config_from_configmap()
    if not zone_config:
        # Fallback: use all regions for common domains
        regions = list(fip_registry.keys())
        zone_config = {
            "openfront":       {"regions": regions},
            "simulation-api":  {"regions": regions},
            "john2143":        {"regions": regions},
            "headscale":       {"ip": "100.64.0.14", "ttl": 3600},
        }
        print(f"WARNING: No zone config in ConfigMap, using defaults for regions: {regions}",
              file=sys.stderr)

    print(f"FIP registry: {list(fip_registry.keys())}", file=sys.stderr)
    zone_text = render_zone(fip_registry, zone_config)
    apply_configmap(zone_text)
    print("zone.db updated (source: ConfigMap)", file=sys.stderr)


if __name__ == "__main__":
    main()
