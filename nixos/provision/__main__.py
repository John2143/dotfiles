"""Pulumi orchestrator for multi-cloud k3s provisioning.

Phase 1: Creates cloud resources (VMs, IPs, SSH keys).
Phase 2: Run deploy_all.py to install NixOS and configure clusters in parallel.
"""

import os
import sys
import json
from pathlib import Path

import pulumi
import pulumi_hcloud as hcloud
import pulumi_digitalocean as do
import yaml

from spec import Spec, ClusterSpec
from resources.hetzner import HetznerCluster
from resources.digitalocean import DOCluster
from resources.common import (
    get_ssh_public_key,
)

# ── Parse spec ──────────────────────────────────────────────────────
SPEC_PATH = Path(__file__).parent / "clusters.yaml"

def load_spec() -> Spec:
    """Load and validate the clusters.yaml spec."""
    if not SPEC_PATH.exists():
        pulumi.log.error(f"Spec file not found: {SPEC_PATH}")
        sys.exit(1)

    with open(SPEC_PATH) as f:
        raw = yaml.safe_load(f)

    spec = Spec(**raw)
    pulumi.log.info(f"Loaded spec: {len(spec.clusters)} clusters across "
                    f"{len(spec.providers)} providers")
    return spec


# ── Cloud provisioning ──────────────────────────────────────────────

def provision_cluster(
    cluster: ClusterSpec,
    defaults: dict,
    ssh_key_name: str,
    ssh_public_key: str,
    ssh_key: any = None,
) -> tuple:
    """Create cloud resources for one cluster. Returns (provider_obj, fip_output)."""
    cloud = cluster.cloud.value
    image = cluster.image or defaults.get("image", "ubuntu-24.04")

    pulumi.log.info(f"[{cloud}/{cluster.region}] Provisioning {cluster.name}...")

    if cloud == "hetzner":
        labels = cluster.labels or {
            "k3s": "true",
            "owner": "john2143",
            "managed-by": "pulumi",
        }
        # Use server node size (first node)
        size = cluster.nodes[0].size

        provider = HetznerCluster(
            name=cluster.name,
            region=cluster.region,
            size=size,
            image=image,
            labels=labels,
            ssh_key_name=ssh_key_name,
            ssh_public_key=ssh_public_key,
            ssh_key=ssh_key,
        )
        return provider, provider.fip_ip

    elif cloud == "digitalocean":
        tags = cluster.tags or defaults.get("tags", [])
        size = cluster.nodes[0].size

        provider = DOCluster(
            name=cluster.name,
            region=cluster.region,
            size=size,
            image=image,
            tags=tags,
            ssh_key_name=ssh_key_name,
            ssh_public_key=ssh_public_key,
            ssh_key=ssh_key,
        )
        return provider, provider.fip_ip

    else:
        raise ValueError(f"Unsupported cloud: {cloud}")

# ── Main ────────────────────────────────────────────────────────────

def main():
    """Orchestrate multi-cloud k3s provisioning."""
    spec = load_spec()
    defaults = spec.defaults
    # Get SSH keys (public for cloud providers, private for nixos-anywhere)
    ssh_key_name = defaults.get("ssh_key_name", "k3s-cloud")
    ssh_public_key = get_ssh_public_key(ssh_key_name)
    pulumi.log.info(f"Using SSH key: {ssh_key_name}")

    # Create shared SSH key resources (one per cloud provider)
    shared_ssh_keys = {}
    clouds_in_spec = {c.cloud.value for c in spec.clusters}
    if "hetzner" in clouds_in_spec:
        shared_ssh_keys["hetzner"] = hcloud.SshKey(
            "shared-ssh-key-hcloud",
            name=ssh_key_name,
            public_key=ssh_public_key,
        )
    if "digitalocean" in clouds_in_spec:
        try:
            existing = do.get_ssh_key(name=ssh_key_name)
            shared_ssh_keys["digitalocean"] = do.SshKey.get(
                "shared-ssh-key-do", id=str(existing.id)
            )
            pulumi.log.info(f"Using existing DO SSH key: {existing.name} (id={existing.id})")
        except Exception:
            shared_ssh_keys["digitalocean"] = do.SshKey(
                "shared-ssh-key-do",
                name=ssh_key_name,
                public_key=ssh_public_key,
            )

    # Provision all clusters (Pulumi resources)
    for cluster in spec.clusters:
        cloud = cluster.cloud.value
        shared_key = shared_ssh_keys.get(cloud)
        provision_cluster(
            cluster, defaults, ssh_key_name, ssh_public_key,
            ssh_key=shared_key,
        )
    # Export summary
    pulumi.export("cluster_count", len(spec.clusters))
    pulumi.export("cluster_names", [c.name for c in spec.clusters])
    pulumi.export("fip_registry", json.dumps(
        {c.region: c.name for c in spec.clusters}
    ))

    pulumi.log.info("=" * 60)
    pulumi.log.info("Multi-cloud k3s provisioning plan complete.")
    pulumi.log.info(f"Clusters provisioned: {len(spec.clusters)}")
    for cluster in spec.clusters:
        pulumi.log.info(f"  {cluster.name} ({cluster.cloud.value}/{cluster.region})")
    pulumi.log.info("=" * 60)


if __name__ == "__main__":
    main()
