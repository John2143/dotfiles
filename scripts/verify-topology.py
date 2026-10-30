#!/usr/bin/env python3
"""
verify-topology.py — Deterministic network topology verification

Usage: scripts/verify-topology.py [--dot PATH]

Queries neighbors, bridge hosts, ARP and DHCP from the five live MikroTik
devices (via mikrotik-connect) and diffs them against network-diagram.dot.

- Links between MikroTiks come from LLDP-confirmed neighbors only. LLDP is
  link-local; CDP/MNDP entries flood across bridges and are ignored.
- Endpoints come from MAC_TO_NODE: wired MACs learned on leaf (non-uplink) ports.
- Exit code is 0 when clean, 1 on any counted issue.
"""

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# DOT node id -> mikrotik-connect alias. Keys are also the node ids used in network-diagram.dot.
DEVICES = {
    "router":        {"alias": "r"},
    "core":          {"alias": "c"},
    "upstairs_core": {"alias": "uc"},
    "upstairs":      {"alias": "u"},
    "office":        {"alias": "o"},
}

# Exact `/system identity` names -> DOT node id. Substring matching is wrong: "upstairs-core" contains "core".
IDENTITY_TO_NODE = {
    "router": "router",
    "core-switch": "core",
    "upstairs-core": "upstairs_core",
    "upstairs-switch": "upstairs",
    "office-switch": "office",
}

MIKROTIK_OUIS = ("04:F4:1C", "D0:EA:11")

# Wired endpoints whose MAC is learned on exactly one MikroTik leaf port (verified 2026-10-29).
# Wireless clients and the cameras behind the NVR are deliberately absent.
MAC_TO_NODE = {
    "30:52:53:09:E1:72": "jetkvm",        # router jetkvm (ether4)
    "1C:0B:8B:50:FF:7E": "u7lite",        # router u7-lite (ether5)
    "EC:71:DB:3E:2F:21": "cam_driveway",  # router cam-front (ether7)
    "DC:A6:32:25:51:6E": "pite",          # router pite (ether8)
    "E8:4D:D0:C1:54:20": "nas",           # core sfp-sfpplus1
    "94:83:C4:C4:9C:4D": "glkvm",         # upstairs-core ether1
    "0C:C4:7A:BD:63:3D": "closet",        # upstairs-core sfp-sfpplus1
    "98:B7:85:23:48:90": "arch",          # upstairs-core sfp-sfpplus3
    "EC:71:DB:8B:92:93": "nvr",           # upstairs ether1
    "F0:B3:EC:7E:31:64": "bedroom",       # upstairs ether4
    "2C:EA:7F:7B:12:75": "bigp",          # upstairs ether5 (iDRAC)
    "3C:2A:F4:95:DF:58": "brother",       # upstairs ether6
    "B8:27:EB:56:F0:27": "vpin",          # upstairs ether8
    "2C:EA:7F:E7:13:98": "bigp",          # upstairs sfp-sfpplus2 (Proxmox host NIC)
    "90:41:B2:D6:74:DB": "u7proxgs",      # office sfp-sfpplus1
}


