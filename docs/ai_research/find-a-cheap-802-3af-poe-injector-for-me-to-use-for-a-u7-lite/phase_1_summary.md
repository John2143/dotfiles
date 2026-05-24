# Phase 1 Summary

## Primary Question
Find a cheap 802.3af PoE injector for a U7 Lite access point.

## Sub-Topic Findings

### Ubiquiti UACC-PoE+-2.5G
**Perspective**: none
**Researcher conclusion**: The UACC-PoE+-2.5G is $19.00 on store.ui.com, delivers 30W 802.3at PoE+ (backward-compatible with 802.3af), supports 2.5GbE passthrough, includes grounded AC power cord and surge protection, and is explicitly listed as compatible with the U7 Lite. Ubiquiti's cheaper U-POE-af ($8) works electrically but bottlenecks the 2.5GbE uplink to 1 Gbps. Third-party resellers inflate the UACC-PoE+-2.5G to $89-$119 — buy direct from Ubiquiti.
**Relation to primary question**: Establishes the baseline that Ubiquiti's own $19 injector is the reference point all competitors must beat.

### Third-Party 802.3af Injectors
**Perspective**: none
**Researcher conclusion**: No third-party injector beats the UACC-PoE+-2.5G at $19 for 2.5GbE. TP-Link TL-POE150S at $12-18 is the cheapest name-brand Gigabit injector but lacks 2.5GbE. Generic injectors go to $5-12 but have documented thermal/fire-risk concerns. Surprise finding: Ubiquiti's own U-PoE (802.3af, Gigabit) is only $8.00 — cheaper than any third-party name brand.
**Relation to primary question**: Confirms the UACC-PoE+-2.5G is the best value at its price point and that no third-party alternative provides meaningful savings without sacrificing features or safety.

### U7 Lite Power Requirements
**Perspective**: none
**Researcher conclusion**: U7 Lite draws 13W max (9W typical), well within 802.3af's 15.4W budget. PoE+ is not required. A Gigabit-only injector works for power but caps the 2.5GbE uplink at 1 Gbps. UACC-PoE+-2.5G at $19 is the best value — only $4 more than the unofficial 2.5GbE-capable U-PoE+ ($15) and $11 more than the Gigabit-only U-POE-af ($8), with official compatibility and 2.5GbE guarantee.
**Relation to primary question**: Confirms 802.3af is sufficient and that the $19 Ubiquiti injector is the correct answer for preserving the U7 Lite's full uplink capability.

## Cross-Cutting Insights

All three reports independently converge on the same answer: **UACC-PoE+-2.5G at $19 from store.ui.com**. No contradictions. The $8 U-PoE is a viable budget alternative if 2.5GbE is not needed, but the $11 difference is too small to justify sacrificing the uplink. Third-party injectors offer no price advantage — Ubiquiti's own $8 injector is cheaper than any name-brand competitor, and their $19 2.5GbE injector is uniquely positioned beneath the entire third-party 2.5GbE market.

## Consolidated Bibliography

Ubiquiti Store. "UniFi 2.5G PoE+ Adapter (30W) — UACC-PoE+-2.5G." https://store.ui.com/us/en/products/uacc-poe-plus-2-5g

Ubiquiti Store. "UniFi PoE Adapter (15W) — U-PoE." https://store.ui.com/us/en/products/u-poe-af

Ubiquiti Tech Specs. "Access Point U7 Lite." https://techspecs.ui.com/unifi/wifi/u7-lite

Ubiquiti Tech Specs. "UniFi 2.5G PoE+ Adapter (30W)." https://techspecs.ui.com/unifi/accessories/uacc-poe-plus-2-5g

Amazon.com. "TP-Link TL-PoE150S 802.3af Gigabit Power Over Ethernet PoE Injector Adapter." https://www.amazon.com/TP-LINK-TL-PoE150S-Injector-Adapter-compliant/dp/B0141JITLW

Gough Lui. "Quick Review, Teardown: 802.3at/bt Power-over-Ethernet (PoE) Power Injectors." July 2021. https://goughlui.com/2021/07/11/quick-review-teardown-802-3at-bt-power-over-ethernet-poe-power-injectors

## Decision

**SUFFICIENT** — The answer is unanimous and well-supported: UACC-PoE+-2.5G at $19 from store.ui.com. Budget alternative: U-PoE at $8 if Gigabit is acceptable. No further research needed.
