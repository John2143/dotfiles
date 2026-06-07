"""Hetzner Cloud resources via pulumi-hcloud."""

import pulumi
import pulumi_hcloud as hcloud
from typing import Optional


class HetznerCluster:
    """Provisions a k3s node + floating IP on Hetzner Cloud."""

    def __init__(
        self,
        name: str,
        region: str,
        size: str,
        image: str,
        labels: dict,
        ssh_key_name: str,
        ssh_public_key: str,
        ssh_key: Optional[hcloud.SshKey] = None,
    ):
        self.name = name
        self.region = region

        # Map region names to Hetzner locations
        location_map = {
            "ashburn": "ash",
            "hillsboro": "hil",
        }
        location = location_map.get(region, region)

        # Use shared SSH key if provided, otherwise create one
        if ssh_key is None:
            ssh_key = hcloud.SshKey(
                f"{name}-ssh-key",
                name=ssh_key_name,
                public_key=ssh_public_key,
            )
        self.ssh_key = ssh_key

        # Create the server
        self.server = hcloud.Server(
            name,
            name=name,
            server_type=size,
            location=location,
            image=image,
            ssh_keys=[self.ssh_key.id],
            labels={**labels, "name": name},
            opts=pulumi.ResourceOptions(delete_before_replace=True),
        )

        # Create floating IP
        self.floating_ip = hcloud.FloatingIp(
            f"{name}-fip",
            name=f"{name}-fip",
            type="ipv4",
            home_location=location,
            labels={**labels, "component": "floating-ip"},
        )

        # Assign floating IP to server
        self.fip_assignment = hcloud.FloatingIpAssignment(
            f"{name}-fip-assign",
            floating_ip_id=self.floating_ip.id,
            server_id=self.server.id,
        )

        # Exports
        pulumi.export(f"{name}_server_ip", self.server.ipv4_address)
        pulumi.export(f"{name}_fip", self.floating_ip.ip_address)

    @property
    def server_ip(self) -> pulumi.Output[str]:
        return self.server.ipv4_address

    @property
    def fip_ip(self) -> pulumi.Output[str]:
        return self.floating_ip.ip_address
