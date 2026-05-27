# Network Configs

MikroTik firmware and device configurations for the home network.

## Contents

- `mikrotik-export-*.rsc` — Full RouterOS config exports from the main router (RB5009UPr+S+)
- `upstairs-switch-export-*.rsc` — Config exports from the upstairs switch (CRS310-8G+2S+IN)
- `downstairs-switch-export-*.rsc` — Config exports from the downstairs switch (CRS310-8G+2S+IN)

## How to Update

### Full MikroTik export
```bash
mikrotik-connect r '/export file=network-configs/mikrotik-export-$(date +%Y-%m-%d)'
mikrotik-connect r '/file download network-configs/mikrotik-export-$(date +%Y-%m-%d).rsc'
```

### Switch exports
```bash
mikrotik-connect u '/export file=network-configs/upstairs-switch-export-$(date +%Y-%m-%d)'
mikrotik-connect d '/export file=network-configs/downstairs-switch-export-$(date +%Y-%m-%d)'
mikrotik-connect u '/file download ...'
mikrotik-connect d '/file download ...'
```

## Restoring

To restore from a known-good export:
```bash
mikrotik-connect r '/import file=network-configs/mikrotik-export-<date>.rsc'
```

This overwrites the current config with the saved version. Reboot the device after import.
