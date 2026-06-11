#!/usr/bin/env python3
"""
verify-topology.py — Deterministic network topology verification

Queries MNDP, bridge hosts, ARP, and DHCP from live MikroTik devices,
builds a structured topology, and diffs it against network-diagram.dot.

MNDP is the gold standard: /ip neighbor print detail gives us both the
local port and the neighbor's port via the `interface-name` field.
"""

import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path.home() / "repos" / "dotfiles"
KEYFILE = f"/run/user/{os.getuid()}/mikrotik-key"

# ── Device info ──────────────────────────────────────────────────
DEVICES = {
    "router":   {"ip": "192.168.1.1",   "short": "r", "ssh": True},
    "core":     {"ip": "192.168.5.4",   "short": "c", "ssh": True},
    "upstairs": {"ip": "192.168.5.3",   "short": "u", "ssh": False},
    "office":   {"ip": "192.168.5.2",   "short": "o", "ssh": True},
}


def ssh(ip, cmd):
    """Execute command on a MikroTik via SSH with key auth."""
    args = [
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=5",
        "-i", KEYFILE,
        f"admin@{ip}", cmd,
    ]
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    # Strip SSH warnings
    lines = [l for l in result.stdout.splitlines()
             if "vulnerable" not in l.lower() and "WARNING" not in l]
    return "\n".join(lines)

def mikrotik_connect(name, cmd):
    """Use mikrotik-connect fish function for devices it supports."""
    args = ["fish", "-c", f"mikrotik-connect {DEVICES[name]['short']} '{cmd}'"]
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    return result.stdout


def run(device, cmd):
    """Run a command on a device, choosing the right transport."""
    if DEVICES[device]["ssh"]:
        return ssh(DEVICES[device]["ip"], cmd)
    else:
        return mikrotik_connect(device, cmd)


# ── Parsers ──────────────────────────────────────────────────────

def parse_mndp(text, device_name):
    """
    Parse /ip neighbor print detail.
    Returns list of {local_port, neighbor_identity, neighbor_ip,
                      neighbor_mac, neighbor_port, board, platform}
    """
    entries = []
    current = {}
    for line in text.splitlines():
        # New entry starts with " N interface=..."
        m = re.match(r'^\s*(\d+)\s+interface=(\S+),bridge', line)
        if m:
            if current:
                entries.append(current)
            idx = int(m.group(1))
            current = {"index": idx, "local_port": m.group(2)}
            continue

        # Key fields
        for field, pattern in [
            ("identity", r'identity="([^"]*)"'),
            ("neighbor_ip", r'address=(\S+)'),
            ("neighbor_mac", r'mac-address=([0-9A-Fa-f:]+)'),
            ("neighbor_port", r'interface-name="([^"]*)"'),
            ("board", r'board="([^"]*)"'),
            ("platform", r'platform="([^"]*)"'),
            ("version", r'version="([^"]*)"'),
        ]:
            m = re.search(pattern, line)
            if m:
                current[field] = m.group(1)
    if current:
        entries.append(current)
    return entries


def parse_speeds(text):
    """
    Parse /interface ethernet monitor [find] once.
    Uses regex to extract per-port name/status/rate triples from the
    columnar MikroTik output, which wraps when ports have different lengths.

    Returns {port_name: {"rate": "10Gbps", "status": "link-ok"}}
    """
    ports = {}

    # Extract port names from the name: line
    name_line = None
    for line in text.splitlines():
        if re.match(r'\s*name:', line):
            name_line = line
            break
    if not name_line:
        return ports

    port_names = name_line.split("name:")[1].strip().split()
    for p in port_names:
        if p:
            ports[p] = {}

    # Extract status/rate per column using ordered matching against
    # the entire output. The tricky part: MikroTik wraps long rows,
    # so we scan line by line and assign values to the right column.
    lines = text.splitlines()
    for line in lines:
        m = re.match(r'\s*status:\s*(.*)', line)
        if m:
            vals = m.group(1).split()
            for i, v in enumerate(vals):
                if i < len(port_names):
                    ports[port_names[i]]["status"] = v
            continue
        m = re.match(r'\s*rate:\s*(.*)', line)
        if m:
            vals = m.group(1).split()
            # Find which columns have link-ok and assign rates
            j = 0
            for i, pn in enumerate(port_names):
                if ports[pn].get("status") == "link-ok":
                    if j < len(vals):
                        ports[pn]["rate"] = vals[j]
                    j += 1
            continue
    return ports




