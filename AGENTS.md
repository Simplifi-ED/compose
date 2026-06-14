# AGENTS.md — AI Agent Steering Directive

This document defines the strict architectural rules, boundaries, and non-negotiables for the native `container compose` plugin. As an AI Agent, you must read, parse, and strictly adhere to this steering document before modifying any files.

---

## 1. Project Scope & Boundary (Option B)

You are building a **Minimal Real Compose Plugin**—NOT a generic orchestration platform [1].

### **In Scope (To Code):**

- Parsing a standard, single-file `docker-compose.yml` [1].
- Multi-file compose: `-f` merge, auto-discovery (`compose.yaml` + override), and `COMPOSE_FILE` [1].
- Project naming: `-p`, `COMPOSE_PROJECT_NAME`, compose `name:`, first-file parent directory [1].
- Instantiating and mapping configuration directly into Apple's programmatic `ContainerCommands` API [1].
- Basic container lifecycles: Starting (via `ContainerRun`) and Stopping (via `ContainerStop`) [1].
- `compose pause` / `compose unpause`: suspend/resume all project containers in place (non-destructive); `-f`, `-p`, `--profile`, `COMPOSE_PROFILES`, `--parallel`, `--dry-run`, `--machine` (workload containers in-VM, not the hypervisor VM); profile scoping same as `ps`/`down`; parallel batch via `WaveExecutionPolicy`; host sandbox uses `ContainerClient.kill` with `SIGSTOP`/`SIGCONT` via `ComposeContainerGateway`; machine mode uses in-VM `container kill --signal SIGSTOP|SIGCONT` until upstream ships native pause/unpause API and `RuntimeStatus.paused` [1].
- Attributes to map: `image`, `command`, `environment`, standard host-to-container `ports`, short-syntax bind-mount `volumes` (`host:container`, `host:container:ro`, comma options such as `host:container:ro,z`), short-form `depends_on` (list of service names), long-form `depends_on` with `condition: service_started` / `service_healthy` / `service_completed_successfully`, `healthcheck` (`test`, `interval`, `timeout`, `retries`, `start_period`), `init`, `profiles`, `deploy.replicas`, and `deploy.resources.limits` (`cpus`, `memory`) [1].
- Profile activation: `--profile` (repeatable, OR) merged with process `COMPOSE_PROFILES` (comma-separated); applies on `up`, `down`, `pause`, `unpause`, `ps`, `logs`, `top`, `config`, `watch` [1].
- Health-gated startup: between topological waves, wait for `service_started` (runtime `running`), `service_healthy` (compose-side probe via `createProcess` — container 1.0.0 has no native per-container health on `ContainerSnapshot`), or `service_completed_successfully` (init process exit code 0 via `ContainerClient.bootstrap` + `ClientProcess.wait`; host sandbox only — errors on `--machine`) [1].
- Service scaling: `deploy.replicas` and `up --scale SERVICE=COUNT` (CLI wins) with uniform `{project}_{service}_{index}` container naming [1].
- Dependency-aware startup ordering: topological sort with parallel waves via structured concurrency [1].
- Partial-`up` rollback: tear down containers from successful waves when a later wave fails [1].
- Reverse-topological `down` when a compose file is available; parallel `down` fallback for `-p`-only [1].
- Opt-in `--remove-orphans` on `up`/`down`: profile-aware orphan detection and removal (project label scoped) [1].
- Root-level `configs:` / `secrets:` with local `file:` sources (`external: false` only); service-level short and long refs; read-only staged mounts at `/run/configs/` and `/run/secrets/` via `-v …:ro` [1].
- `down -v` / `--volumes`: Phase 1 bind-mount purge for project-relative host paths only; symlink-safe allowlist [1].
- Staged config/secret files under `~/.config/container-compose/<project>/` (`0600` secrets, `0644` configs); removed on container teardown and `down` [1].
- Service-level `develop.watch` (`sync`, `sync+restart`); macOS FSEvents file sync into running containers via `compose watch` and `ContainerClient.copyIn`; path sandbox matches bind-mount rules; sync applies to all running replicas [1].
- Service `build:` (short context path or object with `context`, `dockerfile`, `args`, `target`); image build during `up`/`run` init via `Application.BuildCommand` before startup waves; default tag `{project}_{service}` when `image` omitted; explicit `image` names build output when both set; context path sandbox matches bind-mount rules; build args never logged; no registry push [1].
- `compose cp` (`SERVICE:/path` ↔ host) via `ContainerClient.copyIn`/`copyOut`; project/service label scoping same as `exec`; default single replica or `ambiguousService`; `--index N` selects `{project}_{service}_{N}`; `--all` copies into all running replicas (host→container only); relative host paths CWD-sandboxed; absolute host paths allowed with stderr warning; container paths absolute with `..` rejected [1].
- `--machine <name>` on `up`/`down`/`pause`/`unpause`/`exec`/`ps`/`logs`/`cp`: validate machine via `MachineClient.inspect` (lazy boot); `ensureBooted()` only before mutating `up`/`pause`/`unpause` workloads; scope discovery with `com.docker.compose.machine` label; in-VM `container` CLI via `MachineInVMRunner` for list/run/stop/exec/cp/logs/build; host sandbox discovery excludes machine-labeled containers; `ps`/`logs` exit gracefully when machine stopped; execution banner on stderr; dry-run prefixes `machine=<name>` without booting; `watch`/`run`/`top`/`config` error on `--machine` [1].
- Minimal compose `networks:`: root declarations (empty/no-option form; `external: false` only) and service memberships (short list + empty-map long form); project-scoped network create (`{project}_{network}`) before startup waves and removal on `down`; attach via `container run --network`; DNS resolves **container names** (`{project}_{service}_{index}`), not Docker-style service shorthand; custom networks require macOS 26+ [1].
- Minimal compose `volumes:`: root declarations (empty/no-option form; `external: false` only) and service short-syntax named mounts (`mydata:/app/data`); project-scoped volume create (`{project}_{volume}`) via `ClientVolume` before startup waves; mount via `container run -v`; removal on `down -v` only (label-scoped); bind-mount `down -v` behavior unchanged [1].

