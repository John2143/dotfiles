#!/usr/bin/env python3
"""Dynamic zone.db generator — queries Hetzner API for floating IPs, renders BIND zone file.

No hardcoded IPs. Region labels on Hetzner floating IPs are the source of truth.
Region → FIP mapping is discovered at runtime via `hcloud floating-ip list`.

Health checking: before including a region's FIP in zone.db, queries the coredns
on that FIP for a health TXT record. Unhealthy regions are excluded, so DNS
clients never receive dead IPs. Failover delay: ≤60s (generator interval) +
≤30s (coredns reload) + ≤60s (TTL) = ≤150s worst case.

Zone template: lists DOMAINS (not IPs) and which regions each domain should resolve to.
Special entries: tailnet hosts use Tailscale MagicDNS IPs (stable across reprovisions).
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone


# ── Zone template ──────────────────────────────────────────────────────────
# Format: { "domain_name": { "regions": ["region1", ...], "ttl": 60 } }
# "regions" match the "region" label on Hetzner floating IPs.
# A domain with no "regions" key is a static-entry (e.g., headscale via tailnet).
ZONE_CONFIG = json.loads(os.environ.get("ZONE_CONFIG", "{}"))
FALLBACK_TTL = os.environ.get("ZONE_TTL", "60")

# ── Hetzner API ────────────────────────────────────────────────────────────

def get_hetzner_fips() -> dict[str, str]:
    """Query Hetzner for floating IPs. Returns {region: ip}."""
    result = subprocess.run(
        ["hcloud", "floating-ip", "list", "-o", "json"],
        capture_output=True, text=True, check=True,
        env={**os.environ, "HCLOUD_TOKEN": read_token()},
    )
    fips: dict[str, str] = {}
    for fip in json.loads(result.stdout):
        labels = fip.get("labels") or {}
        region = labels.get("region")
        if region:
            fips[region] = fip["ip"]
    return fips


def read_token() -> str:
    """Read Hetzner Cloud API token from agenix-decrypted file."""
    token_path = "/run/agenix/hetzner/hcloud-token"
    try:
        with open(token_path) as f:
            return f.read().strip()
    except FileNotFoundError:
        pass
    # Fallback: try the raw agenix secret
    try:
        result = subprocess.run(
            ["cat", "/run/agenix/hetzner/hcloud-token"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()
    except Exception:
        pass
    print("WARNING: could not read HCLOUD_TOKEN from agenix", file=sys.stderr)
    return os.environ.get("HCLOUD_TOKEN", "")


# ── Health checking ────────────────────────────────────────────────────────

def check_health(fip: str, timeout: int = 5) -> bool:
    """Check whether a node's coredns is responsive.

    Queries the health TXT record. Returns True if the coredns responds
    with the expected value, False on timeout, SERVFAIL, or connection refused.

    Timeout is kept short (5s) so health checking doesn't delay zone generation.
    """
    try:
        result = subprocess.run(
            ["dig", f"@{fip}", "health.gslb.9s.pics", "TXT", "+short",
             f"+time={timeout}", "+tries=1", "+noall", "+answer"],
            capture_output=True, text=True, timeout=timeout + 2,
        )
        output = result.stdout.strip()
        if 'health' in output.lower():
            return True
        # Also accept raw "ok" string (some dig formats omit quoting)
        if output and 'ok' in output.lower():
            return True
        if result.returncode != 0:
            print(f"  health check FAILED for {fip}: dig exit code {result.returncode}", file=sys.stderr)
            return False
        print(f"  health check FAILED for {fip}: unexpected response '{output[:80]}'", file=sys.stderr)
        return False
    except subprocess.TimeoutExpired:
        print(f"  health check TIMEOUT for {fip}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  health check ERROR for {fip}: {e}", file=sys.stderr)
        return False


# ── Zone file generation ────────────────────────────────────────────────────

def render_zone(fips: dict[str, str], config: dict) -> str:
    """Render a BIND zone file from region→IP mapping and domain config.

    Excludes regions whose coredns fails the health check.
    """
    # Health-check all FIPs first
    healthy: dict[str, str] = {}
    unhealthy: list[str] = []
    for region, ip in sorted(fips.items()):
        status = check_health(ip)
        if status:
            healthy[region] = ip
        else:
            unhealthy.append(region)

    if unhealthy:
        print(f"HEALTH: excluding regions {unhealthy} (zone will use {list(healthy.keys())})",
              file=sys.stderr)

    if not healthy:
        print("CRITICAL: all regions unhealthy — generating zone with no A records!", file=sys.stderr)
        # Fall back to all FIPs to avoid a completely empty zone (DNS outage > partial outage)
        healthy = fips
        print(f"FALLBACK: using all {len(fips)} FIPs (all regions unhealthy)", file=sys.stderr)

    serial = datetime.now(timezone.utc).strftime("%Y%m%d%H")
    ns_ips = list(healthy.values())
    ns_names = [f"ns{i+1}" for i in range(len(ns_ips))]

    lines = [
        f"$ORIGIN gslb.9s.pics.",
        f"@   3600 IN SOA ns1.9s.pics. hostmaster.9s.pics. {serial} 7200 1800 86400 3600",
        "",
        "; Nameservers — auto-generated from Hetzner floating IPs",
    ]
    # NS records
    for ns in ns_names:
        lines.append(f"@   3600 IN NS  {ns}.9s.pics.")
    lines.append("")

    # Glue A records for nameservers
    for ns, ip in zip(ns_names, ns_ips):
        lines.append(f"{ns}  3600 IN A   {ip}")
    lines.append("")

    # Health check TXT records — one per region, used by peer nodes for liveness checks
    lines.append("; Health check endpoints — queried by peer nodes")
    for region, ip in sorted(healthy.items()):
        lines.append(f"health.{region}  30 IN TXT  \"ok\"")
    lines.append("")

    # Application A records
    lines.append("; Application A records")
    for domain, cfg in sorted(config.items()):
        regions = cfg.get("regions", [])
        ttl = cfg.get("ttl", FALLBACK_TTL)
        static_ip = cfg.get("ip")  # For tailnet/static entries

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
    fips = get_hetzner_fips()
    if not fips:
        print("ERROR: No Hetzner floating IPs found", file=sys.stderr)
        sys.exit(1)

    print(f"Discovered FIPs: {fips}", file=sys.stderr)

    config = ZONE_CONFIG or {
        "openfront":       {"regions": list(fips.keys())},
        "simulation-api":  {"regions": list(fips.keys())},
        "john2143":        {"regions": list(fips.keys())},
        "headscale":       {"ip": "100.64.0.14", "ttl": 3600},
    }

    zone_text = render_zone(fips, config)
    apply_configmap(zone_text)
    print("zone.db updated successfully", file=sys.stderr)


if __name__ == "__main__":
    main()