def parse_bridge_hosts(text, own_macs):
    """
    Parse /interface bridge host print detail.
    RouterOS wraps entries: the on-interface field appears on a
    continuation line. We join lines, then split on index numbers.

    Returns list of {mac, on_port, flags, local} for every entry.
    """
    entries = []
    # Collapse continuation lines: "         on-interface=..." joined to prior line
    collapsed = re.sub(r'\n\s+(on-interface=\S+)', r' \1', text)

    for line in collapsed.splitlines():
        m = re.match(
            r'^\s*(\d+)\s+(.+?)\s+mac-address=([0-9A-Fa-f:]+)\s+'
            r'interface=(\S+)\s+bridge=\S+\s+on-interface=(\S+)',
            line
        )
        if m:
            flags = m.group(2).strip()
            mac = m.group(3).upper()
            port = m.group(5)
            entries.append({
                "mac": mac, "on_port": port, "flags": flags, "local": "L" in flags
            })
    return entries


def parse_arp(text):
    """
    Parse /ip arp print detail.
    Returns {mac_upper: {ip, interface}}
    """
    entries = {}
    for line in text.splitlines():
        m = re.match(
            r'^\s*\d+\s+\S+\s+address=(\S+)\s+mac-address=([0-9A-Fa-f:]+)',
            line
        )
        if m:
            ip = m.group(1)
            mac = m.group(2).upper()
            # Get interface
            intf = "bridge"
            mi = re.search(r'interface=(\S+)', line)
            if mi:
                intf = mi.group(1)
            entries[mac] = {"ip": ip, "interface": intf}
    return entries



def parse_dhcp(text):
    """
    Parse /ip dhcp-server lease print detail.
    Extracts host-name and comments from multiline entries via
    two-pass matching over the raw text.
    Returns {mac_upper: {ip, hostname, comment}}
    """
    # Pass 1: host-name → MAC (search forward from mac-address to host-name)
    mac_from_host = {}
    for m in re.finditer(
        r'mac-address=([0-9A-Fa-f:]+)[\s\S]*?host-name="([^"]*)"',
        text, re.IGNORECASE,
    ):
        mac_from_host[m.group(1).upper()] = m.group(2)
    # Pass 2: comments like ;;; Name preceding the entry
    mac_from_comment = {}
    for m in re.finditer(
        r';;;\s*(.+?)\s*\n[\s\S]*?mac-address=([0-9A-Fa-f:]+)',
        text,
    ):
        mac_from_comment[m.group(2).upper()] = m.group(1).strip()

    # Pass 3: standard entry parsing
    entries = {}
    for line in text.splitlines():
        m = re.match(
            r'^\s*\d+\s+(\S*)\s*address=(\S+)\s+mac-address=([0-9A-Fa-f:]+)',
            line,
        )
        if m:
            mac = m.group(3).upper()
            entries[mac] = {
                "ip": m.group(2),
                "mac": mac,
                "hostname": mac_from_host.get(mac, ""),
                "comment": mac_from_comment.get(mac, ""),
            }
    return entries


# ── DOT parser ──────────────────────────────────────────────────

def parse_dot_edges(dot_path):
    """
    Parse network-diagram.dot to extract node labels and edges.
    Returns (nodes, edges) where:
      nodes = {node_id: label_lines}
      edges = [(from_id, to_id, label)]
    """
    nodes = {}
    edges = []

    with open(dot_path) as f:
        content = f.read()

    # Extract node definitions:  nodename [shape=..., label="...", ...]
    for m in re.finditer(
        r'(\w+)\s*\[([^\]]*)\]',
        content,
    ):
        node_id = m.group(1)
        attrs = m.group(2)
        label_m = re.search(r'label="([^"]*(?:"[^\"]*"[^"]*)*)"', attrs)
        if label_m:
            lines = label_m.group(1).split(r'\n')
            nodes[node_id] = lines

    # Extract edges:  a -> b [label="...", ...]
    for m in re.finditer(
        r'(\w+)\s*->\s*(\w+)\s*(\[[^\]]*\])?',
        content,
    ):
        src = m.group(1)
        dst = m.group(2)
        attrs = m.group(3) or ""
        label_m = re.search(r'label="([^"]*)"', attrs)
        label = label_m.group(1) if label_m else ""
        edges.append((src, dst, label))

    return nodes, edges


