# Compatible ANT+ USB Dongle Models for Linux

## 1. Summary

ANT+ USB dongles fall into two distinct architectural families with meaningful implications for Linux compatibility. The older **ANTUSB1** (also labeled ANT2USB, USB ID `0fcf:1004`) uses a two-chip design: a Nordic nRF24AP1 ANT baseband processor paired with a Silicon Labs CP210x USB-to-UART bridge. This dongle is driven by the `cp210x` kernel module, presents as a serial port (`/dev/ttyUSBx`), and communicates at 115,200 baud. It supports only 4 ANT channels and has been discontinued for over a decade. The openant library accesses it via pyserial as its `SerialDriver`.

The newer, fully-integrated design — built around the Nordic nRF24AP2-USB single-chip solution with native USB support — is used in three commercially relevant dongles: the **ANTUSB2** (`0fcf:1008`), the **ANTUSB-m** (`0fcf:1009`), and the **Suunto Movestick Mini** (which reports as either `0fcf:1008` or `0fcf:1009` depending on the unit). These are 8-channel devices. On modern Linux kernels, the `usb-serial-simple` (suunto) driver binds to them automatically, creating a `/dev/ttyUSBx` node, but this is incidental: openant **detaches** the kernel driver at runtime and communicates directly with the USB endpoints via libusb/PyUSB (`USB2Driver` for `0fcf:1008`, `USB3Driver` for `0fcf:1009`). This is by design — the openant library does not use the serial device node for these dongles.

Critically, the three USB IDs `0fcf:1004`, `0fcf:1008`, and `0fcf:1009` are the only ones hardcoded in openant's driver detection logic. Third-party/clone dongles (CooSpo, Fitcent, Docooler, etc.) typically present different USB vendor/product IDs and may use entirely different chipsets (e.g., nRF52832 BLE SoCs with ANT capability). These **will not work out of the box with openant** and would require source modifications to add new driver classes. For the user's goal — receiving ANT+ heart rate broadcasts from a Garmin Fenix 7 Pro on NixOS — a genuine Dynastream/Garmin dongle presenting `0fcf:1008` or `0fcf:1009` is the only reliable path. All three compatible models are discontinued as new retail products, but the ANTUSB-m remains available as new-old-stock on eBay.

## 2. Relation to Primary Question

The dongle model and USB ID directly determine which openant driver codepath is used, whether udev rules are needed, and whether the device will function at all — making model selection the single most consequential decision in the purchasing pipeline.

## 3. Source Evaluation

### Source 1: Linux kernel source — `cp210x.c` (torvalds/linux, master branch)
- **URL:** https://github.com/torvalds/linux/blob/master/drivers/usb/serial/cp210x.c
- **Assessment:** Primary source. Official kernel source. Authoritative for which USB IDs the cp210x driver claims. The file lists `0fcf:1003`, `0fcf:1004`, and `0fcf:1006` as Dynastream ANT devices. **Verified directly** — the raw file was read and the `id_table[]` was inspected. Absence of `0fcf:1008` and `0fcf:1009` from this table confirms those are NOT cp210x devices.
- **Weight:** Maximum. Definitive.

### Source 2: Linux kernel source — `usb-serial-simple.c` (torvalds/linux, master branch)
- **URL:** https://github.com/torvalds/linux/blob/master/drivers/usb/serial/usb-serial-simple.c
- **Assessment:** Primary source. Official kernel source. The `SUUNTO_IDS()` macro lists `0fcf:1008` and `0fcf:1009` as "Dynastream ANT USB-m Stick". The driver name "suunto" is a historical artifact. **Verified directly** — the raw file was read.
- **Weight:** Maximum. Definitive.

### Source 3: openant Python library source — `driver.py` (Tigge/openant, master branch)
- **URL:** https://github.com/Tigge/openant/blob/master/openant/base/driver.py
- **Assessment:** Primary source. The actual implementation being used. Three driver classes are defined: `SerialDriver` (VID 0x0FCF, PID 0x1004), `USB2Driver` (0x1008), and `USB3Driver` (0x1009). The `USBDriver.open()` method explicitly calls `dev.detach_kernel_driver(0)`. **Verified directly** — the raw file was read.
- **Weight:** Maximum. Definitive for what openant actually does.

