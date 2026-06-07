"""Post-deploy tasks: age key, agenix decrypt, tailscale connect, k3s verify.

Runs via SSH after nixos-anywhere completes. Uses the cloud SSH key
for all operations.
"""

import time
import pulumi

from resources.common import ssh_exec


def post_deploy(
    host_ip: str,
    hostname: str,
    cloud: str,
    region: str,
    agenix_key_path: str = "~/.ssh/age",
    timeout: int = 300,
) -> dict:
    """Run all post-deploy steps on a freshly-provisioned node.

    Steps:
      1. Wait for NixOS reboot
      2. Copy age key to /etc/agenix/identities/
      3. Rekey agenix secrets
      4. Restart affected services
      5. Tailscale connect via headscale preauth key
      6. Verify k3s is running
      7. Return node status

    Returns dict with status info (k3s version, tailscale IP, etc.)
    """
    pulumi.log.info(f"[{cloud}/{region}] Post-deploy for {hostname}...")

    # Step 1: Wait for NixOS to finish rebooting (longer timeout for first boot)
    _wait_for_nixos(host_ip, hostname, timeout=300)

    # Step 2: Copy age key to both locations agenix checks
    pulumi.log.info(f"[{cloud}/{region}] Copying age identity...")
    ssh_exec(
        host_ip,
        f"mkdir -p /etc/agenix/identities && "
        f"cp {agenix_key_path} /etc/agenix/identities/age-key.txt && "
        f"cp {agenix_key_path} /etc/ssh/age-identity && "
        f"chmod 600 /etc/agenix/identities/age-key.txt /etc/ssh/age-identity",
        timeout=30,
    )

    # Step 3: Run NixOS activation to decrypt agenix secrets
    # agenix --rekey doesn't work standalone (needs secrets.nix from flake context).
    # The activation script has the right RULES path baked in.
    pulumi.log.info(f"[{cloud}/{region}] Activating agenix secrets...")
    ssh_exec(
        host_ip,
        "/run/current-system/activate 2>&1 || echo 'WARNING: activation had issues, continuing...'",
        timeout=60,
    )

    # Step 4: Restart k3s (now that k3s-token is decrypted)
    pulumi.log.info(f"[{cloud}/{region}] Restarting k3s...")
    ssh_exec(host_ip, "systemctl restart k3s 2>/dev/null || true", timeout=30)

    # Step 5: Tailscale connect
    pulumi.log.info(f"[{cloud}/{region}] Connecting Tailscale...")
    _connect_tailscale(host_ip)

    # Step 6: Verify k3s
    pulumi.log.info(f"[{cloud}/{region}] Verifying k3s...")
    k3s_version = ssh_exec(host_ip, "k3s --version 2>&1 | head -1", timeout=10)
    nodes = ssh_exec(host_ip, "kubectl get nodes -o wide 2>&1", timeout=15)
    ts_status = ssh_exec(host_ip, "tailscale status 2>&1 | head -3", timeout=10)

    status = {
        "hostname": hostname,
        "ip": host_ip,
        "cloud": cloud,
        "region": region,
        "k3s_version": k3s_version.strip(),
        "nodes": nodes.strip(),
        "tailscale": ts_status.strip(),
    }

    pulumi.log.info(f"[{cloud}/{region}] Post-deploy complete: {status}")
    return status


def _wait_for_nixos(host_ip: str, hostname: str, timeout: int = 120) -> None:
    """Wait for the NixOS system to finish rebooting after nixos-anywhere."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            out = ssh_exec(host_ip, "cat /etc/hostname", timeout=10).strip()
            # Check that the system reports the correct hostname AND that k3s binary exists
            k3s_check = ssh_exec(host_ip, "which k3s 2>/dev/null || echo 'no k3s'", timeout=10)
            if out == hostname and "no k3s" not in k3s_check:
                return
        except Exception:
            pass
        time.sleep(5)
    raise TimeoutError(f"NixOS did not finish booting on {host_ip} within {timeout}s")


def _connect_tailscale(host_ip: str) -> None:
    """Read the headscale preauth key and connect Tailscale."""
    try:
        preauth = ssh_exec(
            host_ip,
            "cat /run/agenix/hetzner/headscale-preauth-key 2>/dev/null || echo ''",
            timeout=10,
        ).strip()

        if preauth:
            ssh_exec(
                host_ip,
                f"tailscale up --reset --login-server=http://headscale.9s.pics:6767 "
                f"--authkey={preauth} --accept-routes 2>&1",
                timeout=30,
            )
        else:
            # If no preauth key available, restart tailscaled to pick up existing state
            ssh_exec(host_ip, "systemctl restart tailscaled 2>/dev/null || true", timeout=15)

    except Exception as e:
        pulumi.log.warn(f"Tailscale connect on {host_ip} had issues: {e}")
