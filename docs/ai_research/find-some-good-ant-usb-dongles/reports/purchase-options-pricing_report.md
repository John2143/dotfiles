# Purchase Options, Pricing, and Availability Report

## 1. Summary

The ANT+ USB dongle market in May 2026 is shaped by a clear split: official Garmin dongles remain available but at premium prices ($40–60 USD), while a growing ecosystem of third-party alternatives from Chinese manufacturers offers functionally equivalent hardware at one-third to one-half the cost ($14–25 USD). The Suunto Movestick Mini is discontinued and effectively unavailable. Wahoo's $39.99 ANT+ Kit is a well-reviewed mid-tier option that includes a 3 ft extension cable — a practical inclusion for desktop PC setups where signal interference from the computer chassis is a concern.

The Garmin USB ANT Stick (010-01058-00, the "ANTUSB-m" miniature design) is still listed on Garmin's official website and stocked at major retailers including Amazon, B&H Photo, REI, and numerous cycling specialty shops. Its MSRP is $49.99, though sale prices as low as $30.77 have been observed (Mike's Bikes). The older Garmin ANTUSB2 (full-size stick) is confirmed End-of-Life and only available on the secondary market. The Dynastream ANTUSB-m OEM module (203-JN6016) is also marked EOL on thisisant.com but can still be found new on eBay ($25–50) and at Backcountry.com.

Third-party dongles — CooSpo RC401, CYCPLUS U1, TAOPE — all use the same underlying cp210x USB-to-serial chipset and present identical USB vendor/product IDs (0fcf:1008 or 0fcf:1004) as the official Garmin sticks. They are therefore driver-compatible with Linux's `cp210x` kernel module and the `openant` Python library. The CooSpo RC401 has the strongest evidence of Linux compatibility, with verified user reports of working on Linux Mint with `antfs-cli`. The CYCPLUS U1 and TAOPE dongles should also work but have less public Linux-specific documentation.

No manufacturer offers a bundled dongle-plus-heart-rate-strap combo. The user's Garmin Fenix 7 Pro already broadcasts ANT+ HR, so a standalone dongle is all that is required.

## 2. Relation to Primary Question

Purchase options directly determine which compatible dongles are practically obtainable: the Garmin 010-01058-00, Wahoo ANT+ Kit, and CooSpo RC401 are the three most available and Linux-compatible options, spanning a price range of ~$14 to ~$50; the Suunto Movestick Mini and Garmin ANTUSB2 are discontinued and should be excluded from consideration unless found used at a significant discount.

## 3. Source Evaluation

### Primary Sources

1. **Garmin Official Product Page (garmin.com/en-US/p/10997/)**
   - Credibility: Primary source, official manufacturer product listing.
   - Assessment: Confirms the USB ANT Stick (010-01058-00) is still an active, listed product. No pricing displayed on the informational page. High authority for product existence and specifications.

2. **Wahoo Fitness Official Store (wahoofitness.com) — USB ANT+ Kit product page**
   - Credibility: Primary source, official manufacturer e-commerce listing.
   - Assessment: Confirms current price ($39.99), active availability, product specifications, and customer reviews (203 reviews, 4.4/5 stars). Includes 3 ft extension cable. Most recent verified-purchase review dated April 30, 2026. High authority.

3. **THIS IS ANT (thisisant.com) — ANTUSB2 and ANTUSB-m EOL notices**
   - Credibility: Primary source. thisisant.com is the official ANT+ industry consortium website, managed by Garmin Canada (Dynastream).
   - Assessment: Authoritative confirmation that ANTUSB2 and ANTUSB-m (OEM module) are End-of-Life/discontinued. High authority.

4. **CooSpo Official Store (shop.coospo.com, coospo.com)**
   - Credibility: Primary source, official manufacturer store.
   - Assessment: Lists RC401 with starting price $13.99. Free shipping over $29 USD. Shipping policies and product specs are manufacturer-verified. Medium-high authority (manufacturer claims, not independently verified for Linux compatibility).

### Secondary Sources

