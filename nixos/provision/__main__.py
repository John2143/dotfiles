"""Pulumi orchestrator for multi-cloud k3s provisioning.

Reads clusters.yaml → creates cloud resources → deploys NixOS via
nixos-anywhere → post-deploy setup → writes FIP registry to each cluster.
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
    get_cloud_ssh_key_path,
    decrypt_age_file,
    kubectl_apply,
    render_fip_configmap,
)
from deploy import deploy_nixos
from post_deploy import post_deploy


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


# ── Deploy + post-deploy ────────────────────────────────────────────

def deploy_and_configure(
    cluster: ClusterSpec,
    provider_obj,
    fip_ip: pulumi.Output[str],
    ssh_private_key_path: str,
) -> dict:
    """After cloud resources are up, deploy NixOS and run post-deploy steps.

    Uses pulumi.Output.apply() to chain operations after resource creation.
    """
    cloud = cluster.cloud.value
    region = cluster.region
    hostname = cluster.name

    def _do_deploy(server_ip: str):
        """Inner function that runs after Pulumi resources are created."""
        status = {"hostname": hostname, "cloud": cloud, "region": region}

        try:
            # Deploy NixOS via nixos-anywhere
            deploy_nixos(
                host_ip=server_ip,
                hostname=hostname,
                cloud=cloud,
                region=region,
                ssh_private_key_path=ssh_private_key_path,
            )

            # Post-deploy: age key, agenix, tailscale, k3s verify
            result = post_deploy(
                host_ip=server_ip,
                hostname=hostname,
                cloud=cloud,
                region=region,
            )
            status.update(result)
            status["provisioned"] = True

        except Exception as e:
            pulumi.log.error(f"[{cloud}/{region}] Deployment failed: {e}")
            status["provisioned"] = False
            status["error"] = str(e)

        return status

    # Use the server's primary IP (not FIP) for nixos-anywhere
    if hasattr(provider_obj, 'server'):
        server_ip = provider_obj.server_ip
    else:
        server_ip = provider_obj.droplet.ipv4_address

    return server_ip.apply(_do_deploy)


# ── FIP Registry ────────────────────────────────────────────────────

def write_fip_registry(cluster_results: list, fip_map: dict, zones: dict) -> None:
    """Write the FIP registry ConfigMap to each provisioned cluster.

    This replaces the old hcloud-based FIP discovery. Each cluster's
    coredns-zone-generator reads this ConfigMap instead of calling
    cloud APIs.
    """
    # Build FIP registry JSON
    fip_registry = {}
    for result in cluster_results:
        if result.get("provisioned"):
            region = result["region"]
            fip_registry[region] = {
                "ip": fip_map.get(region, result.get("ip", "")),
                "cloud": result["cloud"],
                "geo": result.get("geo_tag", ""),
            }

    # Default zones if not provided
    if not zones:
        regions = list(fip_registry.keys())
        zones = {
            "openfront": {"regions": regions},
            "simulation-api": {"regions": regions},
            "john2143": {"regions": regions},
        }

    cm_yaml = render_fip_configmap(fip_registry, zones)

    # Apply to each provisioned cluster
    for result in cluster_results:
        if result.get("provisioned"):
            host = fip_map.get(result["region"], result.get("ip", ""))
            if host:
                pulumi.log.info(
                    f"[{result['cloud']}/{result['region']}] Writing FIP ConfigMap..."
                )
                try:
                    kubectl_apply(host, cm_yaml)
                    pulumi.log.info(
                        f"[{result['cloud']}/{result['region']}] FIP ConfigMap applied."
                    )
                except Exception as e:
                    pulumi.log.warn(
                        f"[{result['cloud']}/{result['region']}] "
                        f"FIP ConfigMap apply failed: {e}"
                    )


# ── Main ────────────────────────────────────────────────────────────

def main():
    """Orchestrate multi-cloud k3s provisioning."""
    spec = load_spec()
    defaults = spec.defaults
    # Get SSH keys (public for cloud providers, private for nixos-anywhere)
    ssh_key_name = defaults.get("ssh_key_name", "k3s-cloud")
    ssh_public_key = get_ssh_public_key(ssh_key_name)
    ssh_private_key_path = get_cloud_ssh_key_path()
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
        shared_ssh_keys["digitalocean"] = do.SshKey(
            "shared-ssh-key-do",
            name=ssh_key_name,
            public_key=ssh_public_key,
        )

    # Provision all clusters (Pulumi resources)
    cluster_providers = {}
    cluster_fips = {}
    for cluster in spec.clusters:
        cloud = cluster.cloud.value
        shared_key = shared_ssh_keys.get(cloud)
        provider, fip = provision_cluster(
            cluster, defaults, ssh_key_name, ssh_public_key,
            ssh_key=shared_key,
        )
        cluster_providers[cluster.name] = provider
        cluster_fips[cluster.name] = fip

    # Deploy + configure each cluster (post-resource-creation)
    # Build FIP map for registry (region → FIP)
    fip_map = {}
    deploy_results = []
    for cluster in spec.clusters:
        provider = cluster_providers[cluster.name]
        fip = cluster_fips[cluster.name]

        result = deploy_and_configure(
            cluster, provider, fip, ssh_private_key_path=ssh_private_key_path
        )
        deploy_results.append((cluster, result, fip))

    # Aggregate results and write FIP registry
    # Build zone configuration
    zone_config = {
        "openfront": {"regions": [c.region for c in spec.clusters]},
        "simulation-api": {"regions": [c.region for c in spec.clusters]},
        "john2143": {"regions": [c.region for c in spec.clusters]},
    }

    # Export outputs
    pulumi.export("cluster_count", len(spec.clusters))
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