### Source 4: openant udev rules file — `42-ant-usb-sticks.rules` (Tigge/openant)
- **URL:** https://github.com/Tigge/openant/blob/master/resources/42-ant-usb-sticks.rules
- **Assessment:** Primary source. Contains udev rules for exactly `0fcf:1008` and `0fcf:1009` with `TAG+="uaccess"` and `MODE="0666"`. Does NOT include `0fcf:1004` — consistent with the fact that the ANTUSB1 uses serial port access, not raw USB.
- **Weight:** Maximum.

### Source 5: THIS IS ANT Developer Forum — "ANT USB-Stick as COM-Port?" (2011)
- **URL:** https://www.thisisant.com/forum/viewthread/2082
- **Assessment:** Primary/official. Dynastream/Garmin staff (user "Marc") responding on the official ANT developer forum. Confirms: "USB1 is based on nRF24AP1 + Silabs CP210x" and "USB2 is not based on the CP210x, it is based on the nRF24AP-USB." Corroborated by kernel source and openant source. Dated (2011) but concerns stable hardware facts.
- **Weight:** High. Official source, hardware facts are time-invariant.

### Source 6: THIS IS ANT Tech FAQ
- **URL:** https://www.thisisant.com/developer/resources/tech-faq/category/2/
- **Assessment:** Official. Confirms driver architecture differences between ANTUSB1 (SiLabs-based) and ANTUSB2/ANTUSB-m (libusb-win32 based). States "A Linux SDK for ANTUSB2 and ANTUSB-m sticks is currently in Beta" — this appears dated/abandoned; the community-developed openant has superseded it. Also states ANTUSB1 Linux drivers are "not currently being planned."
- **Weight:** Medium-high. Official but dated; some statements may reflect 2013-era product status.

### Source 7: Linux Kernel Driver Database (cateee.net)
- **URLs:**
  - https://cateee.net/lkddb/web-lkddb/USB_SERIAL_CP210X.html
  - https://cateee.net/lkddb/web-lkddb/USB_SERIAL_SIMPLE.html
  - https://cateee.net/lkddb/web-lkddb/USB_SERIAL_SUUNTO.html
- **Assessment:** Secondary source. Auto-generated database of kernel configuration symbols and their associated device IDs. Useful for quick lookups of supported kernel versions and device mappings. Corroborates all primary source findings about USB ID-to-driver mappings.
- **Weight:** Medium. Auto-generated; useful for cross-reference but secondary.

### Source 8: Debian/Ubuntu manpages — `antpm-garmin-ant-downloader(1)`
- **URL:** https://manpages.debian.org/testing/antpm/antpm-garmin-ant-downloader.1.en.html
- **Assessment:** Secondary but reliable. Package documentation for the `antpm` suite (a separate ANT tools package, not openant). Confirms USB IDs, cp210x module usage, and serial port presentation. Useful for corroboration.
- **Weight:** Medium.

### Source 9: bin.re blog — "Track Your Heartrate on Raspberry Pi with Ant+" 
- **URL:** https://bin.re/blog/track-your-heartrate-on-raspberry-pi-with-ant/
- **Assessment:** Community/enthusiast source. Anonymous author. Demonstrates practical Suunto Movestick Mini usage on Linux with `usbserial` module. Useful for confirming the Movestick Mini reports as `0fcf:1008` (and sometimes `0fcf:1009`) and describing the `modprobe usbserial` workaround (pre-kernel 3.14).
- **Weight:** Low-medium. Unverified author, anecdotal, but consistent with kernel sources.

### Source 10: Google Groups — golden-cheetah-users "ant+ usb stick problems"
- **URL:** https://groups.google.com/g/golden-cheetah-users/c/umauL-_gbZE
- **Assessment:** Community source. User "Jon" (likely Jon Eskdale, GoldenCheetah developer) confirms `0fcf:1004` = USB1, `0fcf:1008` = USB2. Includes udev rules examples. Corroborates primary sources.
- **Weight:** Medium. Developer-adjacent, but a mailing list post, not official documentation.

### Source 11: ANTUSB2 Stick product page — THIS IS ANT
- **URL:** https://www.thisisant.com/developer/components/antusb2/
- **Assessment:** Official. Confirms the ANTUSB2 is discontinued (EOL).
- **Weight:** High.

### Source 12: Garmin USB ANT Stick product page
- **URL:** https://www.garmin.com/en-US/p/10997/
- **Assessment:** Official Garmin retail page. This is the current retail product, but notably Garmin does not disclose the USB PID or chipset on this page. It is almost certainly an ANTUSB-m internally, but this cannot be confirmed without a teardown.
- **Weight:** Medium. Official but technically opaque.

