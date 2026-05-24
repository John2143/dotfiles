# Research Plan: find-the-best-way-to-check-our-unifi-status-by-cli-i-can-use-bot

## Primary Question
What is the best method to query UniFi wireless access point status from the command line, given a UniFi Network Application 10.0.162 controller running in k3s with only APs (no UniFi switches or routers), and what is the correct authentication mechanism?

## Context
I just want to do cli unifi queries on my wireless access points, but I have no unifi switches or routers.

## Sub-Topics

### Sub-Topic 1: UniFi REST API Authentication (v10.x)
- **Slug**: unifi-api-authentication
- **Perspective**: none
- **Report path**: reports/unifi-api-authentication_report.md

### Sub-Topic 2: kubectl-Based UniFi Access Patterns
- **Slug**: kubectl-unifi-access
- **Perspective**: none
- **Report path**: reports/kubectl-unifi-access_report.md

### Sub-Topic 3: UniFi API Endpoints for AP Data
- **Slug**: unifi-ap-api-endpoints
- **Perspective**: none
- **Report path**: reports/unifi-ap-api-endpoints_report.md

### Sub-Topic 4: Existing CLI Tools and Wrappers
- **Slug**: unifi-cli-tools
- **Perspective**: none
- **Report path**: reports/unifi-cli-tools_report.md

### Sub-Topic 5: Integration Patterns (NixOS + fish + agenix)
- **Slug**: integration-patterns
- **Perspective**: none
- **Report path**: reports/integration-patterns_report.md
