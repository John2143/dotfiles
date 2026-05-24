#!/usr/bin/env python3
"""
Generate a hardware-specs markdown file from raw enumeration output.

Usage:
  ./generate-hardware-spec.py <hostname> <raw-dump.txt> [--output <path>] [--notes <notes.md>]

The raw dump is the stdout from running the commands in hardware-specs-methodology.md.
Existing Notes sections in the output file (if any) are preserved across regenerations.

Sections in the raw dump are delimited by: === SECTION_NAME ===
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── DMI chassis type decoding ──────────────────────────────────────────────

CHASSIS_TYPES = {
    "1": "Other", "2": "Unknown", "3": "Desktop",
    "4": "Low Profile Desktop", "5": "Pizza Box", "6": "Mini Tower",
    "7": "Tower", "8": "Portable", "9": "Laptop", "10": "Notebook",
    "11": "Hand Held", "12": "Docking Station", "13": "All in One",
    "14": "Sub Notebook", "15": "Space-saving", "16": "Lunch Box",
    "17": "Main Server Chassis", "18": "Expansion Chassis",
    "19": "Sub Chassis", "20": "Bus Expansion Chassis",
    "21": "Peripheral Chassis", "22": "RAID Chassis",
    "23": "Rack Mount Chassis", "24": "Sealed-case PC",
    "31": "Convertible", "32": "Detachable",
    "35": "Desktop Mini / USFF",
}

GARBAGE_DMI_NAMES = {
    "To Be Filled By O.E.M.",
    "To be filled by O.E.M.",
    "System Product Name",
    "Default string",
}


# ── Parsers ─────────────────────────────────────────────────────────────────

def parse_sections(text: str) -> dict[str, list[str]]:
    """Split raw text into sections delimited by === NAME === headers."""
    # Strip nix build noise before the first section marker
    m = re.search(r"^=== ", text, re.MULTILINE)
    if m:
        text = text[m.start():]

    sections: dict[str, list[str]] = {}
    current: str | None = None
    current_lines: list[str] = []
    for line in text.split("\n"):
        m = re.match(r"^=== (.+) ===$", line)
        if m:
            if current:
                sections[current] = current_lines
            current = m.group(1)
            current_lines = []
        else:
            current_lines.append(line)
    if current:
        sections[current] = current_lines
    return sections


def kv(lines: list[str]) -> dict[str, str]:
    """Parse key: value lines into a dict."""
    d: dict[str, str] = {}
    for line in lines:
        if ":" in line:
            k, v = line.split(":", 1)
            d[k.strip()] = v.strip()
    return d


def os_release(lines: list[str]) -> dict[str, str]:
    d: dict[str, str] = {}
    for line in lines:
        m = re.match(r'^([A-Z_]\w*)="?(.+?)"?$', line)
        if m:
            d[m.group(1)] = m.group(2).strip('"')
    return d


def dmidecode_memory(lines: list[str]) -> list[dict[str, str]]:
    """Parse dmidecode -t memory output into DIMM records."""
    dimms: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#") or "SMBIOS" in line or "Getting" in line:
            continue
        if "DMI type 16" in line or "Physical Memory" in line:
            continue
        if "DMI type 17" in line:
            if current:
                dimms.append(current)
            current = {}
            continue
        if current is None:
            continue
        if line.startswith("Handle") or line == "Memory Device":
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            current[k.strip()] = v.strip()
    if current:
        dimms.append(current)
    return dimms


def memory_summary(mem_lines: list[str]) -> tuple[str, str]:
    """Extract RAM and swap from free -h output."""
    ram = swap = ""
    for line in mem_lines:
        if line.startswith("Mem:"):
            ram = line.split()[1]
        elif line.startswith("Swap:"):
            swap = line.split()[1]
    return ram, swap


def net_ifaces(lines: list[str]) -> dict[str, str]:
    """Parse NET_IFACES output: iface_name -> PCI address (e.g. eno1 -> 0000:00:1f.6)."""
    mapping: dict[str, str] = {}
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 2:
            name, pci = parts[0], parts[1]
            # Strip 0000: prefix from PCI address
            if pci.startswith("0000:"):
                pci = pci[5:]
            mapping[pci] = name
    return mapping


def pci_devices(lines: list[str]) -> list[dict[str, str]]:
    """Parse lspci -nn output."""
    devices: list[dict[str, str]] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        m = re.match(r"^([0-9a-f:.]+)\s+(.+?)\s*\[([0-9a-f]{4})\]\s*:\s*(.+)", line)
        if not m:
            continue
        addr = m.group(1)
        class_id = m.group(3)
        desc = m.group(4).strip()
        ids_m = re.search(r"\[([0-9a-f:]+)\]", desc)
        vid_did = ids_m.group(1) if ids_m else ""
        desc_clean = re.sub(r"\s*\[[0-9a-f:]+\]", "", desc)
        rev_m = re.search(r"\(rev\s+([0-9a-f]+)\)", desc)
        rev = rev_m.group(1) if rev_m else ""
        desc_clean = re.sub(r"\s*\(rev\s+[0-9a-f]+\)", "", desc_clean).strip()
        devices.append({
            "addr": addr,
            "class_id": class_id,
            "desc": desc_clean,
            "vid_did": vid_did,
            "rev": rev,
            "raw": line,
        })
    return devices


def usb_devices(lines: list[str]) -> list[str]:
    result: list[str] = []
    for line in lines:
        m = re.match(r"Bus \d+ Device \d+: ID ([0-9a-f:]+) (.+)", line.strip())
        if m:
            result.append(f"`{m.group(1)}` {m.group(2)}")
    return result


def sensors(lines: list[str]) -> dict:
    text = "\n".join(lines).strip()
    if text:
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass
    return {}


# ── Formatters ──────────────────────────────────────────────────────────────

def fmt_overview(host: str, os_info: dict, kernel_raw: str, dmi: dict) -> list[str]:
    kernel = kernel_raw.strip()
    if kernel.startswith("Linux "):
        kernel = kernel[6:]
    # Simplify kernel to version + arch
    parts = kernel.split()
    version = arch = None
    for i, p in enumerate(parts):
        if re.match(r"^\d+\.\d+\.\d+$", p) and i > 0:
            version = p
        if p in ("x86_64", "aarch64", "armv7l"):
            arch = p
    kernel_short = f"{version} {arch}" if version and arch else kernel

    # Chassis
    product = dmi.get("product_name", "Desktop")
    chassis_type = dmi.get("chassis_type", "")
    if product in GARBAGE_DMI_NAMES:
        chassis = CHASSIS_TYPES.get(chassis_type, "Desktop")
    elif chassis_type in CHASSIS_TYPES:
        chassis = f"{product} ({CHASSIS_TYPES[chassis_type]})"
    else:
        chassis = product

    return [
        "## System Overview", "",
        "| Field | Value |",
        "|---|---|",
        f"| Hostname | {host} |",
        f"| OS | {os_info.get('PRETTY_NAME', '')} |",
        f"| Kernel | {kernel_short} |",
        f"| Motherboard | {dmi.get('board_vendor', '')} {dmi.get('board_name', '')} ({dmi.get('board_version', '')}) |",
        f"| Chassis | {chassis} |",
        f"| BIOS | {dmi.get('bios_vendor', '')} {dmi.get('bios_version', '')} ({dmi.get('bios_date', '')}) |",
    ]


def fmt_cpu(cpu: dict) -> list[str]:
    lines = ["## CPU", "", "| Field | Value |", "|---|---|"]
    model = cpu.get("Model name", cpu.get("Model", ""))
    lines.append(f"| Model | {model} |")
    lines.append(f"| Architecture | {cpu.get('Architecture', '')} |")

    cores = cpu.get("Core(s) per socket", cpu.get("Core(s) per cluster", ""))
    threads = cpu.get("Thread(s) per core", "1")
    online = cpu.get("CPU(s)", "")
    sockets = cpu.get("Socket(s)", "")

    if sockets and sockets != "-":
        lines.append(f"| Cores | {cores} ({online} threads, {threads} per core) |")
        lines.append(f"| Sockets | {sockets} |")
    else:
        lines.append(f"| Cores | {cores} ({online} threads) |")

    max_mhz = cpu.get("CPU max MHz", "")
    min_mhz = cpu.get("CPU min MHz", "")
    if max_mhz:
        lines.append(f"| Max Frequency | {float(max_mhz) / 1000:.1f} GHz (boost) |")
    if min_mhz:
        lines.append(f"| Min Frequency | {int(float(min_mhz))} MHz |")

    for name, key in [("L1d Cache", "L1d cache"), ("L1i Cache", "L1i cache"),
                       ("L2 Cache", "L2 cache"), ("L3 Cache", "L3 cache")]:
        if key in cpu:
            lines.append(f"| {name} | {cpu[key]} |")

    for k in ("Microcode", "Microcode version"):
        if k in cpu:
            lines.append(f"| Microcode | {cpu[k]} |")
            break
    if "Virtualization" in cpu:
        lines.append(f"| Virtualization | {cpu['Virtualization']} |")
    if "Flags" in cpu:
        lines.append(f"| Flags | {cpu['Flags'][:300]}… |")
    return lines


def fmt_memory(ram: str, swap: str, dimms: list[dict]) -> list[str]:
    lines = ["## Memory", "", "### Summary", "",
             "| Type | Size |", "|---|---|",
             f"| RAM | {ram} |", f"| Swap | {swap} |"]

    real = [d for d in dimms if d.get("Size") not in ("No Module Installed", None, "") and d.get("Size")]
    if real:
        lines += ["", "### DIMM Details", "",
                  "| Slot | Size | Type | Speed | Manufacturer | Part Number |",
                  "|---|---|---|---|---|---|"]
        for d in real:
            loc = d.get("Locator", "?")
            size = d.get("Size", "?")
            dtype = d.get("Type", "?")
            speed = d.get("Speed", "?")
            configured = d.get("Configured Memory Speed", "")
            if configured and configured != speed:
                speed = f"{speed} (configured: {configured})"
            mfr = d.get("Manufacturer", "?")
            pn = d.get("Part Number", "?").strip()
            lines.append(f"| {loc} | {size} | {dtype} | {speed} | {mfr} | {pn} |")
    else:
        lines += ["", "_No DIMM details available (requires root/dmidecode on x86)_"]
    return lines


def fmt_storage(lines: list[str]) -> list[str]:
    result = ["## Storage", "", "```"]
    for line in lines:
        if line.strip() and "NAME" not in line:
            result.append(line.rstrip())
    result.append("```")
    return result


def fmt_gpu(pci: list[dict]) -> list[str]:
    gpus = [d for d in pci if d["class_id"] in ("0300", "0302", "0380")]
    if not gpus:
        return []
    result = ["## GPU", ""]
    for g in gpus:
        ids = f" [{g['vid_did']}]" if g["vid_did"] else ""
        rev = f" rev {g['rev']}" if g["rev"] else ""
        result.append(f"- `{g['addr']}` {g['desc']}{ids}{rev}")
    return result


def fmt_network(pci: list[dict], ifaces: dict[str, str]) -> list[str]:
    net_classes = {"0200", "0280"}
    nics = [d for d in pci if d["class_id"] in net_classes]
    if not nics:
        return []
    result = ["## Network", ""]
    result.append("| Device | Interface | Description |")
    result.append("|---|---|---|")
    for n in nics:
        iface = ifaces.get(n["addr"], "—")
        ids = f" [{n['vid_did']}]" if n["vid_did"] else ""
        rev = f" rev {n['rev']}" if n["rev"] else ""
        result.append(f"| {n['addr']} | {iface} | {n['desc']}{ids}{rev} |")
    return result


def fmt_pci(pci: list[dict]) -> list[str]:
    result = ["## PCI Devices", ""]
    for d in pci:
        ids = f" [{d['vid_did']}]" if d["vid_did"] else ""
        rev = f" rev {d['rev']}" if d["rev"] else ""
        result.append(f"- `{d['addr']}` {d['desc']}{ids}{rev}")
    return result


def fmt_usb(devices: list[str]) -> list[str]:
    result = ["## USB Devices", ""]
    if devices:
        result.extend(f"- {d}" for d in devices)
    else:
        result.append("- No USB devices detected")
    return result


def fmt_disk_ids(lines: list[str]) -> list[str]:
    ids = [l.strip() for l in lines if l.strip()]
    if not ids:
        return []
    return ["## Disk Identifiers", "", "```"] + ids + ["```"]


def fmt_sensors(data: dict) -> list[str]:
    result = ["## Temperature Sensors", ""]
    if not data:
        return result + ["- No sensor data available"]
    for adapter_name, adapter_data in data.items():
        items = []
        for sensor_name, sensor_data in adapter_data.items():
            if isinstance(sensor_data, dict):
                vals = []
                for k, v in sorted(sensor_data.items()):
                    if isinstance(v, (int, float)):
                        key = k.replace("_input", "").replace("_", " ")
                        if "temp" in k:
                            vals.append(f"{key}: {v:.0f}°C")
                        else:
                            vals.append(f"{key}: {v:.1f}")
                if vals:
                    items.append(f"{sensor_name} — {', '.join(vals[:4])}")
        if items:
            result.append(f"- {adapter_name}: {'; '.join(items[:3])}")
    if len(result) <= 2:
        result.append("- No readable sensor values")
    return result


def extract_notes(existing_path: Path | None) -> list[str]:
    """Extract ## Notes section from an existing spec file."""
    if not existing_path or not existing_path.exists():
        return []
    with open(existing_path) as f:
        text = f.read()
    in_notes = False
    notes: list[str] = []
    for line in text.split("\n"):
        if line.strip() == "## Notes":
            in_notes = True
            continue
        if in_notes:
            if line.startswith("## "):
                break
            notes.append(line)
    while notes and not notes[-1].strip():
        notes.pop()
    return notes