### **Out of Scope (DO NOT CODE):**

- Network drivers, overlay networks, IPAM plugins, network `aliases`, static `ipv4_address`/`ipv6_address`, `priority`, `network_mode`, `external: true` networks, cross-project network sharing, or modifying macOS `pf`/system-wide routing [1].
- Volume drivers, NFS/cloud storage, `external: true` volumes, cross-project volume sharing [1].
- Long-form bind-mount `read_only: true`, explicit `:rw` volume suffix [1].
- External secret/config managers (`external: true`, Vault, cloud SM) [1].
- `depends_on` condition restart policies and HTTP health checks beyond exec/CMD probes [1].
- Cross-arch `build.platform` without native translation; multi-stage cache export to remote registries; `develop.watch` `rebuild` action [1].

---

## 2. Hard Rules & Dev Gates (Non-Negotiable)

1. **Verify via Compiler, Not Guesswork:**
   Apple's `ContainerCommands` API is strictly typed and subject to change. Do NOT assume its property or method signatures. You must run `swift build` after every block of code you write. If it doesn't compile, it is wrong. No "hallucinated APIs".

2. **Build & Format Gate:**
   Your code must build without compilation errors or linter warnings.

   ```bash
   swift build -c release
   ```

3. **No Hardcoded Mocks:**
   Do not introduce mock runtimes, hardcoded system states, or static stub YAML files inside the production codebase. The plugin must talk directly to the real system loop.

---

## 3. LLM Smell Neutralizer (What NOT to Code)

To prevent code-bloat, code-rot, and unmaintainable abstractions, you must obey these code style rules:

- **No "Manager" or "Factory" Classes:**
  Do not write abstract orchestration layers (e.g., `ComposeManager`, `ContainerCommandFactory`, `LifecycleCoordinator`). Keep the architecture flat. If you need to map a YAML service to a command, write a direct, stateless mapping function or a lightweight data structure.
- **No Speculative Protocols:**
  Do not write protocols with a single implementation (e.g., `protocol ComposeParsing`, `protocol CommandExecuting`). Use concrete, straightforward `structs` and `final classes`.
- **No Unnecessary Generics:**
  Keep type signatures concrete. Avoid generic wrappers.
- **No Useless Abstraction Layers:**
  Do not wrap Apple's existing libraries inside custom wrappers just to "simplify" things. Call `ContainerCommands` directly.

---

## 4. Code Preservation (What NOT to Break)

