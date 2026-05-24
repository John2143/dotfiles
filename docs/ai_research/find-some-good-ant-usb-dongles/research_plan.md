# Research Plan: find-some-good-ant-usb-dongles

## Primary Question
What are the best ANT+ USB dongles for receiving heart rate data from a Garmin Fenix 7 Pro on a Linux (NixOS) PC, considering compatibility, reliability, availability, and price?

## Context
The user has a Garmin Fenix 7 Pro watch broadcasting ANT+ heart rate during activities. They are on a NixOS Linux PC (kernel 6.18.28, x86_64) with an Intel Bluetooth 5.2 adapter. No ANT+ dongle is currently plugged in. The goal is to receive ANT+ heart rate data for livestream overlay (OBS). The `openant` Python library (available in nixpkgs as `python3Packages.openant`) will be used as the software receiver. The dongle must be compatible with Linux's cp210x kernel module (USB IDs 0fcf:1004, 0fcf:1008, 0fcf:1009).

## Sub-Topics

### Sub-Topic 1: Compatible ANT+ USB dongle models for Linux
- **Slug**: compatible-dongle-models
- **Perspective**: none
- **Report path**: reports/compatible-dongle-models_report.md

### Sub-Topic 2: Purchase options, pricing, and availability
- **Slug**: purchase-options-pricing
- **Perspective**: none
- **Report path**: reports/purchase-options-pricing_report.md

### Sub-Topic 3: Performance, reliability, and practical setup considerations
- **Slug**: performance-reliability
- **Perspective**: none
- **Report path**: reports/performance-reliability_report.md