# ── Main verification logic ──────────────────────────────────────

def main():
    print("=" * 70)
    print("  NETWORK TOPOLOGY VERIFICATION")
    print("=" * 70)

    # ── Step 1: Collect MNDP from all devices ──
    print("\n── Step 1: Collecting MNDP data...")
    mndp = {}
    for name in DEVICES:
        mndp[name] = parse_mndp(run(name, "/ip neighbor print detail"), name)
        print(f"  {name}: {len(mndp[name])} MNDP entries")

    # ── Step 2: Collect interface speeds ──
    print("\n── Step 2: Collecting interface speeds...")
    speeds = {}
    for name in DEVICES:
        speeds[name] = parse_speeds(run(name, "/interface ethernet monitor [find] once"))
        links = {p: info.get("rate", "?") for p, info in speeds[name].items()
                 if info.get("status") == "link-ok"}
        print(f"  {name}: {len(links)} active ports")

    # ── Step 3: Collect bridge hosts from SWITCHES only (router's
    # bridge shows the entire L2 domain — unreliable for endpoints)
    print("\n── Step 3: Collecting bridge hosts (switches only)...")
    bridge_hosts = {}
    for name in ["core", "upstairs", "office"]:
        bridge_hosts[name] = parse_bridge_hosts(
            run(name, "/interface bridge host print detail"), set()
        )
        externals = [e for e in bridge_hosts[name] if not e["local"]]
        print(f"  {name}: {len(externals)} external MACs")

    arp = parse_arp(run("router", "/ip arp print detail"))
    dhcp = parse_dhcp(run("router", "/ip dhcp-server lease print detail"))
    print(f"  ARP: {len(arp)} entries, DHCP: {len(dhcp)} entries")

    # ── Step 4: Build deterministic link table from MNDP ──
    print("\n" + "=" * 70)
    print("  DETERMINISTIC MIKROTIK-TO-MIKROTIK LINKS (from MNDP)")
    print("=" * 70)

    verified_links = []  # [(local_dev, local_port, remote_dev, remote_port, speed)]

    for dev_name, entries in mndp.items():
        for e in entries:
            # Only count MikroTik-to-MikroTik (those with interface-name)
            if "neighbor_port" not in e:
                continue

            local_port = e["local_port"]
            remote_port = e["neighbor_port"]

            # Determine remote device name — only match real MikroTik boards
            identity = e.get("identity", "").lower()
            board = e.get("board", "").lower()
            is_mtik = any(board.startswith(p) for p in ("crs", "rb", "ccr"))
            remote_dev = None
            if is_mtik:
                for dname in DEVICES:
                    if dname in identity:
                        remote_dev = dname
                        break
            if not remote_dev:
                continue

            # Get speed from local device
            speed = "?"
            if local_port in speeds[dev_name]:
                speed = speeds[dev_name][local_port].get("rate", "?")

            verified_links.append((dev_name, local_port, remote_dev, remote_port, speed))


    # Filter out transitive MNDP (bridge flooding).
    # A MikroTik neighbor appearing on the same port as OTHER MikroTik
    # neighbors is transitive — MNDP flooded across the bridge.
    # Real physical links: exactly 1 MikroTik identity per port,
    # OR the identity is the only one on that port across all devices.
    # Heuristic: count MikroTik neighbor appearances per (dev, port).
    port_neighbor_counts = defaultdict(int)
    for link in verified_links:
        a_dev, a_port, _, _, _ = link
        port_neighbor_counts[(a_dev, a_port)] += 1

    seen = set()
    unique_links = []
    for link in verified_links:
        a_dev, a_port, b_dev, b_port, speed = link
        # Only keep if EITHER side has exactly 1 MikroTik neighbor on its port
        # (prevents transitive flooding where e.g. router's 10GsfpLAN sees
        # office/upstairs/core but only core is physically connected)
        a_count = port_neighbor_counts.get((a_dev, a_port), 99)
        b_count = port_neighbor_counts.get((b_dev, b_port), 99)
        if a_count == 1 or b_count == 1:
            key = frozenset([(a_dev, a_port), (b_dev, b_port)])
            if key not in seen:
                seen.add(key)
                unique_links.append(link)

    print(f"\n{'LOCAL DEV':<10} {'LOCAL PORT':<18} {'REMOTE DEV':<12} {'REMOTE PORT':<20} {'SPEED':>8}")
    print("-" * 70)
    for a_dev, a_port, b_dev, b_port, speed in sorted(unique_links):
        print(f"{a_dev:<10} {a_port:<18} {b_dev:<12} {b_port:<20} {speed:>8}")
    # ── Step 5: Identify non-MikroTik endpoints ──
    print("\n" + "=" * 70)
    print("  NON-MIKROTIK ENDPOINTS (from bridge hosts + ARP/DHCP)")
    print("=" * 70)

    # Build MAC → IP + hostname lookup
    mac_to_ip = {}
    mac_to_name = {}
    for mac, info in arp.items():
        if info.get("interface") == "bridge":  # only LAN side
            mac_to_ip[mac] = info["ip"]
    for mac, info in dhcp.items():
        mac_to_name[mac] = info.get("hostname") or info.get("comment", "")

    # Identify uplink ports per switch (from verified MNDP links).
    # Add both sides; strip "bridge/" prefix from remote port names.
    uplink_ports = defaultdict(set)
    for a_dev, a_port, b_dev, b_port, speed in unique_links:
        a_port_clean = a_port.replace("bridge/", "")
        b_port_clean = b_port.replace("bridge/", "")
        if a_dev in bridge_hosts:
            uplink_ports[a_dev].add(a_port_clean)
        if b_dev in bridge_hosts:
            uplink_ports[b_dev].add(b_port_clean)

    # For each MAC, find its "home switch" — the switch where it appears
    # on a non-uplink port. Bridge forwarding makes MACs visible on trunks,
    # so we take the best (non-uplink) port per MAC across all switches.
    mac_home = {}  # mac -> (switch, port)
    for sw_name in bridge_hosts:
        for entry in bridge_hosts[sw_name]:
            mac = entry["mac"]
            port = entry["on_port"]
            if entry["local"]:
                continue
            if mac.startswith("04:F4:1C") or mac.startswith("D0:EA:11"):
                continue
            # Only consider non-uplink ports
            if port in uplink_ports[sw_name]:
                continue
            # First non-uplink hit wins
            if mac not in mac_home:
                mac_home[mac] = (sw_name, port)

    # Print and collect
    print(f"\n{'MAC':<19} {'IP':<17} {'HOSTNAME':<20} {'SWITCH':<10} {'PORT':<16}")
    print("-" * 70)
    endpoints = []
    for mac, (sw, port) in sorted(mac_home.items()):
        ip = mac_to_ip.get(mac, "?")
        hostname = mac_to_name.get(mac, "")
        endpoints.append((mac, ip, hostname, sw, port))
        print(f"{mac:<19} {ip:<17} {hostname:<20} {sw:<10} {port:<16}")


    # ── Step 6: Cross-reference against DOT ──
    print("\n" + "=" * 70)
    print("  DIFF: LIVE TOPOLOGY vs. DOT FILE")
    print("=" * 70)

    dot_path = REPO / "network-configs" / "network-diagram.dot"
    dot_nodes, dot_edges = parse_dot_edges(dot_path)

    # Map live hostnames to DOT node IDs
    hostname_to_dot = {
        "nas":       "nas",
        "arch":      "arch",
        "closet":    "closet",
        "pite":      "pite",
        "office":    "officepc",
        "secu":      "secu",
        "U7ProXGSOffice": "u7proxgs",
        "U7LiteBlueRoom": "u7lite",
        "NVR":       "nvr",
        "Front":     None,  # ambiguous — multiple "Front" cams
        "Back":      "cam_back",
        "Garage":    "cam_garage",
        "Side":      "cam_side",
        "vpin":      "vpin",
        "serverkvm": "jetkvm",
    }
    endpoint_to_dot = {}
    for mac, ip, hostname, sw, port in endpoints:
        dot_id = hostname_to_dot.get(hostname)
        if dot_id:
            endpoint_to_dot[(sw, port)] = (dot_id, hostname, ip)

    # Also map by MAC for camera-specific nodes
    cam_mac_map = {
        "EC:71:DB:65:58:A3": "cam_gate",    # Front Gate
        "EC:71:DB:89:D8:8B": "cam_porch",   # Front Porch
        "EC:71:DB:3E:2F:21": "cam_driveway",# Front Driveway
        "EC:71:DB:8B:92:93": "nvr",         # NVR
        "F0:B3:EC:7E:31:64": "bedroom",     # Bedroom switch
        "94:83:C4:C4:9C:4D": "glkvm",       # GL-KVM
        "3C:2A:F4:95:DF:58": "brother",     # Brother
    }
    for mac, ip, hostname, sw, port in endpoints:
        if mac in cam_mac_map:
            endpoint_to_dot[(sw, port)] = (cam_mac_map[mac], hostname, ip)

    print("\n  Checking DOT edges against live data...")
    issues = 0

    # Build expected edges from live data
    live_edges = set()  # {(dot_src, dot_dst, port_info)}

    # MNDP links → DOT edges
    mndp_dot_map = {
        ("core", "sfp-sfpplus1"): ("router", "10GsfpLAN"),
        ("core", "ether1"):       ("router", "pi"),
        ("core", "sfp-sfpplus3"): ("upstairs", "sfp-sfpplus2"),
        ("core", "sfp-sfpplus4"): ("office", "ether8"),
    }
    for a_dev, a_port, b_dev, b_port, speed in unique_links:
        key = (a_dev, a_port)
        if key in mndp_dot_map:
            dot_src, dot_dst_port = mndp_dot_map[key]
            live_edges.add((a_dev, dot_src))  # (switch, router-or-switch)

    # Endpoints → DOT edges
    for (sw, port), (dot_id, hostname, ip) in endpoint_to_dot.items():
        live_edges.add((sw, dot_id))
        # Check port matches DOT label
        dot_edge = None
        for src, dst, label in dot_edges:
            if src == sw and dst == dot_id:
                dot_edge = (src, dst, label)
                break
        if dot_edge:
            dot_label = dot_edge[2]
            if port not in dot_label:
                print(f"  PORT MISMATCH: {sw}->{dot_id} ({hostname}):")
                print(f"    DOT says: \"{dot_label}\"")
                print(f"    Live says: port {port}")
                issues += 1
        else:
            print(f"  MISSING DOT EDGE: {sw} -> {dot_id} ({hostname} .{ip})")
            issues += 1

    # Check DOT edges exist in live data
    for src, dst, label in dot_edges:
        # Skip infrastructure edges that span devices
        if (src, dst) in live_edges:
            continue
        if (dst, src) in live_edges:
            continue
        # Skip non-physical edges (WiFi, transient, virtual)
        if any(w in label.lower() for w in ("wifi", "mgmt", "iot", "dotted")):
            continue
        # Skip edges between non-MikroTik nodes (camera chains, Internet, etc.)
        if src in ("internet", "verizon", "homepi", "iot") or dst in ("internet", "verizon", "homepi", "iot"):
            continue
        if src in ("cam_gate", "cam_porch", "cam_back", "cam_garage", "cam_side", "cam_driveway"):
            continue
        if dst in ("cam_gate", "cam_porch", "cam_back", "cam_garage", "cam_side", "cam_driveway"):
            continue
        # Only warn about server/endpoint edges
        if src in ("officepc", "secu") or dst in ("officepc", "secu"):
            continue  # WiFi clients
        print(f"  UNVERIFIED DOT EDGE: {src} -> {dst} (\"{label}\")")
        issues += 1

    if issues == 0:
        print("  All DOT edges verified against live topology!")
    else:
        print(f"\n  Total discrepancies: {issues}")

    # Flag potential issues
    print()
    issues = 0

    # Check known devices appear as DOT nodes
    dot_node_ids = set(dot_nodes.keys())
    known_devices = {"router", "core", "upstairs", "office", "nas", "nvr",
                     "closet", "arch", "glkvm", "brother", "pite", "u7proxgs",
                     "u7lite", "officepc", "secu", "verizon", "internet",
                     "homepi", "vpin", "jetkvm", "cam_driveway", "cam_gate",
                     "cam_porch", "cam_back", "cam_garage", "cam_side", "iot"}

    for dev in known_devices:
        if dev not in dot_node_ids:
            print(f"  WARNING: '{dev}' missing from DOT file!")
            issues += 1

    if issues == 0:
        print("  No issues found!")
    else:
        print(f"\n  Total issues: {issues}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
