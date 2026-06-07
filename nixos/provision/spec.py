"""Pydantic models for clusters.yaml — the declarative multi-cloud spec."""

from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class Cloud(str, Enum):
    HETZNER = "hetzner"
    DIGITALOCEAN = "digitalocean"
    AWS = "aws"
    AZURE = "azure"


class NodeRole(str, Enum):
    SERVER = "server"
    AGENT = "agent"


class NodeSpec(BaseModel):
    """A single VM/node within a cluster."""

    role: NodeRole
    size: str  # cpx21, s-2vcpu-4gb, t3.medium, etc.
    volume_size_gb: Optional[int] = None  # override default volume size


class ClusterSpec(BaseModel):
    """One k3s cluster in a specific cloud region."""

    name: str  # "do-nyc", "hetzner-ashburn"
    cloud: Cloud
    region: str  # "nyc1", "ashburn"
    geo_tag: str  # k8gb geo-tag: "us-nyc", "us-ashburn"
    floating_ip: bool = True
    image: Optional[str] = None  # per-cloud image override
    labels: Optional[dict] = None  # Hetzner key:value labels
    tags: Optional[list[str]] = None  # DO/AWS string tag list
    nodes: list[NodeSpec] = Field(default_factory=list)


class ProviderSpec(BaseModel):
    """Cloud provider credential reference."""

    token_env: str  # env var name for the API token


class Spec(BaseModel):
    """Root spec — what Pulumi reads to drive provisioning."""

    version: int = 2
    defaults: dict = Field(default_factory=dict)
    providers: dict[str, dict] = Field(default_factory=dict)
    clusters: list[ClusterSpec] = Field(default_factory=list)
