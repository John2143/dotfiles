#!/usr/bin/env python3
"""Dynamic zone.db generator — queries Hetzner API for floating IPs, renders BIND zone file.

No hardcoded IPs. Region labels on Hetzner floating IPs are the source of truth.
Region → FIP mapping is discovered at runtime via `hcloud floating-ip list`.

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


# ── Zone file generation ────────────────────────────────────────────────────

def render_zone(fips: dict[str, str], config: dict) -> str:
    """Render a BIND zone file from region→IP mapping and domain config."""
    serial = datetime.now(timezone.utc).strftime("%Y%m%d%H")
    ns_ips = list(fips.values())
    ns_names = [f"ns{i+1}" for i in range(len(ns_ips))]

    lines = [
        f"$ORIGIN 9s.pics.",
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
                ip = fips.get(region)
                if ip:
                    lines.append(f"{domain}  {ttl} IN A   {ip}")

    # Wildcard catch-all (all regions)
    lines.append("")
    lines.append("; Wildcard catch-all")
    for ip in ns_ips:
        lines.append(f"*  {FALLBACK_TTL} IN A   {ip}")

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