- **Do Not Touch Core Apple Files:**
  Do not touch any files in the parent `apple/container` repository or modify their internal targets. All of your implementation must reside strictly inside your isolated plugin package target (`Sources/` of your plugin package).
- **Do Not Delete Comments:**
  Do not delete existing developer comments, documentation headers, or inline parameter descriptions when refactoring.
- **Do Not Rewrite Working Code:**
  If a parser block or CLI command works, do not rewrite it to use a different styling preference (e.g., changing synchronous execution patterns to async/await wrappers unless explicitly instructed).

---

## 5. Development Loop & Verification

Before finalizing any task, run this exact sequence to ensure the plugin is healthy and discovered natively:

```bash
# 1. Build and verify target compiles
make build
# or: swift build -c release

# 2. Package into target directory structure
make dist
# or: ./scripts/package.sh

# 3. Simulate installation to libexec
INSTALL_ROOT="$(dirname "$(dirname "$(command -v container)")")"
export TARGET_DIR="${INSTALL_ROOT}/libexec/container-plugins/compose"
# On this host (/usr/local install): /usr/local/libexec/container-plugins/compose
# Requires sudo when INSTALL_ROOT is /usr/local
mkdir -p "$TARGET_DIR" || sudo mkdir -p "$TARGET_DIR"
cp -R dist/compose/* "$TARGET_DIR/" || sudo cp -R dist/compose/* "$TARGET_DIR/"

# 4. Verify discovery
container --help | grep -A 2 "PLUGINS:"
```

The output of the discovery command **must** show the `compose` plugin. If it does not appear, your `config.toml` structure is incorrect or placed in the wrong path. Stop and debug.

---

## 6. Machine-Mode Hypervisor Corrections (`--machine`)

You must actively resolve the three core gaps in the VM hypervisor boundary instead of leaving them as documented constraints:

1. **In-VM Image Builds:**
   - Do not run `BuildRunner` on the macOS host when `--machine <name>` is set [2.1].
   - Run `container build` inside the machine via `MachineInVMRunner` so image construction uses the VM image store [2.1].

2. **Home-Relative File Staging:**
   - Refactor `ComposeFileStaging.swift` to use `FileManager.default.homeDirectoryForCurrentUser` instead of `NSTemporaryDirectory()` [2.2].
   - Ensure configs and secrets are staged at `~/.config/container-compose/...` so they fall within the automatically mounted `$HOME` directory inside the VM [2.2].

3. **Lazy VM Booting:**
   - Remove aggressive `MachineClient.boot` calls from eager context initialization [2.3].
   - Prevent `ps`, `logs`, and `config` / `--dry-run` commands from booting a stopped VM [2.3]. If the target machine is stopped, `ps`/`logs` must exit gracefully with a "Machine stopped" message [2.3].
   - Call `ensureBooted()` lazily only inside `Up` immediately before dispatching container executions (including in-VM builds) [2.3].

---

## Learned User Preferences

