# Compose plugin entitlements audit

Generated for issue #91. Scope: `compose` release binary only (not the `container` daemon).

## v1 release posture

Release builds ship **capability-only** entitlements embedded via ad-hoc codesign. **`com.apple.security.app-sandbox` is absent** — the process is not App Sandbox–isolated. Capability keys (`hypervisor`, `network.client`) declare intent for future Developer ID signing; they do not restrict the process until `app-sandbox` is enabled.

See repo-root [`entitlements.plist`](../entitlements.plist) (release) vs [`entitlements.sandbox.plist`](../entitlements.sandbox.plist) (opt-in spike only).

## Entitlement matrix

| Subsystem | Compose direct? | Evidence | v1 entitlement | Delegated to `container`? |
|-----------|-----------------|----------|----------------|---------------------------|
| Container lifecycle (host) | API call | `ComposeContainerGateway.swift:39-153` — `ContainerClient` list/get/run/kill/delete | `network.client` (API transport) | Runtime execution, port publish |
| Hypervisor / VMs | API call | Same gateway + `DeployResourceLimitsPlanning.swift:6-7` (Virtualization.framework) | `hypervisor` | Kernel/image store inside daemon |
| Image build (`build:`) | API call | `BuildRunner.swift:141` — `Application.BuildCommand` | Same as container API | Build runs in daemon / in-VM runner |
| Port mapping | Planner only | Maps to `container run -p` args; no listen in compose | **None** — omit `network.server` | `container run` publishes ports |
| Staging (`configs`/`secrets`) | File I/O | `ComposeFileStaging.swift:7-10` — `~/.config/container-compose/` | N/A (unsandboxed v1) | — |
| Compose file / bind mounts | File I/O | `BindMountPathResolver.swift:9-30`, `ComposeFileResolution.swift:34-48` | N/A | — |
| `compose watch` | FSEvents + copy | `FileWatch.swift:53-68`, `ContainerFileSync.swift` | N/A | `ContainerClient.copyIn` for sync |
| Host DNS | `/etc/hosts` + admin | `HostsFileEditor+Apply.swift:17-75`, `HostsFileEditor.swift:5` | N/A | — |
| `compose doctor` | Subprocess | `DoctorChecks+Subprocess.swift:31-59` — spawns `container` on PATH | N/A | Checks CLI the user already runs |
| Machine mode | API + in-VM CLI | `MachineInVMRunner.swift:60` — `ContainerClient.createProcess` | Same as host API | In-VM `container` binary |

### v1 release allowlist

| Key | Include in `entitlements.plist`? |
|-----|----------------------------------|
| `com.apple.security.hypervisor` | Yes |
| `com.apple.security.network.client` | Yes |
| `com.apple.security.app-sandbox` | **No** (deferred) |
| `com.apple.security.network.server` | **No** — compose never binds/listens |
| `com.apple.security.files.user-selected.read-write` | **No** — powerbox primitive; useless for headless CLI paths |

## Sandbox blocker register

Enabling `app-sandbox` without mitigations breaks these flows:

| ID | Blocker | Files | Commands | Mitigation status |
|----|---------|-------|----------|-------------------|
| B1 | Project-relative bind mounts outside container | `BindMountPathResolver.swift`, `BindMountPurge.swift` | `up`, `down -v`, `cp` | **None** — needs broad file RW or architectural change |
| B2 | FSEvents on arbitrary host directories | `FileWatch.swift:53-68` | `watch` | **None** — needs read access to watch roots |
| B3 | Read/write `/etc/hosts` | `HostsFileEditor+Apply.swift:17-100` | `up --host-dns`, `down` | **None** — system path; admin `osascript` also blocked |
| B4 | Spawn `/usr/bin/container` subprocess | `DoctorChecks+Subprocess.swift:31-59` | `doctor` | **None** — sandbox restricts child process policy |
| B5 | Compose file discovery from CWD / `-f` | `ComposeFileResolution.swift:34-48` | all commands | **None** — not covered by user-selected entitlement |

`com.apple.security.files.user-selected.read-write` does **not** resolve B1/B2/B5 — it only grants paths chosen via NSOpenPanel/powerbox, not CLI arguments.

## Ad-hoc signing + App Sandbox (empirical spike)

Tested on macOS arm64 (local dev host, 2026-06):

| Artifact | Signing | `compose --help` |
|----------|---------|------------------|
| Capability-only (`hypervisor` + `network.client`, no `app-sandbox`) | `codesign -s - --entitlements entitlements.plist` | **Pass** (exit 0) |
| Sandbox candidate (`app-sandbox` + capabilities) | Same ad-hoc identity | **Fail** (exit 133, no output) |

**Conclusion:** Ad-hoc signing can embed entitlements, but turning on `app-sandbox` for this bare CLI plugin is not viable without additional file-access entitlements and likely **Developer ID + notarized** signing. Defer full sandbox to a follow-up issue; use [`entitlements.sandbox.plist`](../entitlements.sandbox.plist) only with [`scripts/smoke-sandbox-entitlements.sh`](../scripts/smoke-sandbox-entitlements.sh).

## Smoke matrix (capability-only release binary)

| Scenario | Expected v1 | Notes |
|----------|-------------|-------|
| `codesign -d --entitlements :-` shows hypervisor + network.client | Pass | CI gate via `verify-codesign.sh` |
| `compose --help` | Pass | No sandbox isolation |
| `compose up` / `down` (minimal fixture) | Pass* | *Requires local `container` runtime |
| `compose watch` | Pass* | Unsandboxed file access unchanged |
| `up --host-dns` | Pass* | Admin prompt path unchanged |

Sandbox plist matrix (opt-in script only): expect **fail** on B1–B5 until mitigations exist.

## Future sandbox plist candidate

[`entitlements.sandbox.plist`](../entitlements.sandbox.plist) documents keys for spike testing only. **Not used by `build-release.sh` in v1.** Any production sandbox profile requires resolved blockers B1–B5 and a Developer ID signing pipeline (out of scope for #91).
