# U7 Lite Power Requirements

## 1. Summary

The UniFi U7 Lite requires **standard 802.3af PoE (15.4W budget)**. Its maximum power consumption is **13W**, with typical draw around 9W. The AP's 2.5GbE uplink is its only network port; using a Gigabit-only injector limits the link to 1 Gbps. The user's candidate — the **UACC-PoE+-2.5G at $19.00** — is officially compatible, provides 2.5GbE passthrough, and is objectively the best value among Ubiquiti-branded injectors for this AP.

## 2. Relation to Primary Question

The primary question asks for a cheap 802.3af PoE injector for a U7 Lite. This report establishes the AP's exact power requirements, confirming that 802.3af is sufficient, and evaluates whether cost savings from a Gigabit-only injector are worth the bandwidth trade-off versus the 2.5GbE-capable UACC-PoE+-2.5G.

### 2.1 Power Requirements

| Parameter | Value | Source |
|---|---|---|
| PoE Standard | 802.3af (PoE) | [1][2] |
| Max Power Consumption | 13W | [1][2] |
| Typical Operating Draw | ~9W | [6] |
| Supported Voltage Range | 42.5–57V DC | [1] |
| 802.3af Budget | 15.4W at source | [7] |
| Margin | 2.4W (15.5% headroom) | — |

The U7 Lite's 13W maximum is comfortably within the 15.4W budget of 802.3af. It does **not** require 802.3at (PoE+, 30W) or 802.3bt (PoE++, 60W+). Ubiquiti's own Tech Specs page lists the power method simply as "PoE" — which in Ubiquiti's terminology means 802.3af [3].

### 2.2 Uplink Speed Implications

The U7 Lite has a single **2.5GBASE-T** RJ45 uplink port. Whether the injector needs 2.5GbE passthrough depends on the upstream switch/router port speed:

- **If the upstream port is Gigabit**: Any Gigabit injector (U-POE-af, U-PoE+) is sufficient. The link auto-negotiates to 1 Gbps and there is no penalty.
- **If the upstream port is 2.5GbE**: A Gigabit-only injector becomes the bottleneck. The link negotiates at 1 Gbps, capping throughput.

Real-world throughput from the U7 Lite in testing reached "low Gig+" speeds (~1.5 Gbps) on Wi-Fi 6/7 clients at close range with a 160 MHz channel [2], so a 2.5GbE-capable injector is beneficial only when the upstream switch is multi-gig capable and the Wi-Fi clients can saturate >1 Gbps.

### 2.3 Injector Comparison

| Injector | Price (USD) | PoE Standard | Max Power | Rated Link Speed | 2.5GbE in Practice | U7 Lite Listed Compatible |
|---|---|---|---|---|---|---|
| **U-POE-af** | ~$8 [4] | 802.3af | 15.4W | Gigabit | No [5] | No [3] |
| **U-PoE+ (U-POE-at)** | $15.00 [8] | 802.3at | 30W | Gigabit | Yes (unofficial) [3] | No |
| **UACC-PoE+-2.5G** | $19.00 [9] | 802.3at | 30W | 2.5GbE | Yes (official) | **Yes** [9] |

**Key observation**: The U-POE-at (Gigabit-rated) has been reported by Ubiquiti community members to pass 2.5GbE traffic in practice — it's a passive electrical passthrough and the magnetics support the higher frequency [3]. Ubiquiti does not market it as 2.5GbE-capable, but real-world testing confirms it works. The U-POE-af, however, appears limited to Gigabit.

### 2.4 The UACC-PoE+-2.5G at $19.00

This injector is:
- **Officially compatible** with U7 Lite (listed on the product page) [9]
- **802.3at (30W)** — backward-compatible with 802.3af devices
- **2.5GbE rated** — no ambiguity about multi-gig support
- **$19.00** on the Ubiquiti Store
- Includes surge, peak pulse, and overcurrent protection

At only $4 more than the Gigabit-only U-PoE+ ($15) and ~$11 more than the bare-minimum U-POE-af (~$8), it's the clear recommendation when 2.5GbE capability has any future value.

## 3. Source Evaluation

