# Clock sync spike (#102)

Verified against pinned deps: `container` ≥1.0.0, `containerization` 0.33.3.

## Problem

macOS sleep freezes guest microVM clocks. After wake, guests lag behind the host until the next periodic sync (upstream `TimeSyncer` interval: 30s). TLS and token validation can fail during the drift window.

## Upstream primitives

| Layer | API | Location |
|-------|-----|----------|
| Host dial | `ContainerClient.dial(id:port:)` | `container` `ContainerClient.swift` |
| Guest agent port | `Vminitd.port` = 1024 | `containerization` `Vminitd.swift` |
| Set guest clock | `Vminitd.setTime(sec:usec:)` → guest `settimeofday` | `containerization` `Vminitd.swift` |
| Periodic sync | `TimeSyncer` actor (30s loop) | `containerization` `TimeSyncer.swift` |
| VM resume | `timeSyncer.resume()` on `VZVirtualMachineInstance.resume()` | `containerization` `VZVirtualMachineInstance.swift` |

There is **no** `container sync` CLI route or `ContainerClient.syncTime` XPC route in container 1.0.0. Compose must `dial` + `setTime` directly.

## Host sandbox path (v1 — implemented)

```
ContainerClient.dial(containerID, Vminitd.port)
  → Vminitd(connection: FileHandle, group: EventLoopGroup)
  → gettimeofday on host
  → agent.setTime(sec, usec)
  → agent.close()
```

**NIO lifecycle:** one `MultiThreadedEventLoopGroup(numberOfThreads: 1)` per sync batch; `shutdownGracefully` after all containers in the batch complete. `ponytail:` upgrade path = pooled group across wakes.

**Discovery:** `ContainerListFilters(status: .running, labels: [project: "^.+$"]).withoutMachines()` — same project-label scoping as compose discovery.

## Machine path (v1 — partial)

| Target | Mechanism | v1 status |
|--------|-----------|-----------|
| Machine hypervisor | Host `dial(snapshot.containerId, Vminitd.port)` + `setTime` | **Implemented** when in-VM compose workloads exist |
| In-VM workload microVMs | Requires in-VM `ContainerClient.dial` per nested container | **Deferred** — no public in-VM dial from `MachineInVMRunner`; nested microVMs keep independent clocks |

Machines are included only when `MachineInVMRunner.listContainers` finds a **running** container with `com.docker.compose.project` label.

## Skew threshold

Manual acceptance: guest `date` within **5 seconds** of host `date` after sync. Constant: `ClockSync.skewThresholdSeconds`.

## Manual repro

```bash
container system start
container run -d --name clocktest docker.io/library/alpine:3.20 sleep 3600
container exec clocktest date
date
# Close lid ≥2 minutes, wake, re-run both date commands — guest lags until sync.
```

After compose clock sync: dates should match within 5s.

## Risks

- vsock `EBADF` on teardown ([containerization#678](https://github.com/apple/containerization/issues/678)): per-container catch; warn, do not crash CLI.
- Detached workloads with no running compose process: wake observer inactive; eager sync on next runtime command entry.
