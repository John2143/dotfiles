# Network Configs

MikroTik firmware and device configurations for the home network.

## Contents

- `router.rsc` — Full RouterOS config export from the main router (RB5009UPr+S+, 192.168.5.1)
- `core.rsc` — Config export from the core switch (CRS305-1G-4S+IN, 192.168.5.4)
- `upstairs.rsc` — Config export from the upstairs switch (CRS310-8G+2S+IN, 192.168.5.3)
- `office.rsc` — Config export from the office switch (CRS310-8G+2S+IN, 192.168.5.2)
- `upstairs-core.rsc` — Config export from the upstairs-core switch (CRS305-1G-4S+ r2, 192.168.5.5)

Each device also has a `.verbose.rsc` twin (`/export verbose` — includes protocol-mode,
bridge and default settings) for full-fidelity restore.

**`/export` omits sensitive values** — WireGuard private keys, passwords, etc. only appear
under `/export show-sensitive`. These files are safe to commit; never add `show-sensitive`.

Git tracks history — no need for dates in filenames.

## How to Update

```bash
# RouterOS writes CRLF over a terminal; strip it or every line looks changed.
export k=/run/user/$(id -u)/mikrotik-key
ssh -i "$k" admin@192.168.5.1 '/export' | tr -d '\r' > router.rsc
ssh -i "$k" admin@192.168.5.4 '/export' | tr -d '\r' > core.rsc
ssh -i "$k" admin@192.168.5.3 '/export' | tr -d '\r' > upstairs.rsc
ssh -i "$k" admin@192.168.5.2 '/export' | tr -d '\r' > office.rsc
ssh -i "$k" admin@192.168.5.5 '/export' | tr -d '\r' > upstairs-core.rsc

# ...and the .verbose.rsc twin of each ('/export verbose' - see SKILL.md for the full list)
./check-drift.sh --quiet   # must print OK
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
