# Final Report: Cheap 802.3af PoE Injector for U7 Lite

## 1. Answer

Buy the **Ubiquiti UACC-PoE+-2.5G at $19.00** from store.ui.com. It is the cheapest 2.5GbE PoE injector on the market, delivers 30W PoE+ (backward-compatible with U7 Lite's 802.3af), includes a grounded AC power cord and surge protection, and is explicitly listed as compatible with the U7 Lite. No third-party injector offers better value — name-brand Gigabit-only injectors cost $12-18 without 2.5GbE, and generic injectors carry documented fire-risk concerns.

If 2.5GbE is not needed, Ubiquiti's own **U-PoE at $8.00** is cheaper than any third-party name brand and perfectly adequate for powering the U7 Lite on Gigabit.

Total: **U7 Lite ($99) + UACC-PoE+-2.5G ($19) = $118**.

## 2. Evidence Summary

| Finding | Source |
|---------|--------|
| UACC-PoE+-2.5G is $19 on store.ui.com, supports 2.5GbE, 30W PoE+, includes surge protection | [Ubiquiti Injector Report](reports/ubiquiti-poe-injector_report.md) |
| No third-party injector beats $19 for 2.5GbE; Ubiquiti U-PoE at $8 is cheapest reliable Gigabit injector | [Third-Party Injectors Report](reports/third-party-poe-injectors_report.md) |
| U7 Lite draws 13W max, 802.3af sufficient; Gigabit injectors bottleneck 2.5GbE uplink | [U7 Lite Power Requirements](reports/u7-lite-power-requirements_report.md) |

## 3. Confidence Assessment

**High confidence.** Three independent sub-agents reached identical conclusions using Ubiquiti's official tech specs, store pricing, Amazon listings, community forums, and teardown analyses. No contradictory evidence.

## 4. Limitations and Open Questions

- Pricing is as of 2026-05-24 on store.ui.com. Third-party resellers inflate to $89-119 — buy direct.
- The U7 Lite's 2.5GbE uplink is only beneficial if the upstream switch also supports 2.5GbE. Current MikroTik switches are SFP+ (10GbE) or 1GbE — the upstairs switch's 10GbE SFP+ port would need a 2.5GbE-capable SFP+ module or media converter.

## 5. Bibliography

Ubiquiti Store. "UniFi 2.5G PoE+ Adapter (30W) — UACC-PoE+-2.5G." https://store.ui.com/us/en/products/uacc-poe-plus-2-5g

Ubiquiti Store. "UniFi PoE Adapter (15W) — U-PoE." https://store.ui.com/us/en/products/u-poe-af

Ubiquiti Tech Specs. "Access Point U7 Lite." https://techspecs.ui.com/unifi/wifi/u7-lite