# ── Main ────────────────────────────────────────────────────────────────────

def generate(hostname: str, raw_text: str, notes: list[str] | None = None) -> str:
    sections = parse_sections(raw_text)

    cpu = kv(sections.get("CPU", []))
    dmi = kv(sections.get("DMI", []))
    os_info = os_release(sections.get("OS", []))
    kernel_raw = sections.get("KERNEL", [""])[0]
    ram, swap = memory_summary(sections.get("MEMORY", []))
    dimms = dmidecode_memory(sections.get("RAM_DETAILS", []))
    pci = pci_devices(sections.get("PCI", []))
    usb = usb_devices(sections.get("USB", []))
    ifaces = net_ifaces(sections.get("NET_IFACES", []))
    sensor_data = sensors(sections.get("SENSORS", []))

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    blocks: list[list[str]] = [
        [f"# Hardware Specs: {hostname}", "", f"**Generated:** {timestamp}"],
        fmt_overview(hostname, os_info, kernel_raw, dmi),
        fmt_cpu(cpu),
        fmt_memory(ram, swap, dimms),
        fmt_storage(sections.get("BLOCK_DEVICES", [])),
    ]

    gpu = fmt_gpu(pci)
    if gpu:
        blocks.append(gpu)

    net = fmt_network(pci, ifaces)
    if net:
        blocks.append(net)

    blocks += [
        fmt_pci(pci),
        fmt_usb(usb),
    ]

    disk = fmt_disk_ids(sections.get("DISK_ID", []))
    if disk:
        blocks.append(disk)

    blocks.append(fmt_sensors(sensor_data))

    # Assemble with blank-line separators
    output: list[str] = []
    for i, block in enumerate(blocks):
        output.extend(block)
        output.append("")

    # Add Notes section
    if notes:
        output.append("## Notes")
        output.append("")
        output.extend(notes)
        output.append("")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description="Generate hardware spec markdown from raw dump")
    parser.add_argument("hostname", help="Host name for the spec")
    parser.add_argument("raw_dump", type=Path, help="Path to raw enumeration output")
    parser.add_argument("--output", "-o", type=Path, help="Output file path (default: hardware-<hostname>-specs.md)")
    parser.add_argument("--notes", type=Path, help="Path to file containing Notes to append")
    args = parser.parse_args()

    raw_text = args.raw_dump.read_text()

    # Determine notes source
    notes: list[str] = []
    if args.notes:
        notes = args.notes.read_text().strip().split("\n")
    elif args.output:
        notes = extract_notes(args.output)

    output = generate(args.hostname, raw_text, notes)
    out_path = args.output or Path(f"hardware-{args.hostname}-specs.md")
    out_path.write_text(output + "\n")
    print(f"Wrote {out_path} ({len(output)} bytes)")


if __name__ == "__main__":
    main()
