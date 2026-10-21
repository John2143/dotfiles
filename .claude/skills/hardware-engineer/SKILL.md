---
description: Out-of-band hardware access — BMC/iDRAC over Redfish, IPMI, remote KVM and physical console on the home servers
argument-hint: (none — invoked as skill://hardware-engineer)
allowed-tools: Bash(curl *), Bash(ssh *), Bash(ipmitool *), Read, Search
tool-hints: |
  Default to GET. Power actions, BIOS/attribute writes and firmware updates are mutations and need
  explicit approval — the operator account can power-cycle machines that run workloads.
  Never add -v/--trace/--trace-ascii to curl against a BMC: it prints the Authorization header.
  Failed logins are rate-limited per source IP; do not retry a rejected request in a loop.
  Read the facts from `~/dotfiles/docs/bigp-housekeeping.md` rather than assuming them.
---

# Hardware engineer

Out-of-band access to physical machines: the BMC today, remote KVM and physical console when that
is the only path. Vendor-specific detail is discovered at runtime, not memorised here — BMC
resource trees differ between firmware versions.

## Access

BMCs are queried over Redfish with a curl netrc file holding an operator account. The path is
documented in `skill://network-engineer` (account model, which host has the secret, and the
blocking policy) — do not restate it here.

```
curl -sk --netrc-file /run/agenix/<bmc> https://<bmc-ip>/redfish/v1/
```

`-k` is required: BMC certificates are self-signed.

## Discovery order

Don't hardcode a resource path from memory — enumerate from the service root and follow what the
device advertises:

1. `/redfish/v1/` → Systems, Chassis, Managers, SessionService.
2. The system: model, serial, power state, processors, memory, PCIe devices.
3. The chassis: thermal (temperatures and fans), power (PSUs, input voltage, draw).
4. The manager: firmware version, network, logs, and the vendor's OEM attribute tree — that is
   where thermal profiles, fan offsets and alert destinations live.
5. Logs: the SEL for hardware events (long history), the lifecycle log for administrative events
   (usually only days).

Vendor attributes are worth a full dump once per session and a grep thereafter; the names are not
stable across models.

## Reading thermal data

- Fans are driven by the BMC's closed loop, **dominated by inlet temperature** — not by CPU load
  or by the OS. A server that is loud at idle is usually hot at the intake, not busy.
- So compare, in this order: inlet reading vs a thermometer in the room; inlet vs the chassis's
  configured support limit; CPU/GPU deltas above inlet; exhaust minus inlet.
- If the room is cool and the inlet is not, look for recirculation (closed rack, missing blanks,
  exhaust with nowhere to go) before suspecting a sensor. A sensor that disagrees with a
  thermometer at the bezel is a support case, not a tuning problem.
- Check whether anything is inflating the curve: a thermal profile setting, a fan-speed offset, or
  a non-vendor PCIe card (many BMCs apply a higher floor for uncertified cards).
- The OS sees none of this. Do not go looking for a fan daemon on the host.

## Mutations

Power on/off/reset, BIOS and attribute writes, and firmware updates all change the physical
machine. Ask first, and prefer a graceful shutdown through the OS over a BMC power action. A BMC
reset interrupts console access but not the host.

## Pointers

- `~/dotfiles/docs/bigp-housekeeping.md` — model, service tag, firmware, accounts, known open
  hardware faults, and the deliberate non-actions for that box.
- `skill://network-engineer` — BMC addressing, credential path and the blocking policy.