### Source 13: CooSpo product page / AliExpress community articles
- **URL:** https://www.coospo.com/products/coospo-usb-ant-stick-ant-dongle-for-indoor-cycling-training-data-transmission-compatible-with-bkool-wahoo-tacx-bike-trainer-zwift-trainerroad-garmin-connect-cycleops-trainer-rouvy-tacx-vortex
- **Assessment:** Vendor marketing. Claims nRF52832 chipset (not nRF24AP2-USB). USB VID/PID not disclosed. Community articles on AliExpress suggest Linux compatibility but do not specify openant compatibility. The nRF52832 is a Bluetooth SoC with ANT capability via SoftDevice; its USB interface is likely a custom vendor-specific protocol, not the nRF24AP2-USB protocol that openant expects.
- **Weight:** Low. Vendor claims without technical verification; chipset information from a marketplace content farm rather than official specs.

### Source 14: Nordic Semiconductor product pages — nRF24AP2-USB
- **URL:** https://www.thisisant.com/developer/components/nrf24ap2-usb
- **Assessment:** Official chipset documentation. Confirms nRF24AP2-USB is NRND (Not Recommended for New Designs), integrated 8-channel ANT processor with full-speed USB 2.0. Confirms this is the chip inside ANTUSB2 and ANTUSB-m.
- **Weight:** High. Official chip vendor documentation.

### Source 15: eBay listings — ANTUSB-m (Garmin DynaStream)
- **URL:** https://www.ebay.com/itm/395176001674
- **Assessment:** Commercial marketplace listing. Confirms availability of ANTUSB-m as new-old-stock from Taiwanese sellers. Part number 203-JN6016. Does not provide technical specifications but confirms supply availability.
- **Weight:** Low for technical claims; informative for availability.

## 4. Conclusions

### 4.1 Architecture Summary

| Model | USB ID | Chipset | Kernel Module | openant Driver | Interface | Channels | Status |
|-------|--------|---------|---------------|----------------|-----------|----------|--------|
| ANTUSB1 (ANT2USB) | `0fcf:1004` | nRF24AP1 + CP210x | `cp210x` | `SerialDriver` (pyserial) | `/dev/ttyUSBx` @ 115200 | 4 | Discontinued |
| ANTUSB2 | `0fcf:1008` | nRF24AP2-USB | `usb-serial-simple` (suunto)* | `USB2Driver` (libusb) | Raw USB endpoints | 8 | Discontinued (EOL) |
| ANTUSB-m | `0fcf:1009` | nRF24AP2-USB | `usb-serial-simple` (suunto)* | `USB3Driver` (libusb) | Raw USB endpoints | 8 | Available (NOS) |
| Suunto Movestick Mini | `0fcf:1008` or `0fcf:1009` | nRF24AP2-USB (inferred) | `usb-serial-simple` (suunto)* | `USB2Driver` or `USB3Driver` | Raw USB endpoints | 8 | Discontinued |
| Third-party clones | Varies | Varies (nRF52832, etc.) | Varies | **None** (requires code changes) | Varies | Varies | Available |

\* The kernel driver is detached at runtime by openant; the device is accessed via libusb, not the serial node.

### 4.2 Recommended Models for the User's Use Case

**Primary recommendation: ANTUSB-m (`0fcf:1009`)**
- Directly supported by openant's `USB3Driver` (first driver checked in the detection loop).
- 8 channels — more than sufficient for receiving a single heart rate broadcast.
- Still available as new-old-stock on eBay (search for "Garmin DynaStream ANT+ ANTUSB-m" or "Garmin 203-JN6016").
- Small, low-profile form factor ideal for a permanently-connected laptop.
- No special kernel module configuration needed — the `usb-serial-simple` module is built into all modern kernels, and openant detaches it anyway.

