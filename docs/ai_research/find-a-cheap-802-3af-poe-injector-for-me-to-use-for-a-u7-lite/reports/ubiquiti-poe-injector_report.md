# Ubiquiti UACC-PoE+-2.5G Injector Report

## 1. Summary

The **Ubiquiti UACC-PoE+-2.5G** (also branded as "UniFi 2.5G PoE+ Adapter (30W)") is an active IEEE 802.3at (PoE+) injector sold directly by Ubiquiti for **$19.00 USD** on the official store. It delivers up to 30 W at 48 V DC (0.65 A), supports 2.5 Gigabit Ethernet (2.5GbE) data passthrough, includes a grounded AC power cord, and provides comprehensive surge, peak-pulse, and overcurrent protection. It is backward-compatible with 802.3af devices and is explicitly listed by Ubiquiti as compatible with the U7 Lite access point.

## 2. Relation to Primary Question

The primary research question is to find a cheap 802.3af PoE injector for a U7 Lite access point. The UACC-PoE+-2.5G is directly relevant:

### 2.1 U7 Lite Power Requirements

The U7 Lite (U7-Lite, $99.00 USD) has the following PoE characteristics per Ubiquiti's official tech specs:

| Parameter | Value |
|---|---|
| Max. Power Consumption | 13 W |
| Supported Voltage Range | 42.5–57 V DC |
| PoE Standard Required | 802.3af (PoE) |
| Uplink | 2.5 GbE RJ45 |

The U7 Lite draws ~10 W typical, 13 W maximum. Any standard 802.3af (15.4 W) or 802.3at (30 W) source will power it.

### 2.2 UACC-PoE+-2.5G Compatibility

The UACC-PoE+-2.5G outputs 48 V DC at up to 0.65 A (30 W) — more than double the U7 Lite's maximum draw. Ubiquiti explicitly lists the U7 Lite among the 10 compatible devices on the product page. The 2.5GbE passthrough matches the U7 Lite's 2.5GbE uplink without bottlenecking.

### 2.3 Comparison with Cheaper Ubiquiti Options

| Injector | Price (USD) | PoE Standard | Max Output | Ethernet | Compatible with U7 Lite? |
|---|---|---|---|---|---|
| **U-POE-af** (15W PoE Adapter) | $8.00 | 802.3af | 15 W | Gigabit only | Electrically yes; not listed by Ubiquiti (would bottleneck 2.5GbE uplink to 1 Gbps) |
| **U-POE-at** (30W PoE+ Adapter) | $15.00 | 802.3at | 30 W | Gigabit only | Electrically yes; not listed (same bottleneck) |
| **UACC-PoE+-2.5G** | **$19.00** | **802.3at (af compatible)** | **30 W** | **2.5GbE** | **Yes — explicitly listed** |

### 2.4 The Bottleneck Question

The U7 Lite has a 2.5GbE uplink. Using a Gigabit-only injector (U-POE-af at $8 or U-POE-at at $15) will cap the wired link at 1 Gbps. While the U7 Lite's WiFi 7 radios can theoretically exceed 1 Gbps aggregate (4.3 Gbps on 5 GHz, 688 Mbps on 2.4 GHz), in practice many deployments are limited by their internet connection or switch port anyway. A community discussion on the Ubiquiti forum confirmed that users who only have Gigabit infrastructure are successfully using the U-POE-af with the U7 Lite.

For the extra $11 over the U-POE-af (or $4 over the U-POE-at), the UACC-PoE+-2.5G future-proofs the link and eliminates the bottleneck.

## 3. Source Evaluation

### 3.1 Primary Sources (Authoritative)

- **store.ui.com/us/en/products/uacc-poe-plus-2-5g** — Official Ubiquiti product page. Confirmed $19.00 USD price, specs, compatibility list (includes U7 Lite), and "in the box" contents (includes AC cable with earth ground). **High confidence.**
- **techspecs.ui.com/unifi/accessories/uacc-poe-plus-2-5g** — Official Ubiquiti tech specs page. Confirmed all electrical and physical specifications. **High confidence.**
- **techspecs.ui.com/unifi/wifi/u7-lite** — Official U7 Lite tech specs. Confirmed 13 W max consumption, 2.5 GbE uplink, 42.5–57 V DC voltage range. **High confidence.**
- **store.ui.com/us/en/products/u-poe-af** — Official Ubiquiti page for the 15W PoE adapter ($8.00). Confirmed specs for comparison. **High confidence.**

### 3.2 Secondary Sources

- **dl.ubnt.com/datasheets/poe/PoE_Adapters_DS.pdf** — Ubiquiti's PoE adapters datasheet. Covers the general adapter line; used to cross-reference specifications. **High confidence.**
- **community.ui.com/questions/…/af33c00a-7c57-4dc9-b8cc-d14a8a60de47** — Ubiquiti Community discussion confirming U7 Lite works with U-POE-af (802.3af) and community reports that older Gigabit-labeled Ubiquiti injectors sometimes pass 2.5GbE despite not being marketed as such. **Medium confidence** (community anecdote, not official).
- **reddit.com/r/Ubiquiti/comments/1fw12ph** — Reddit discussion where a user reports powering two U7 Pros via the UACC-PoE+-2.5G with stable 2.5GbE throughput. **Medium confidence** (user anecdote).
- **broadbandbuyer.com, bhphotovideo.com, adorama.com** — Third-party retailer listings showing price ranges ($89–$119 at some resellers). These inflated prices are from third-party scalpers/resellers; the official Ubiquiti store price is $19.00. **Low confidence** for pricing; useful only to highlight the MSRP vs. reseller markup.