def run(device, cmd):
    """Run a read-only RouterOS command via mikrotik-connect; CRs stripped.

    mikrotik-connect exits 0 even when RouterOS rejects the command, so errors are
    detected from the output: empty output, or a RouterOS error prefix.
    """
    alias = DEVICES[device]["alias"]
    r = subprocess.run(["mikrotik-connect", alias, cmd],
                       capture_output=True, text=True, timeout=30)
    out = r.stdout.replace("\r", "")
    if r.returncode != 0 or not out.strip() or re.match(
            r"(bad command name|syntax error|no such item|expected end of command|failure:)",
            out.strip()):
        sys.exit(f"ERROR: mikrotik-connect {alias} '{cmd}' failed: "
                 f"rc={r.returncode} {out.strip()[:120]} {r.stderr.strip()[:120]}")
    return out


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
            ("neighbor_ip", r'(?<![\w-])address=(\S+)'),
            ("discovered_by", r'discovered-by=(\S+)'),
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
    ap = argparse.ArgumentParser(description="Verify network-diagram.dot against the live MikroTiks.")
    ap.add_argument("--dot", type=Path, default=REPO / "network-configs" / "network-diagram.dot")
    args = ap.parse_args()

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

    # ── Step 3: Collect bridge hosts from all devices (the router's leaf
    # ports are the only place jetkvm/u7-lite/cam-front/pite are learned)
    print("\n── Step 3: Collecting bridge hosts (all devices)...")
    bridge_hosts = {}
    for name in DEVICES:
        bridge_hosts[name] = parse_bridge_hosts(
            run(name, "/interface bridge host print detail"), set()
        )
        externals = [e for e in bridge_hosts[name] if not e["local"]]
        print(f"  {name}: {len(externals)} external MACs")

    arp = parse_arp(run("router", "/ip arp print detail"))
    dhcp = parse_dhcp(run("router", "/ip dhcp-server lease print detail"))
    print(f"  ARP: {len(arp)} entries, DHCP: {len(dhcp)} entries")

    order = {name: i for i, name in enumerate(DEVICES)}

    # ── Step 4: Physical links from LLDP only ──
    print("\n" + "=" * 70)
    print("  MIKROTIK-TO-MIKROTIK LINKS (LLDP-confirmed neighbors)")
    print("=" * 70)

    links = {}  # frozenset({(dev, port), (dev, port)}) -> speed of first side seen
    for dev, entries in mndp.items():
        for e in entries:
            if "lldp" not in e.get("discovered_by", "").split(","):
                continue
            remote = IDENTITY_TO_NODE.get(e.get("identity"))
            if remote not in DEVICES or "neighbor_port" not in e:
                continue
            key = frozenset({(dev, e["local_port"]),
                             (remote, e["neighbor_port"].removeprefix("bridge/"))})
            if key not in links:
                links[key] = speeds[dev].get(e["local_port"], {}).get("rate", "?")

    def oriented(key):
        return tuple(sorted(key, key=lambda end: (order[end[0]], end[1])))

    print(f"\n{'LOCAL DEV':<14} {'LOCAL PORT':<18} {'REMOTE DEV':<14} {'REMOTE PORT':<20} {'SPEED':>8}")
    print("-" * 78)
    for key in sorted(links, key=lambda k: [(order[d], p) for d, p in oriented(k)]):
        (a_dev, a_port), (b_dev, b_port) = oriented(key)
        print(f"{a_dev:<14} {a_port:<18} {b_dev:<14} {b_port:<20} {links[key]:>8}")

    # ── Step 5: Endpoints on leaf ports ──
    print("\n" + "=" * 70)
    print("  ENDPOINTS ON LEAF PORTS (bridge hosts + ARP/DHCP)")
    print("=" * 70)
    n = 0

    # Build MAC → IP + hostname lookup
    mac_to_ip = {}
    mac_to_name = {}
    for mac, info in arp.items():
        if info.get("interface") == "bridge":  # only LAN side
            mac_to_ip[mac] = info["ip"]
    for mac, info in dhcp.items():
        mac_to_name[mac] = info.get("hostname") or info.get("comment", "")

    uplink_ports = defaultdict(set)
    for key in links:
        for dev, port in key:
            uplink_ports[dev].add(port)

    mac_leaves = defaultdict(set)  # mac -> {(dev, port)}
    for dev in DEVICES:
        for entry in bridge_hosts[dev]:
            mac, port = entry["mac"], entry["on_port"]
            if entry["local"] or mac.startswith(MIKROTIK_OUIS):
                continue
            if port in uplink_ports[dev]:
                continue
            mac_leaves[mac].add((dev, port))

    rows = sorted(((mac, dev, port) for mac, locs in mac_leaves.items() for dev, port in locs),
                  key=lambda r: (order[r[1]], r[2], r[0]))
    print(f"\n{'MAC':<19} {'IP':<17} {'HOSTNAME':<22} {'NODE':<14} {'DEVICE':<14} {'PORT':<16}")
    print("-" * 102)
    for mac, dev, port in rows:
        print(f"{mac:<19} {mac_to_ip.get(mac, '?'):<17} {mac_to_name.get(mac, ''):<22} "
              f"{MAC_TO_NODE.get(mac, '-'):<14} {dev:<14} {port:<16}")

    print()
    for mac in sorted(mac_leaves):
        locs = sorted(mac_leaves[mac])
        if len(locs) < 2:
            continue
        if mac in MAC_TO_NODE:
            print(f"  AMBIGUOUS: {MAC_TO_NODE[mac]} {mac} seen on {locs}")
            n += 1
        else:
            print(f"  note: {mac} on {locs} (roaming/unmapped, not counted)")

    # ── Step 6: Compare with the DOT file ──
    print("\n" + "=" * 70)
    print(f"  DIFF: LIVE TOPOLOGY vs. {args.dot}")
    print("=" * 70)
    dot_nodes, dot_edges = parse_dot_edges(args.dot)

    def port_in(port, label):
        return re.search(r'(?<![\w-])' + re.escape(port) + r'(?![\w-])', label) is not None

    live = []  # (a, b, ports, desc)
    for key in links:
        (a, port_a), (b, port_b) = oriented(key)
        live.append((a, b, [port_a, port_b], f"{a} {port_a} <-> {b} {port_b}"))
    seen_nodes = set()
    for mac, locs in mac_leaves.items():
        node = MAC_TO_NODE.get(mac)
        if not node:
            continue
        seen_nodes.add(node)
        for dev, port in sorted(locs):
            live.append((dev, node, [port], f"{node} {mac}"))

    for a, b, ports, desc in live:
        cands = [label for src, dst, label in dot_edges if {src, dst} == {a, b}]
        if not cands:
            print(f"  MISSING DOT EDGE: {a} -> {b} ({desc}, port(s) {ports})")
            n += 1
        elif not any(all(port_in(p, label) for p in ports) for label in cands):
            print(f"  PORT MISMATCH: {a}<->{b} ({desc}): live port(s) {ports}; DOT label(s) {cands}")
            n += 1

    checked_pairs = {frozenset({a, b}) for a, b, _, _ in live}
    unseen = set(MAC_TO_NODE.values()) - seen_nodes
    for node in sorted(unseen):
        print(f"  NOT SEEN: {node} (no MAC learned on a leaf port; idle or offline?)")

    nodes_mikrotik = set(DEVICES)
    checkable = nodes_mikrotik | set(MAC_TO_NODE.values())
    for src, dst, label in dot_edges:
        if not ({src, dst} <= checkable and {src, dst} & nodes_mikrotik):
            continue
        if {src, dst} & unseen or frozenset({src, dst}) in checked_pairs:
            continue
        print(f"  UNVERIFIED DOT EDGE: {src} -> {dst} (\"{label}\")")
        n += 1

    for node in sorted(checkable - set(dot_nodes)):
        print(f"  MISSING DOT NODE: {node}")
        n += 1

    print()
    if n == 0:
        print("All checks passed.")
    else:
        print(f"Total issues: {n}")
    return 1 if n else 0

if __name__ == "__main__":
    sys.exit(main())
