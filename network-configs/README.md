# Network Configs

MikroTik firmware and device configurations for the home network.

## Contents

- `router.rsc` — Full RouterOS config export from the main router (RB5009UPr+S+, 192.168.1.1)
- `core.rsc` — Config export from the core switch (CRS305-1G-4S+IN, 192.168.5.4)
- `upstairs.rsc` — Config export from the upstairs switch (CRS310-8G+2S+IN, 192.168.5.3)
- `office.rsc` — Config export from the office switch (CRS310-8G+2S+IN, 192.168.5.2)

Git tracks history — no need for dates in filenames.

## How to Update

```bash
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 '/export' > router.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.4 '/export' > core.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.3 '/export' > upstairs.rsc
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.5.2 '/export' > office.rsc
```

## Restoring

**Destructive — overwrites the entire running config. Reboot recommended after.**

```bash
# Via SSH pipe (streams commands directly):
ssh -i /run/user/$(id -u)/mikrotik-key admin@192.168.1.1 < router.rsc

# Or via RouterOS flash (upload file first):
mikrotik-connect r '/import file=router.rsc'
mikrotik-connect r '/system reboot'
```

**Never import a switch config onto the router or vice versa** — the interface names and hardware topology are different.
