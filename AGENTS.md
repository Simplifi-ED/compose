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
- Attributes to map: `image`, `command`, `environment`, standard host-to-container `ports`, short-syntax bind-mount `volumes` (`host:container`), short-form `depends_on` (list of service names), long-form `depends_on` with `condition: service_started` / `service_healthy`, `healthcheck` (`test`, `interval`, `timeout`, `retries`, `start_period`), `profiles`, and `deploy.replicas` [1].
- Health-gated startup: between topological waves, wait for `service_started` (runtime `running`) or `service_healthy` (compose-side probe via `createProcess` — container 1.0.0 has no native per-container health on `ContainerSnapshot`) [1].
- Service scaling: `deploy.replicas` and `up --scale SERVICE=COUNT` (CLI wins) with uniform `{project}_{service}_{index}` container naming [1].
- Dependency-aware startup ordering: topological sort with parallel waves via structured concurrency [1].
- Partial-`up` rollback: tear down containers from successful waves when a later wave fails [1].
- Reverse-topological `down` when a compose file is available; parallel `down` fallback for `-p`-only [1].
- Opt-in `--remove-orphans` on `up`/`down`: profile-aware orphan detection and removal (project label scoped) [1].
- Root-level `configs:` / `secrets:` with local `file:` sources (`external: false` only); service-level short and long refs; read-only staged mounts at `/run/configs/` and `/run/secrets/` via `-v …:ro` [1].
- `down -v` / `--volumes`: Phase 1 bind-mount purge for project-relative host paths only; symlink-safe allowlist [1].
- Staged config/secret files under a project temp directory (`0600` secrets, `0644` configs); removed on container teardown and `down` [1].

### **Out of Scope (DO NOT CODE):**

- Custom bridging networks, overlay networks, or advanced routing [1].
- Named volume declarations, volume drivers, user `volumes:` `:ro` suffixes, and root-level `volumes:` blocks [1].
- External secret/config managers (`external: true`, Vault, cloud SM) [1].
- `depends_on` condition `service_completed_successfully`, restart policies, and HTTP health checks beyond exec/CMD probes [1].
- Image-building lifecycles (no parsing of `build:` blocks or running Dockerfiles) [1].

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

## Learned User Preferences

- v1 scope is minimal real compose (parse `docker-compose.yml`, start/stop services), not full Docker Compose parity.
- Load project skills under `.agents/skills/` (especially `swift-concurrency`, `swift-testing-pro`, `writing-for-interfaces`) when implementing features.
- Prefer structured-concurrency parallelism (`withTaskGroup`) for multi-service orchestration.
- Develop on Command Line Tools only (no full Xcode.app); use `mint install realm/SwiftLint` instead of `brew install swiftlint`.
- Deliver merge-ready PRs with polish included—not deferred follow-up cleanup.
- Run Thermos parallel review (`thermo-nuclear-review` + code-quality subagents) before declaring feature work complete.
- Run Thermos review on feature specs before filing GitHub issues.
- CI/release automation (Makefile, GitHub Actions, Homebrew tap) targets this compose plugin repo only—not upstream `apple/container`.
- Keep new source files ≤250 lines; split modules when exceeded.
- Reuse upstream ContainerCommands APIs (`ContainerLogs`, `ContainerExec`, `AsyncSignalHandler`) instead of reimplementing.
- In test fixtures, pin container images to version tags—not `:latest` or sha digests.

## Learned Workspace Facts

- `container` CLI 1.0.0 at `/usr/local` for local dev; plugin at `{INSTALL_ROOT}/libexec/container-plugins/compose` via `scripts/install-plugin.sh` (`sudo` for `/usr/local`). Homebrew `container` sets `CONTAINER_INSTALL_ROOT` to `opt_prefix`, so plugins belong under `opt/container/libexec/container-plugins/compose`—not `HOMEBREW_PREFIX/libexec/...` from `command -v`. Run `container system start` before plugin discovery; host Linux kernel must be configured (`container system kernel set`) before `container run` or `compose up` succeed.
- Package targets: `ComposeCore`, `compose`, `compose-verify`; on CLT use `swift run -c release compose-verify` (not `swift test`) and `scripts/lint.sh` with `SWIFTLINT_DISABLE_SOURCEKIT=1`. CI/release workflows install SwiftLint via `scripts/install-swiftlint.sh` before `make lint`.
- `compose down` reverse-topological with compose file present; parallel fallback for explicit `-p` only (not `COMPOSE_PROJECT_NAME` or compose `name:`).
- Default compose discovery: `compose.yaml` → … → `docker-compose.yml` + paired `*.override.*`; `COMPOSE_FILE` when no `-f`. Project name: `-p` → `COMPOSE_PROJECT_NAME` → merged `name:` → first-file parent dir. Explicit missing `-f` paths throw; only absent default discovery yields nil so `-p`-only `down`/`ps` can proceed.
- Multi-file merge: unique-key ports/volumes; env list by var name; `depends_on` keyed merge (override wins per service); `healthcheck` override wins. Relative bind-mount paths resolve against the compose file directory, not shell CWD.
- `include:` via `ComposeIncludeResolver`: paths relative to the including file; parent services win naming (duplicate service name errors—unlike `-f` merge); recursive includes with cycle rejection; per-include `env_file` and `project_directory`; bind mounts in included services resolve against `project_directory` (default: included file's directory).
- Per-file substitution before YAML parse: shell environment overrides `.env` beside each compose file; supports `${VAR}`, `${VAR:-default}`, `${VAR-default}`, and `$$` escapes; unresolved `${VAR}` errors; YAML anchors/aliases resolved by Yams during decode.
- CLI subcommands: `up`, `down`, `ps`, `logs`, `top`, `exec`, `run`; `up`/`down` accept `--progress auto|plain|none`; `up --attach` multiplexes logs after detached start; `-f`/`-p` on subcommands, not `compose` root.
- Profiles: default `up` skips profiled services; `--profile` (repeatable, OR) on `up`, `ps`, `logs`, `top`, `down`; `down --profile "*"` stops all project containers; `run` auto-enables the target service's profiles; filter before dependency graph with `profileExcludedDependency` for inactive deps; `COMPOSE_PROFILES` deferred.
- `ComposeCore/Terminal/` is presentation-only (no Container API imports); `Runtime/` holds orchestration (`ServiceRunner` waves + `HealthWait` inter-wave gating, `LogStream`, `SignalForwarding`, `ExecSession`, `AttachAfterUp`, `ProjectStatus`). `compose top` streams `ContainerClient.stats()` by project labels; `compose logs` multiplexes containerLog + bootlog. SIGINT during `up`/`down` leaves started containers running. State uses `com.docker.compose.*` labels on `ContainerRun`.
- Scaling: `ReplicaPlanning` is pure validation/naming; replica loops live in `ServicePlanner.startupLayers`; `up` names are always `{project}_{service}_{index}` (1-based); `container_name` errors on `up` via `validateForUp` but still keys `run` via `runContainerBaseName`; `deploy.replicas` must be >= 1 at decode; static host port + replicas > 1 fails at plan time; container-only ports (`80`, `:80`) parse but emit no `-p`; replicas carry `com.docker.compose.container-number`; log multiplex keys by container name and disambiguates replica prefixes.
- `--remove-orphans` on `up`/`down` is opt-in; `OrphanRemoval` handles profile-aware detection. On `up`, discovery/removal failures warn and startup continues (`UpOrphanRemoval.removeBeforeStartupBestEffort`). `down -v` purges project-relative bind-mount paths only (`BindMountPurge`); named volumes deferred.