- v1 scope is minimal real compose (parse `docker-compose.yml`, start/stop services), not full Docker Compose parity.
- Load project skills under `.agents/skills/` (especially `swift-concurrency`, `swift-testing-pro`, `writing-for-interfaces`, `swift-format-style`, `ios-code-audit`) when implementing features.
- Prefer structured-concurrency parallelism (`withTaskGroup`) for multi-service orchestration.
- Develop on Command Line Tools only (no full Xcode.app); use `mint install realm/SwiftLint` instead of `brew install swiftlint`.
- Deliver merge-ready PRs with polish included—not deferred follow-up cleanup.
- Run Thermos parallel review (`thermo-nuclear-review` + code-quality subagents) before declaring feature work complete; fix all findings (major, minor, deferrable).
- Run Thermos review on feature specs before filing GitHub issues.
- CI/release automation targets this compose plugin repo only—not upstream `apple/container`; keep `.github/workflows/ci.yml` as a maintainer-run quality gate (`workflow_dispatch`), not per-commit, to conserve macOS runner minutes; draft pre-release changelogs as gitignored markdown under `dist/` (e.g. `dist/v0.0.1-rc2.md`) for `gh release --notes-file`; Homebrew formula bumps belong only in [`Simplifi-ED/homebrew-compose`](https://github.com/Simplifi-ED/homebrew-compose)—never commit `Formula/` or tap mirror files in the compose repo (`release.yml` `bump-homebrew-formula` checks out the tap and pushes there).
- First public release follows semver starting at v0.0.1, not v1.0.0.
- Keep new source files ≤250 lines; split modules when exceeded.
- Reuse upstream ContainerCommands APIs (`ContainerLogs`, `ContainerExec`, `AsyncSignalHandler`) instead of reimplementing.
- In test fixtures, pin container images to version tags—not `:latest` or sha digests.

## Learned Workspace Facts

- `container` CLI 1.0.0 at `/usr/local` for local dev; plugin at `{INSTALL_ROOT}/libexec/container-plugins/compose` via `scripts/install.sh` (`sudo` for `/usr/local`). `scripts/install.sh` resolves `INSTALL_ROOT` from the active `container` on PATH: Homebrew `opt/container` only when that binary is the Homebrew one; otherwise `dirname(dirname(container))` (PKG `/usr/local`). Override with `CONTAINER_INSTALL_ROOT`. Homebrew `container` formula sets `CONTAINER_INSTALL_ROOT` to `opt_prefix`, so plugins belong under `opt/container/libexec/container-plugins/compose`—not `HOMEBREW_PREFIX/libexec/...` from `command -v`. Distribute compose via `brew install simplifi-ed/compose/container-compose` (may require `brew trust simplifi-ed/compose`); link step fails if plugin path exists as a non-symlink directory. macOS 26+ required for container machines (`--machine`). Container 1.0.0 has `MachineAPIClient` but no machine-scoped `ContainerClient`—machine runtime I/O uses in-VM `MachineInVMRunner`. Run `container system start` before plugin discovery; host Linux kernel must be configured (`container system kernel set`) before `container run` or `compose up` succeed.
- Package targets: `ComposeCore`, `compose`, `compose-verify`; on CLT use `swift run -c release compose-verify` (not `swift test`) and `scripts/lint.sh` with `SWIFTLINT_DISABLE_SOURCEKIT=1`. `compose-verify` sync bridge: `blockingAwait` runs async work via `Task.detached`; `StandardStreamCapture.captureStandardError` restores stderr before reading the pipe (avoids deadlock)—use for tests that intentionally emit production stderr. CI (`ci.yml`) is manual-only via `workflow_dispatch` with opt-in `run_smoke`; `release.yml` runs lint/build/test on version tags (auto-generated notes; does not auto-mark `-rc` pre-release; bumps Homebrew formula). Both install SwiftLint via `scripts/install-swiftlint.sh` before `make lint`.
- `compose down` reverse-topological with compose file present; parallel fallback for explicit `-p` only (not `COMPOSE_PROJECT_NAME` or compose `name:`). `--remove-orphans` on `up`/`down` is opt-in; `OrphanRemoval` handles profile-aware detection. On `up`, discovery/removal failures warn and startup continues (`UpOrphanRemoval.removeBeforeStartupBestEffort`). `down -v` purges project-relative bind-mount paths (`BindMountPurge`) and project-labeled named volumes (`VolumeRunner`); absolute bind mounts skipped. Short-syntax bind mounts support `:ro`, `:z`, and comma options (`:ro,z`) via `VolumeSpec`/`ComposeBindingKeys.parseVolumeSpec`; `:z` is parse-only passthrough to `container run -v` (no SELinux on macOS). Live checks: `scripts/smoke-volume-mounts.sh` / `make smoke-volumes`.
- Default compose discovery: `compose.yaml` → … → `docker-compose.yml` + paired `*.override.*`; `COMPOSE_FILE` when no `-f`. Project name: `-p` → `COMPOSE_PROJECT_NAME` → merged `name:` → first-file parent dir. Explicit missing `-f` paths throw; only absent default discovery yields nil so `-p`-only `down`/`ps` can proceed.
- Multi-file merge and `include:`: unique-key ports/volumes; env list by var name; `depends_on` keyed merge (override wins per service); `healthcheck` override wins. Relative bind-mount paths resolve against the compose file directory, not shell CWD. `include:` via `ComposeIncludeResolver`—paths relative to including file; parent services win naming (duplicate service name errors—unlike `-f` merge); recursive includes with cycle rejection; per-include `env_file` and `project_directory`.
- Per-file substitution before YAML parse: shell environment overrides `.env` beside each compose file; supports `${VAR}`, `${VAR:-default}`, `${VAR-default}`, and `$$` escapes; unresolved `${VAR}` errors; YAML anchors/aliases resolved by Yams during decode.
- CLI subcommands: `up`, `down`, `ps`, `logs`, `top`, `exec`, `cp`, `run`, `watch`, `config`, `save`, `load`; shared flags via `@OptionGroup` `ParsableArguments` structs (`ProjectOptions`, `ProfileOptions`, …) with synthesized `Codable`—delegate to pure resolution helpers, not `ResolutionCache`/custom `init(from:)` unless encoding is required; `up`/`down` accept `--progress auto|plain|none`; `up --attach` multiplexes logs after detached start; `-f`/`-p` on subcommands, not `compose` root; service `init: true` maps to `container run --init` via `ServiceRunMapping` (`useInit` tri-state merge; config encodes only `init: true`); `save -o` exports profile-resolved manifest + OCI stack tar (`ArchiveExport`, local images only—no pull); `load -i` imports archive and writes bundled `compose.yaml`; `save`/`load` reject `--machine`.
- Profiles: default `up` skips profiled services; `--profile` (repeatable, OR) and process-env `COMPOSE_PROFILES` (comma-separated, union with CLI—not read from compose `.env`) on `up`, `ps`, `logs`, `top`, `down`, `config`, `watch`; `ProfileResolution.resolve(cliProfiles:environment:)` is the pure merge helper (inject env dict in compose-verify—no setenv); sticky shell `COMPOSE_PROFILES` sets `profileFilterRequested` for query/teardown even on `-p`-only (needs compose file or `profileFilterRequiresComposeFile`; `COMPOSE_PROFILES=*`/`down --profile "*"` stops all project containers without a compose file); `run` auto-enables target service profiles; filter before dependency graph with `profileExcludedDependency`.
- `ComposeCore/Terminal/` is presentation-only (no Container API imports); `Runtime/` holds orchestration (`ServiceRunner` waves + `HealthWait` inter-wave gating, `LogStream`, `SignalForwarding`, `ExecSession`, `AttachAfterUp`, `ProjectStatus`). `compose top` streams `ContainerClient.stats()` by project labels; `compose logs` multiplexes containerLog + bootlog. SIGINT during `up`/`down` leaves started containers running. State uses `com.docker.compose.*` labels on `ContainerRun`. Interactive PTY resize for `exec`/`run` (`useInteractivePTY`) is forwarded by upstream `ProcessIO.handleProcess` (SIGWINCH → `ClientProcess.resize`); compose owns SIGINT/SIGTERM via `SignalForwarding`. `up --attach` is log-only (no PTY resize); `--machine` exec/run resize deferred.
- Scaling: `ReplicaPlanning` is pure validation/naming; replica loops live in `ServicePlanner.startupLayers`; `up` names are always `{project}_{service}_{index}` (1-based); `container_name` errors on `up` via `validateForUp` but still keys `run` via `runContainerBaseName`; `deploy.replicas` must be >= 1 at decode; static host port + replicas > 1 fails at plan time; container-only ports (`80`, `:80`) parse but emit no `-p`; replicas carry `com.docker.compose.container-number`; log multiplex keys by container name and disambiguates replica prefixes. `deploy.resources.limits` via `DeployResourceLimitsPlanning`: whole-integer `cpus` only (fractional decimals and millicore suffixes rejected at plan/config time—Virtualization.framework); omit `cpus` for lightweight services; `memory` maps to `--memory`/`-m`.
- `develop.watch` via FSEvents sync (`WatchDebouncer`, `ContainerFileSync`); `build:` via `BuildRunner`/`Application.BuildCommand` before waves (default tag `{project}_{service}`; args never logged); `compose cp` via `CpSession`/`CpContainerResolver` and shared `ContainerCopyAPI`; dry-run prefixes for build/cp; path sandbox reuses `BindMountPathResolver`; `develop.watch` `rebuild` still deferred.
- Compose `networks:` via `NetworkPlanning`/`NetworkRunner`: validate in `validate()` only; create `{project}_{network}` before startup waves; `down` removal scoped to teardown∪running services (same model as volume purge) and throws on invalid scoped config; host/machine create-delete is project-label scoped (warn on unlabeled reuse). Merge `-f`: bare `backend:` under service `networks:` is YAML null (removes membership)—use `backend: {}` for empty-map membership. Live check: `scripts/smoke-networks.sh` / `make smoke-networks` (macOS 26+).
