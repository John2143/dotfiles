# Beyla eBPF Instrumentation — Status, Incident, Re-enable

> **STATUS: DISABLED since 2026-08-16** — Beyla's `obi_protocol_tcp` eBPF program
> kernel-panicked `big` (repeatedly). Re-enable only after the root cause is
> understood (see [Re-enable checklist](#re-enable-checklist)).

---

## What it is

[Beyla](https://github.com/grafana/beyla) (now OpenTelemetry eBPF
Instrumentation, "OBI", after CNCF donation) is an eBPF auto-instrumentation
agent: it watches process/kernel events and emits OTLP **traces + RED metrics**
for services that don't self-instrument. It needs no code changes — it attaches
uprobes/kprobes and TC programs at runtime.

- **Deploy:** ArgoCD Application `apps/beyla.yaml` → Grafana Helm chart `beyla`
  `1.16.10`, app image `docker.io/grafana/beyla:3.25.0`
- **Namespace:** `observability` (DaemonSet, privileged, host networking)
- **Export:** OTLP → `alloy.observability.svc:4318` (traces + metrics); Alloy
  forwards metrics to Mimir, traces to Tempo
- **Node selection:** `nodeSelector: beyla.enabled: "true"` — label exists on
  **arch** (control-plane/etcd!) and **big** (worker) only
- **Scope filter:** excludes `kube*`, `*jaeger-agent*`, `*prometheus*`,
  `*promtail*`, `*grafana-agent*` owners (per-service tracing beats eBPF)

Note: `argo/docs/2026-08-10-auto-instrumentation.md` claims "4/6 nodes
(arch, closet, nas, big)". **That was never true** — the label only ever existed
on arch + big, so the DaemonSet ran exactly 2 pods.

---

## The incident (2026-08-12 → 08-16)

### Timeline

| When (node clock) | What |
|---|---|
| 08-12 → 08-14 | `big` rebooted **5× in 48h** (clean shutdowns, 1–2 min power gaps). Each reboot logged as `reboot requested from client` from an interactive login session — i.e. manual recoveries, not scheduled. |
| 08-14 ~19:04–19:30 | Cluster churn: `arch` and `closet` flapped NodeNotReady→Ready, `big` went down at 19:26 and rebooted 19:29. Fallout: teamspeak pod evicted, Longhorn volume stuck (`Multi-Attach error` ×7), mass `0/6 nodes available` reschedule storm. |
| 08-15 20:35 | `big` boots (current boot). |
| 08-16 ~00:33 | **Kernel panic watched live** on `big`'s console: `RIP: 0010:bpf_prog_df6215dd4d76f052_obi_protocol_tcp+0x5b04/0x6348` |
| 08-16 ~00:55 | **Beyla disabled** — `apps/beyla.yaml` nodeSelector flipped `"true"` → `"false"`, commit `5b1ad44`, pushed. App-of-apps auto-synced within ~3 min → DaemonSet scaled to 0. |
| 08-17 14:47 | `big` uptime **1d18h, zero panics** since the disable. |

### The panic signature

```
RIP: 0010:bpf_prog_df6215dd4d76f052_obi_protocol_tcp+0x5b04/0x6348
```

- `bpf_prog_…` prefix = a **JIT-compiled BPF program**, not userspace
- `obi_protocol_tcp` = Beyla's TCP-connection observer (network metrics/RTT +
  payload-based protocol detection)
- `+0x5b04/0x6348` = fault deep inside the running program

A verifier-approved BPF program faulting at runtime almost always means a
**kernel regression** (6.18.44 is bleeding-edge; Beyla uses `bpf_loop` for TCP
payload, TC/TCX attach, etc.), not a Beyla logic bug — a pure-Beyla bug would
crash on other kernels too. The `big` console shows panics because the node
registered `drm panic` display planes (bochs-drm).

### Why it looked like "clean shutdowns"

A hard panic never reaches journald — `big`'s previous-boot kernel log just
*stops* (last entry 17h before the crash, only cni0 noise). The panic text goes
to the VGA console only. So each crash looked like a planned reboot in the
journal, plus the user's manual `reboot` to recover.

### Evidence the fix worked

- Beyla processes on arch + big: **zombies** (`Zsl` = dead, no threads, no fds)
- `/sys/fs/bpf` **empty** on both nodes — no pinned BPF programs, so
  `obi_protocol_tcp` is unloaded from the kernel
- DaemonSet `DESIRED 0`, ArgoCD app `Synced/Healthy`
- `big`: no reboot and no panic since 08-16 00:33 (vs. 5 reboots/2 days before)

This is strong but not formal proof — only one panic signature was ever
captured.

---

## Re-enable checklist

Before trying again:

1. **Check upstream first** — no public issue matches this signature as of
   2026-08-17. File one at `grafana/beyla` or
   `open-telemetry/opentelemetry-ebpf-instrumentation` (see
   [Evidence for upstream](#evidence-for-upstream)).
2. **Decide the kernel/Beyla combo** — either pin a kernel known to work with
   Beyla 3.25.0, or upgrade Beyla once a fix lands. Do not blind-re-enable on
   the current 6.18.44.
3. **Consider workers only** — Beyla ran on `arch`, an etcd/control-plane
   member. A panic there risks quorum. Prefer a worker-only label
   (`beyla.enabled` on big/office, not arch) next time.
4. Flip the selector:
   ```yaml
   # argo/apps/beyla.yaml
   nodeSelector:
     beyla.enabled: "true"   # was "false"
   ```
5. `git add apps/beyla.yaml && git commit && git push` — app-of-apps auto-syncs
   (~3 min reconcile) → child CR updates → DaemonSet schedules pods.
6. Verify + watch:
   ```bash
   ssh closet.local 'kubectl get pods -n observability -l app.kubernetes.io/name=beyla -o wide'   # expect 2 Running (arch, big)
   ssh closet.local 'kubectl get ds -n observability beyla'
   # then watch big for panics over the next days:
   ssh big.local 'journalctl -b -k | rg -i "panic|oops|BUG:" '
   ```

**Re-disable** (emergency): flip the nodeSelector back to `"false"`, commit,
push, wait ~3 min. The DaemonSet scales to 0; pods terminate (30s grace). If a
node already panicked, it recovers on reboot.

---

## Evidence for upstream

What to capture when the next panic (or one from history) hits:

- **Full panic text** — the fault line *above* RIP (`BUG: kernel NULL pointer
  dereference` / `general protection fault` / `unable to handle page fault`),
  faulting address, register dump, call trace, and the `Code:` hex bytes. A
  photo of the console is fine.
- **pstore** (automatic RAM capture, survives reboot):
  `sudo ls /sys/fs/pstore && sudo cat /sys/fs/pstore/*`
  (needs root; `pstore` is mounted but not world-readable).
- **Determinism:** if the RIP/offset is *identical* every crash → software
  (kernel/Beyla). If it *varies* → suspect hardware (RAM/CPU) instead.
- Environment: kernel `6.18.44` (NixOS, x86_64), Beyla `3.25.0`, k3s `1.35.7`.

---

## Leftover state (kept intentionally)

| Resource | Where | Why kept |
|---|---|---|
| `configmap/beyla`, `serviceaccount/beyla`, `clusterrole/beyla`, `clusterrolebinding/beyla` | `observability` ns | Inert; re-enable is a one-line flip. Purge only by deleting `apps/beyla.yaml` from git (app-of-apps prune + finalizer). |
| `beyla.enabled: "true"` node labels | arch, big | Needed for re-enable |

Observability impact of the disable: only Beyla's extra traces/RED metrics are
gone. The Alloy → Mimir/Loki/Tempo pipeline is untouched; services that emit
their own OTLP (traefik, temporal, …) still have traces.

---

## Related

- Original setup doc: `argo/docs/2026-08-10-auto-instrumentation.md`
  (**stale** — still says "expect 4 Running"; update before re-enabling)
- Alloy observability stack: skill notes in the argo-engineer skill
  (`observability` ns telemetry layout)