**Secondary recommendation: ANTUSB2 (`0fcf:1008`)**
- Also directly supported (openant's `USB2Driver`).
- 8 channels.
- Harder to find than the ANTUSB-m; officially EOL.

**Avoid: ANTUSB1 (`0fcf:1004`)**
- Only 4 channels.
- Uses serial port access — requires membership in the `dialout` group (or equivalent) for `/dev/ttyUSBx` access.
- openant's `SerialDriver` is checked **last** in the detection loop, meaning it will only be used if no USB2/USB3 device is found (this is fine in isolation, but the serial codepath is less exercised).
- Long discontinued; any units found are very old.

**Avoid: Third-party/clone dongles**
- openant hardcodes VID 0x0FCF and specific PIDs in its driver classes. A dongle with a different USB ID will not be detected.
- Some clones use nRF52832 (a Bluetooth+ANT SoC) rather than the nRF24AP2-USB ANT network processor. Even if openant were modified to detect them, the USB protocol would likely be incompatible.
- Unless you are willing to reverse-engineer the USB protocol and write a new openant driver class, these are not viable.

### 4.3 udev Rules Required

openant's `USB2Driver` and `USB3Driver` access the device via libusb (PyUSB). This requires the user to have read/write permission on the raw USB device node (e.g., `/dev/bus/usb/003/042`). openant ships a udev rules file (`42-ant-usb-sticks.rules`) that sets `MODE="0666"` and `TAG+="uaccess"` for both `0fcf:1008` and `0fcf:1009`.

**On NixOS**, the standard `sudo python -m openant.udev_rules` will fail because `/etc/udev/rules.d` is immutable. Instead, add the rules via NixOS configuration:

```nix
services.udev.extraRules = ''
  # ANT+ USB dongles — allow user access via libusb
  ACTION!="add", GOTO="ant_rules_end"
  SUBSYSTEM!="usb", GOTO="ant_rules_end"
  ATTR{idVendor}=="0fcf", ATTR{idProduct}=="1008", MODE="0666", TAG+="uaccess"
  ATTR{idVendor}=="0fcf", ATTR{idProduct}=="1009", MODE="0666", TAG+="uaccess"
  LABEL="ant_rules_end"
'';
```

Note: The `TAG+="uaccess"` will not work with `services.udev.extraRules` on NixOS due to rule ordering (the `99-local.rules` priority is too late for `uaccess`). Use `MODE="0666"` alone as shown above, or add the user to the `plugdev` group with `GROUP="plugdev"`. The `MODE="0666"` approach grants world read/write and is sufficient for single-user workstations.

### 4.4 NixOS-Specific Notes

- `python3Packages.openant` is available in nixpkgs (unstable channel). It depends on `pyusb` (for the libusb path) and optionally `pyserial` (for the ANTUSB1 serial path).
- The `cp210x` kernel module is built into the standard NixOS kernel — no configuration needed, though it is not required for ANTUSB2/ANTUSB-m operation.
- The `usb-serial-simple` module (which includes the suunto driver) is also built in. It will auto-bind to `0fcf:1008`/`0fcf:1009` and create `/dev/ttyUSBx` nodes, but openant will detach it. This is expected and harmless.
- No NixOS-specific kernel configuration changes are required for any of the recommended dongles.
- The Fenix 7 Pro broadcasts ANT+ heart rate using the standard ANT+ Heart Rate Device Profile (device type 120 / 0x78). This is a well-supported profile in openant's `devices` module. No special configuration is needed beyond the standard ANT+ heart rate monitor device class.

### 4.5 Key Caveats

1. **All compatible dongles are discontinued as new retail products.** The ANTUSB2 is officially EOL per THIS IS ANT. The Suunto Movestick Mini is discontinued. The ANTUSB-m appears as new-old-stock on eBay. There is no currently-manufactured dongle with guaranteed openant compatibility.

2. **The Garmin USB ANT Stick (010-01058-00) still sold on Amazon** is almost certainly an ANTUSB-m internally, but this cannot be confirmed without physical inspection of the USB ID. At ~$40-50 it is the most expensive option but the only one with retailer return policies.

3. **openant driver detection order** checks drivers in reverse-append order: USB3Driver (0fcf:1009) first, then USB2Driver (0fcf:1008), then SerialDriver (0fcf:1004). If both an ANTUSB-m and ANTUSB2 are plugged in simultaneously, the ANTUSB-m will be selected.

4. **The kernel's `usb-serial-simple` suunto driver** will claim 0fcf:1008/1009 devices and create `/dev/ttyUSBx` nodes. This is a cosmetic side effect — openant detaches the kernel driver. Some older guides recommend `modprobe usbserial vendor=0x0fcf product=0x1008`; this is unnecessary on kernels ≥3.14 where the suunto driver is built in.

## 5. Bibliography

Garmin. (n.d.). *Garmin USB ANT Stick*. Retrieved May 18, 2026, from https://www.garmin.com/en-US/p/10997/

Linux kernel contributors. (n.d.). *cp210x.c — Silicon Labs CP210x USB to RS232 serial adaptor driver*. Linux kernel source tree. https://github.com/torvalds/linux/blob/master/drivers/usb/serial/cp210x.c

Linux kernel contributors. (n.d.). *usb-serial-simple.c — USB Serial "Simple" driver*. Linux kernel source tree. https://github.com/torvalds/linux/blob/master/drivers/usb/serial/usb-serial-simple.c

Nordic Semiconductor. (n.d.). *nRF24AP2-USB (NRND)*. THIS IS ANT. https://www.thisisant.com/developer/components/nrf24ap2-usb

RALOVICH, K. (2014). *[PATCH] USB: simple: add Dynastream ANT USB-m Stick device support*. Linux USB mailing list. https://www.spinics.net/lists/linux-usb/msg101436.html

THIS IS ANT. (n.d.). *ANTUSB2 Stick (EOL)*. https://www.thisisant.com/developer/components/antusb2/

THIS IS ANT. (n.d.). *Tech FAQ*. https://www.thisisant.com/developer/resources/tech-faq/category/2/

THIS IS ANT Developer Forum. (2011, October 20). *ANT USB-Stick as COM-Port?* https://www.thisisant.com/forum/viewthread/2082

Tiger, G. (2025). *openant: ANT and ANT-FS Python Library* (Version 1.3.4) [Source code]. GitHub. https://github.com/Tigge/openant

Tiger, G. (2025). *openant/base/driver.py* [Source code]. In openant repository. https://github.com/Tigge/openant/blob/master/openant/base/driver.py

Tiger, G. (2025). *openant/resources/42-ant-usb-sticks.rules* [udev rules file]. In openant repository. https://github.com/Tigge/openant/blob/master/resources/42-ant-usb-sticks.rules

Tiger, G. (2025). *openant/udev_rules.py* [Source code]. In openant repository. https://github.com/Tigge/openant/blob/master/openant/udev_rules.py

Various. (n.d.). *Linux Kernel Driver DataBase: CONFIG_USB_SERIAL_CP210X*. https://cateee.net/lkddb/web-lkddb/USB_SERIAL_CP210X.html

Various. (n.d.). *Linux Kernel Driver DataBase: CONFIG_USB_SERIAL_SIMPLE*. https://cateee.net/lkddb/web-lkddb/USB_SERIAL_SIMPLE.html

Various. (n.d.). *Linux Kernel Driver DataBase: CONFIG_USB_SERIAL_SUUNTO*. https://cateee.net/lkddb/web-lkddb/USB_SERIAL_SUUNTO.html

Various. (n.d.). *antpm-garmin-ant-downloader(1)*. Debian testing manpages. https://manpages.debian.org/testing/antpm/antpm-garmin-ant-downloader.1.en.html

Various. (n.d.). *USB1 vs USB2 ANT+ Sticks*. TrainerRoad Support. https://support.trainerroad.com/hc/en-us/articles/206007776-USB1-vs-USB2-ANT-Sticks

Various. (n.d.). *Dynastream Innovations ANTUSB-m Stick*. Linux Hardware Database. https://linux-hardware.org/?id=usb:0fcf-1009

bin.re. (n.d.). *Track Your Heartrate on Raspberry Pi with Ant+*. https://bin.re/blog/track-your-heartrate-on-raspberry-pi-with-ant/

golden-cheetah-users. (n.d.). *ant+ usb stick problems*. Google Groups. https://groups.google.com/g/golden-cheetah-users/c/umauL-_gbZE

Nordic Semiconductor. (2010, June 16). *Nordic Expands nRF24AP2 Family With Single Chip Solution For ANT USB Dongles*. SemiconductorOnline. https://www.semiconductoronline.com/doc/nordic-expands-nrf24ap2-family-with-single-0001

CooSpo. (n.d.). *CooSpo USB ANT Stick*. https://www.coospo.com/products/coospo-usb-ant-stick-ant-dongle-for-indoor-cycling-training-data-transmission-compatible-with-bkool-wahoo-tacx-bike-trainer-zwift-trainerroad-garmin-connect-cycleops-trainer-rouvy-tacx-vortex

Suunto. (n.d.). *Suunto Movestick Mini*. https://www.suunto.com/Products/PODs/Suunto-Movestick-Mini/
