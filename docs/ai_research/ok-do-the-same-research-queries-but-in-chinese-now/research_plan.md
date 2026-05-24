# Research Plan: ok-do-the-same-research-queries-but-in-chinese-now

## Primary Question
What are the best ANT+ USB dongles available on Chinese marketplaces (淘宝/Taobao, 京东/JD, 拼多多/Pinduoduo, 闲鱼/Xianyu, AliExpress, Banggood) for receiving heart rate data from a Garmin Fenix 7 Pro on a NixOS Linux PC, considering compatibility, reliability, availability, and price? Research should be conducted using Chinese-language sources (简体中文).

## Context
Same use case as previous English-language research: the user has a Garmin Fenix 7 Pro watch broadcasting ANT+ heart rate during activities. They are on a NixOS Linux PC (kernel 6.18.28, x86_64) with an Intel Bluetooth 5.2 adapter. No ANT+ dongle is currently plugged in. The goal is to receive ANT+ heart rate data for livestream overlay (OBS). The `openant` Python library (available in nixpkgs as `python3Packages.openant`) will be used as the software receiver. The dongle must present USB IDs 0fcf:1004, 0fcf:1008, or 0fcf:1009 for openant compatibility. Use Chinese-language sources (简体中文) for this research — search in Chinese, read Chinese product pages, Chinese tech forums, Chinese reviews.

## Sub-Topics

### Sub-Topic 1: Compatible ANT+ USB dongle models available in China (中国市场可用的ANT+ USB接收器型号)
- **Slug**: compatible-dongle-models-cn
- **Perspective**: none
- **Report path**: reports/compatible-dongle-models-cn_report.md

### Sub-Topic 2: Purchase options, pricing on Chinese platforms (中国电商平台购买渠道与价格)
- **Slug**: purchase-options-pricing-cn
- **Perspective**: none
- **Report path**: reports/purchase-options-pricing-cn_report.md

### Sub-Topic 3: Performance, reliability, and practical setup (性能、可靠性与实际配置)
- **Slug**: performance-reliability-cn
- **Perspective**: none
- **Report path**: reports/performance-reliability-cn_report.md