| # | Source | Type | Reliability |
|---|---|---|---|
| [1] | techspecs.ui.com/unifi/wifi/u7-lite | Official manufacturer spec sheet | **Definitive** — primary source |
| [2] | Dong Knows Tech review (dongknows.com) | Independent third-party review with hands-on testing | **High** — tested unit, corroborates official specs |
| [3] | community.ui.com — Pre-Sales thread | User forum with Ubiquiti staff/community replies | **Medium-High** — community-verified but not official |
| [4] | Reddit r/Ubiquiti — U-POE-af pricing | User discussion | **Low** — informal pricing reference |
| [5] | Web search result — injector passthrough | Aggregated search summary | **Low** — synthesized, not a single source |
| [6] | Web search result — 9W typical draw | Aggregated search summary | **Low** — not independently verified |
| [7] | IEEE 802.3af standard (via Wikipedia) | Standards body | **Definitive** for the standard itself |
| [8] | store.ui.com — U-PoE+ product page | Official store listing | **Definitive** for pricing/specs |
| [9] | store.ui.com — UACC-PoE+-2.5G product page | Official store listing | **Definitive** for pricing/specs/compatibility |

The official Ubiquiti Tech Specs page [1] and store listings [8][9] are the most authoritative sources. The Dong Knows Tech review [2] provides independent corroboration with real power measurements. Community reports [3] on 2.5GbE passthrough behavior of Gigabit-rated injectors are informal but consistent across multiple users.

## 4. Conclusions

1. **802.3af is sufficient.** The U7 Lite draws 13W max, well within 802.3af's 15.4W. No PoE+ or PoE++ required.

2. **Gigabit injectors work for power but limit data rate.** The U-POE-af (~$8) will power the U7 Lite perfectly but caps the link at 1 Gbps. The U-PoE+ ($15) provides 30W (overkill for power) and has been reported to pass 2.5GbE unofficially.

3. **The UACC-PoE+-2.5G at $19.00 is the best value.** For only $4 more than the U-PoE+ and $11 more than the U-POE-af, it provides:
   - Official 2.5GbE support (no ambiguity)
   - Official U7 Lite compatibility listing
   - 30W PoE+ (future-proof for PoE+ devices)
   - Surge/overcurrent protection
   - No risk of discovering a Gigabit injector doesn't pass 2.5GbE with your specific cable length/quality

4. **The only reason to buy a cheaper injector** is if the upstream switch port is Gigabit and will remain so — in that case, any 802.3af Gigabit injector (including third-party) will work.

## 5. Bibliography

1. Ubiquiti Tech Specs — UniFi U7 Lite. https://techspecs.ui.com/unifi/wifi/u7-lite (accessed 2026-05-24).

2. Dong Knows Tech. "Ubiquiti U7-Lite Review: A Little Solid Dual-Band Wi-Fi 7 AP." Published 2025-06-09. https://dongknows.com/ubiquiti-u7-lite-access-point-review/ (accessed 2026-05-24).

3. Ubiquiti Community. "Pre-Sales question re Powering the U7 Lite access point." https://community.ui.com/questions/Pre-Sales-question-re-Powering-the-U7-Lite-access-point/af33c00a-7c57-4dc9-b8cc-d14a8a60de47 (accessed 2026-05-24).

4. Reddit r/Ubiquiti. "Is the Ubiquiti 802.3af PoE injector (U-POE-AF) a good deal?" https://www.reddit.com/r/Ubiquiti/comments/kqvfow/ (accessed 2026-05-24).

5. Web search: "U7 Lite 2.5GbE uplink port speed PoE injector passthrough." (2026-05-24).

6. Web search: "Ubiquiti U7 Lite datasheet PoE requirements power draw 802.3af." (2026-05-24).

7. Wikipedia. "Power over Ethernet." https://en.wikipedia.org/wiki/Power_over_Ethernet (accessed 2026-05-24).

8. Ubiquiti Store. "UniFi PoE+ Adapter (30W) — U-PoE+." https://store.ui.com/us/en/products/u-poe-plus (accessed 2026-05-24).

9. Ubiquiti Store. "UniFi 2.5G PoE+ Adapter (30W) — UACC-PoE+-2.5G." https://store.ui.com/us/en/products/uacc-poe-plus-2-5g (accessed 2026-05-24).
