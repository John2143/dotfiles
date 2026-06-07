"""DigitalOcean resources via pulumi-digitalocean."""

import pulumi
import pulumi_digitalocean as do
from typing import Optional


class DOCluster:
    """Provisions a k3s node + reserved IP on DigitalOcean."""

    def __init__(
        self,
        name: str,
        region: str,
        size: str,
        image: str,
        tags: list[str],
        ssh_key_name: str,
        ssh_public_key: str,
        ssh_key: Optional[do.SshKey] = None,
    ):
        self.name = name
        self.region = region

        # Use shared SSH key if provided, otherwise create one
        if ssh_key is None:
            ssh_key = do.SshKey(
                f"{name}-ssh-key",
                name=ssh_key_name,
                public_key=ssh_public_key,
            )
        self.ssh_key = ssh_key

        # Create the droplet
        self.droplet = do.Droplet(
            name,
            name=name,
            region=region,
            size=size,
            image=image,
            ssh_keys=[self.ssh_key.fingerprint],
            tags=[*tags, f"cluster:{name}"],
            opts=pulumi.ResourceOptions(delete_before_replace=True),
        )

        # Create reserved IP
        self.reserved_ip = do.ReservedIp(
            f"{name}-reserved-ip",
            region=region,
        )

        # Assign reserved IP to droplet
        self.ip_assignment = do.ReservedIpAssignment(
            f"{name}-ip-assign",
            ip_address=self.reserved_ip.ip_address,
            droplet_id=self.droplet.id.apply(lambda i: int(i)),
        )

        # Exports
        pulumi.export(f"{name}_server_ip", self.droplet.ipv4_address)
        pulumi.export(f"{name}_fip", self.reserved_ip.ip_address)

    @property
    def server_ip(self) -> pulumi.Output[str]:
        return self.droplet.ipv4_address

    @property
    def fip_ip(self) -> pulumi.Output[str]:
        return self.reserved_ip.ip_address