### 3.3 Price Discrepancy Note

Third-party retailer listings show the UACC-PoE+-2.5G at $89–$119.44 USD, but the official Ubiquiti Store price is $19.00. This is a common pattern with in-demand Ubiquiti products — resellers mark up when official stock is low or when they are targeting enterprise procurement. Always check store.ui.com for the real price.

## 4. Conclusions

### 4.1 Is the UACC-PoE+-2.5G the best value for powering a U7 Lite?

**Yes, with a caveat.** At $19.00, the UACC-PoE+-2.5G is the cheapest 2.5GbE-capable PoE injector available from any reputable manufacturer, and it is the official Ubiquiti-recommended injector for the U7 Lite. It provides:

- Full 2.5GbE passthrough (matching the U7 Lite's uplink)
- 30 W PoE+ (more than double the 13 W the U7 Lite needs)
- Industrial-grade surge protection (1500 A surge discharge, <1 ns response time)
- Grounded AC power cord included
- 87%+ efficiency
- NDAA compliant, with CE/FCC/IC/UL/UKCA/KC/CCC/RoHS certifications

The caveat: if your network infrastructure is entirely Gigabit (1 Gbps switch, 1 Gbps internet), the $8.00 U-POE-af will power the U7 Lite just fine and you will not notice the bottleneck. The UACC-PoE+-2.5G is $11 more but buys 2.5GbE capability you may not be using.

### 4.2 Included Accessories

Per the Ubiquiti store product page:
- RJ45 data input port
- **Grounded AC power cable** (included)
- PoE+ output port
- LED status indicator
- Wall-mountable design

No separate power cord purchase is needed — it ships with the AC cable.

### 4.3 Key Specifications

| Spec | Value |
|---|---|
| Model | UACC-PoE+-2.5G |
| Dimensions | 93 × 62 × 35 mm (3.7 × 2.4 × 1.4 in) |
| Weight | 156 g (5.5 oz) |
| Output | 48 V DC @ 0.65 A (30 W) |
| Input | 100–240 V AC, 50/60 Hz, 0.75 A max |
| PoE Standard | 802.3at (PoE+), backward-compatible with 802.3af |
| Ethernet | 2× RJ45, 10/100/1000/2500 Mbps |
| Powering Pairs | Pins 4,5 (+) and 7,8 (−) — 2-pair (Mode B) |
| Surge Protection | 1500 A (8/20 µs) power; 36 A (10/1000 µs) data peak pulse |
| Clamping | 11 V Data, 60 V Power |
| Efficiency | >87% |
| Operating Temp | 0–40 °C (32–104 °F) |
| Certifications | CE, FCC, IC, UL, UKCA, KC, CCC, RoHS |
| NDAA Compliant | Yes |

### 4.4 Recommendation

For powering a U7 Lite, the UACC-PoE+-2.5G at **$19.00** is the best value 2.5GbE PoE injector available. If you absolutely do not need 2.5GbE and want to save $11, the U-POE-af at $8.00 works electrically. However, the $19 price is low enough that the future-proofing argument strongly favors the UACC-PoE+-2.5G.

## 5. Bibliography

1. Ubiquiti Store. "UniFi 2.5G PoE+ Adapter (30W) — UACC-PoE+-2.5G." https://store.ui.com/us/en/products/uacc-poe-plus-2-5g. Accessed 2026-05-24.

2. Ubiquiti Tech Specs. "UniFi 2.5G PoE+ Adapter (30W)." https://techspecs.ui.com/unifi/accessories/uacc-poe-plus-2-5g. Accessed 2026-05-24.

3. Ubiquiti Tech Specs. "Access Point U7 Lite." https://techspecs.ui.com/unifi/wifi/u7-lite. Accessed 2026-05-24.

4. Ubiquiti Store. "Access Point U7 Lite." https://store.ui.com/us/en/products/u7-lite. Accessed 2026-05-24.

5. Ubiquiti Store. "UniFi PoE Adapter (15W) — U-PoE." https://store.ui.com/us/en/products/u-poe-af. Accessed 2026-05-24.

6. Ubiquiti. "PoE Adapters Datasheet." https://dl.ubnt.com/datasheets/poe/PoE_Adapters_DS.pdf. Accessed 2026-05-24.

7. Ubiquiti Community. "Pre-Sales question re Powering the U7 Lite access point." https://community.ui.com/questions/Pre-Sales-question-re-Powering-the-U7-Lite-access-point/af33c00a-7c57-4dc9-b8cc-d14a8a60de47. Posted ~March 2025. Accessed 2026-05-24.

8. r/Ubiquiti. "Does PoE+ injector support 2.5Gbe?" https://www.reddit.com/r/Ubiquiti/comments/1fw12ph/. Posted October 2024. Accessed 2026-05-24.

9. B&H Photo. "Ubiquiti 2.5G PoE+ Adapter (30W)." https://www.bhphotovideo.com/c/product/1895495-REG/. Accessed 2026-05-24.

10. EuroSupplies. "Datasheet 2.5G PoE+ Adapter (30W)." https://www.eurosupplies.com/files/product/112896.pdf. Accessed 2026-05-24.