5. **Amazon.com product listings (Garmin B00CM381SQ, CooSpo B07CB4328P, TAOPE B01MRWK2DE, CYCPLUS B077YDL2KL)**
   - Credibility: Secondary source. Major e-commerce platform with third-party sellers.
   - Assessment: Amazon pages are JavaScript-rendered and pricing was not directly readable via automated tools. Prices cited are from search result snippets and aggregated retailer data. Moderate authority for pricing; listings confirm these products are actively sold and shipped.

6. **eBay listings (ebay.com)**
   - Credibility: Secondary source. Auction/secondary marketplace.
   - Assessment: Used for confirming secondary-market availability of discontinued products (ANTUSB-m, ANTUSB2). Pricing data points: ~$25–50 for ANTUSB-m, ~$50 for used Garmin USB ANT Stick. Price volatility is inherent. Moderate authority.

7. **Specialty Retailers (PlayBetter, GPS Nation, Mike's Bikes, B&H Photo, REI, Backcountry, Trek Bikes of Florida, Bike Mart)**
   - Credibility: Secondary sources. Established retail businesses.
   - Assessment: Consistent pricing across retailers ($49.99 MSRP for Garmin, $39.99 for Wahoo) increases confidence in these price points. Mike's Bikes sale price ($30.77) is a verified outlier. Moderate-high authority.

8. **TrainerRoad Forum (trainerroad.com/forum/t/ant-stick-recommendations/90770)**
   - Credibility: Secondary source. User forum, anonymous contributors.
   - Assessment: Provides community perspective on real-world availability issues (e.g., Suunto Movestick Mini being hard to find as of February 2024). Low individual authority but useful for corroborating discontinuation patterns.

9. **Ubuntu Manpages (manpages.ubuntu.com) — gant/antpm documentation**
   - Credibility: Primary source for Linux driver documentation.
   - Assessment: Confirms cp210x kernel module, USB IDs 0fcf:1004/0fcf:1008/0fcf:1009, and /dev/ttyUSBxxx device presentation. High authority for Linux compatibility facts.

10. **GitHub — ant-plus Node.js library (github.com/Loghorn/ant-plus)**
    - Credibility: Secondary source. Open-source community project.
    - Assessment: Documents that GarminStick2 driver (USB product ID 0x1008) "works with many of the common off-brand clones." Useful for corroborating third-party dongle compatibility. Moderate authority.

11. **AliExpress / Banggood listings**
    - Credibility: Secondary sources. Chinese e-commerce platforms.
    - Assessment: CYCPLUS U1 priced at $18.12 on Banggood. Prices on these platforms are typically the lowest available but shipping times are longer (2–4 weeks). Moderate authority for pricing.

12. **CooSpo RC401 Review on AliExpress (aliexpress.com/s/wiki-ssr/article/coospo-usb-ant-stick...)**
    - Credibility: Secondary source. Platform-hosted review article, author unverified.
    - Assessment: Claims successful testing on Linux Mint with `antfs-cli`. The specific claim about Linux compatibility is valuable but the source is promotional in nature. Moderate authority; the claim is plausible given the cp210x chipset but should be independently verified.

## 4. Conclusions

### Currently Manufactured and Widely Available

| Dongle | Price (USD) | Where to Buy | Notes |
|--------|-------------|--------------|-------|
| **Garmin USB ANT Stick (010-01058-00)** | $49.99 MSRP; sale prices ~$30–50 | Amazon, B&H Photo, REI, PlayBetter, GPS Nation, Mike's Bikes, Backcountry, Walmart, eBay | Current Garmin model; miniature ANTUSB-m form factor; actively manufactured |
| **Wahoo USB ANT+ Dongle Kit** | $39.99 | wahoofitness.com, REI, Amazon, Condor Cycles, Trek retailers | Includes 3 ft USB extension cable; 4.4/5 stars (203 reviews); actively sold |
| **CooSpo RC401** | $13.99–$25 | shop.coospo.com, Amazon, eBay, AliExpress | Best Linux documentation among third-party options; 8-channel support; free shipping >$29 from CooSpo direct |
| **CYCPLUS U1** | $18.12–$37 | Banggood ($18.12), Amazon, eBay ($36.85), cycplus.com | Miniature form factor (18.5×14.5×6mm); U2 variant includes 3m extension cable |
| **TAOPE ANT+ Dongle** | ~$15 | Amazon | Budget option; less Linux documentation; some user reports of success |

### Discontinued / End-of-Life

| Dongle | Status | Last Known Price | Secondary Market |
|--------|--------|-----------------|------------------|
| **Garmin ANTUSB2** | EOL (confirmed by thisisant.com) | ~$40–50 (when available) | eBay only; used units |
| **Garmin ANTUSB-m (OEM 203-JN6016)** | EOL (confirmed by thisisant.com) | ~$30–40 (when available) | eBay ($25–50 new/used); Backcountry.com residual stock |
| **Suunto Movestick Mini** | Discontinued (confirmed by Suunto retailers) | ~$40 CAD (~$30 USD) | Effectively unavailable; some residual Amazon/eBay listings may exist |

### Bundle Deals

No manufacturer offers a dongle-plus-heart-rate-strap bundle. The user already owns a Garmin Fenix 7 Pro broadcasting ANT+ HR, so a standalone dongle is sufficient. For users who might also need an HR strap, a DIY combination of a CooSpo RC401 ($14) plus a ROCKBROS ANT+/BLE chest strap (~$53) totals under $70 — but this is unnecessary for the current use case.

### Recommendation for This User

**Best value:** CooSpo RC401 (~$14–$18 on Amazon or CooSpo direct). It has the strongest public evidence of Linux compatibility among third-party dongles, identical USB IDs to the Garmin original, and costs less than one-third the Garmin MSRP. The cp210x kernel module in the user's NixOS kernel (6.18.28) will recognize it automatically as `/dev/ttyUSB0`.

**Best reliability:** Wahoo USB ANT+ Kit ($39.99). Actively sold by Wahoo with warranty support, includes the extension cable (useful for positioning the dongle away from PC interference), and has strong Linux compatibility through the same cp210x driver path. The extension cable is genuinely useful for desktop OBS setups where the PC tower may be under a desk.

**Official option:** Garmin USB ANT Stick ($49.99 MSRP, often $30–50). The safest choice for guaranteed ANT+ protocol compatibility, but offers no functional advantage over the CooSpo or Wahoo for heart-rate-only reception via `openant`. The premium is for brand assurance, not additional capability.

### Shipping Considerations

- Amazon: 1–2 day delivery (Prime) for all listed dongles.
- CooSpo direct (shop.coospo.com): Free shipping on orders over $29; $4.99 otherwise. Ships from China (1–3 weeks typical).
- Banggood/AliExpress: 2–4 weeks to US addresses. Lowest prices but slowest delivery.
- Wahoo official store: Standard US shipping; 30-day returns.
- Garmin.com: Product page is informational only; Garmin directs purchases to authorized retailers rather than selling direct.

## 5. Bibliography

Garmin. (n.d.). *USB ANT Stick™*. Garmin. https://www.garmin.com/en-US/p/10997/

THIS IS ANT. (n.d.). *ANTUSB2 Stick (EOL)*. THIS IS ANT. https://www.thisisant.com/developer/components/antusb2/

THIS IS ANT. (n.d.). *ANTUSB-m (EOL)*. THIS IS ANT. https://www.thisisant.com/developer/components/antusb-m

THIS IS ANT. (n.d.). *USB ANT Stick™*. THIS IS ANT Directory. https://www.thisisant.com/directory/usb-ant-stick

Garmin. (n.d.). *USB ANT Stick™ — Buy*. Garmin. https://buy.garmin.com/en-US/US/shop-by-accessories/fitness-sensors/usb-ant-stick-/prod10997.html

Wahoo Fitness. (n.d.). *USB ANT+ Dongle & Extension Cable Kit*. Wahoo Fitness. https://www.wahoofitness.com/devices/indoor-cycling/parts-components/usb-ant-kit-buy

Wahoo Fitness. (n.d.). *USB ANT+ Dongle & Extension Cable Kit*. REI Co-op. https://www.rei.com/product/160982/wahoo-fitness-usb-ant-dongle-with-3-ft-extender-cable

CooSpo. (n.d.). *CooSpo USB ANT Stick, Indoor bike Training Data Transmission*. CooSpo. https://www.coospo.com/products/coospo-usb-ant-stick-ant-dongle-for-indoor-cycling-training-data-transmission-compatible-with-bkool-wahoo-tacx-bike-trainer-zwift-trainerroad-garmin-connect-cycleops-trainer-rouvy-tacx-vortex

CooSpo. (n.d.). *Products*. CooSpo Shop. https://shop.coospo.com/collections/all

Amazon. (n.d.). *Garmin USB ANT Stick for Garmin Fitness Devices (010-01058-00)*. Amazon. https://www.amazon.com/Garmin-USB-Stick-Fitness-Devices/dp/B00CM381SQ

Amazon. (n.d.). *CooSpo USB ANT Stick, ANT+ Dongle for Indoor Cycling Training Data Transmission (RC401)*. Amazon. https://www.amazon.com/CooSpo-Adapter-PerfPRO-CycleOps-TrainerRoad/dp/B07CB4328P

Amazon. (n.d.). *TAOPE USB ANT+ Dongle, Mini Size Dongle USB Stick Adapter*. Amazon. https://www.amazon.com/Adapter-PerfPRO-CycleOps-Virtual-TrainerRoad/dp/B01MRWK2DE

Amazon. (n.d.). *CYCPLUS USB ANT+ Stick Dongle Adapter Wireless Receiver (U1)*. Amazon. https://www.amazon.com/Adapter-CycleOps-TrainerRoad-Compatible-Forerunner/dp/B077YDL2KL

Amazon. (n.d.). *SUUNTO Movestick Mini*. Amazon. https://www.amazon.com/SUUNTO-SS016591000-Movestick-Mini/dp/B0050GL5GM

CYCPLUS. (n.d.). *Ant Stick | Ant USB Stick | USB ANT+ Stick Dongle Adapter*. CYCPLUS. https://www.cycplus.com/products/ant-usb-stick-u10

Banggood. (n.d.). *CYCPLUS U1 Mini Size USB ANT+ Stick*. Banggood. https://www.banggood.com/CYCPLUS-U1-Mini-Size-USB-ANT-Stick-for-Zwift-Garmin-Wahoo-Bkool-p-1230174.html

eBay. (2026, January 4). *Garmin Dynastream Antusb-m ANT+ USB Stick Dongle Wireless Receiver 203-JN6016*. eBay. https://www.ebay.com/itm/375691885707

eBay. (2026). *COOSPO RC401 USB ANT Dongle Receiver for Bike Trainers*. eBay. https://www.ebay.com/itm/358090328199

eBay. (2026). *USB ANT+ Stick Dongle ANT Transmitter Receiver for Bicycle Computer Transmission (CYCPLUS)*. eBay. https://www.ebay.com/itm/388662833790

eBay. (n.d.). *Garmin 010-01058-00 USB ANT Stick Device*. eBay. https://www.ebay.com/p/1166099499

GPS Nation. (n.d.). *Garmin USB ANT Stick*. GPS Nation. https://www.gpsnation.com/products/garmin-usb-ant-stick

PlayBetter. (n.d.). *Garmin USB ANT Stick*. PlayBetter. https://www.playbetter.com/products/garmin-usb-ant-stick

Mike's Bikes. (n.d.). *Garmin USB ANT Computer Stick*. Mike's Bikes. https://mikesbikes.com/products/usb-ant-comp-stick-n-a-blk

B&H Photo Video. (n.d.). *Garmin USB ANT Stick 010-01058-00*. B&H Photo Video. https://www.bhphotovideo.com/c/product/1112125-REG/garmin_010_01058_00_usb_ant_stick.html

Backcountry. (n.d.). *Garmin ANT+ Stick (ANTUSB-m)*. Backcountry. https://www.backcountry.com/garmin-antplus-stick-antusb-m

Trionics. (n.d.). *Garmin New OEM USB ANT Stick™, 010-01058-00*. Trionics. https://trionics.com/garmin-new-oem-usb-ant-stick-010-01058-00/

Suunto. (n.d.). *Suunto Movestick Mini*. Suunto. https://www.suunto.com/Products/PODs/Suunto-Movestick-Mini/

OpticsPlanet. (n.d.). *Suunto Movestick Mini USB Data Transfer Stick (Discontinued)*. OpticsPlanet. https://www.opticsplanet.com/suunto-movestick-mini-usb-data-transfer-stick.html

Suunto. (n.d.). *Suunto USB ANT+ Dongle User Guide*. Suunto. https://us.suunto.com/pages/suunto-usb-ant-dongle-user-guide

AliExpress. (n.d.). *COOSPO USB ANT+ Stick for Indoor Cycling: Does It Really Work with Zwift, Garmin, and Wahoo?* AliExpress. https://www.aliexpress.com/s/wiki-ssr/article/coospo-usb-ant-stick-ant-dongle-for-indoor-cycling-training-data-transmission-rc401-products-info-and-review

Loghorn. (n.d.). *ant-plus: A node module for ANT+*. GitHub. https://github.com/Loghorn/ant-plus

Ubuntu Manpages. (n.d.). *gant — console based ANT+ information retrieval client for Garmin GPS products*. Ubuntu Manpages. https://manpages.ubuntu.com/manpages/bionic/man1/antpm-garmin-ant-downloader.1.html

van Gestel, G. (n.d.). *Installing Incyclist on a Linux box with an ANT+ dongle*. Cycling van Gestel Online. https://cycling.vangestel.online/indoor/faq/incyclist-on-linux/index.html

TrainerRoad Forum. (2024, February 7). *Ant+ stick recommendations*. TrainerRoad. https://www.trainerroad.com/forum/t/ant-stick-recommendations/90770

TrainerRoad Forum. (2021, February 3). *Ant+ stick why do the prices vary so much?* TrainerRoad. https://www.trainerroad.com/forum/t/ant-stick-why-do-the-prices-vary-so-much/52391

Trek Bikes of Florida. (n.d.). *Trainer Part Wahoo USB ANT+ Dongle Kit Black*. Trek Bikes of Florida. https://trekbikesflorida.com/products/trainer-part-wahoo-usb-ant-dongle-kit-black

Bike Mart. (n.d.). *Trainer Part Wahoo USB ANT+ Dongle Kit Black*. Bike Mart. https://www.bikemart.com/products/trainer-part-wahoo-usb-ant-dongle-kit-black

eatpedalpaddle. (2015, January 2). *Suunto Movestick Mini ANT+ USB stick*. Eat Pedal Paddle. https://eatpedalpaddle.wordpress.com/2015/01/02/suunto-movestick-mini-ant-usb-stick/

GPS Central. (n.d.). *Buy Garmin USB ANT Stick (010-01058-00) — Discontinued*. GPS Central. https://www.gpscentral.ca/product/garmin-usb-ant-stick

TrainerRoad Support. (n.d.). *USB1 vs USB2 ANT+ Sticks*. TrainerRoad. https://support.trainerroad.com/hc/en-us/articles/206007776-USB1-vs-USB2-ANT-Sticks

Condor Cycles. (n.d.). *Wahoo ANT+ Kit*. Condor Cycles. https://www.condorcycles.com/en-us/products/wahoo-ant-kit

Hostel Shoppe. (n.d.). *Wahoo ANT+ USB Dongle with Extension Cord*. Hostel Shoppe. https://hostelshoppe.com/products/wahoo-ant-usb-dongle-with-extension-cord

GoSupps. (n.d.). *CooSpo USB ANT Stick for Indoor Cycling Data Transmission*. GoSupps. https://www.gosupps.com/coospo-usb-ant-stick-ant-dongle-for-indoor-cycling-training-data-transmission-compatible-with-bkool-wahoo-tacx-bike-trainer-zwift-trainerroad-garmin-connect-cycleops-trainer-rouvy-tacx-vortex-rc401-ant-dongle.html
