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
- Attributes to map: `image`, `command`, `environment`, standard host-to-container `ports`, short-syntax bind-mount `volumes` (`host:container`), short-form `depends_on` (list of service names), `profiles`, and `deploy.replicas` [1].
- Service scaling: `deploy.replicas` and `up --scale SERVICE=COUNT` (CLI wins) with uniform `{project}_{service}_{index}` container naming [1].
- Dependency-aware startup ordering: topological sort with parallel waves via structured concurrency [1].
- Partial-`up` rollback: tear down containers from successful waves when a later wave fails [1].
- Reverse-topological `down` when a compose file is available; parallel `down` fallback for `-p`-only [1].

### **Out of Scope (DO NOT CODE):**

- Custom bridging networks, overlay networks, or advanced routing [1].
- Named volume declarations, volume drivers, read-only mount suffixes (`:ro`), and root-level `volumes:` blocks [1].
- Long-form `depends_on` with `condition:` (for example `service_healthy`), health-check gating, or restart policies [1].
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
swift build -c release

# 2. Package into target directory structure
mkdir -p dist/compose/bin
cp .build/release/compose dist/compose/bin/
cp config.toml dist/compose/

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
- Keep new source files ≤250 lines; split modules when exceeded.
- Reuse upstream ContainerCommands APIs (`ContainerLogs`, `ContainerExec`, `AsyncSignalHandler`) instead of reimplementing.

## Learned Workspace Facts

- `container` CLI 1.0.0 at `/usr/local`; plugin at `{INSTALL_ROOT}/libexec/container-plugins/compose` (not Homebrew paths); `/usr/local` install needs `sudo` via `scripts/install-plugin.sh`. Run `container system start` before plugin discovery.
- Package targets: `ComposeCore`, `compose`, `compose-verify`; on CLT use `swift run -c release compose-verify` (not `swift test`) and `scripts/lint.sh` with `SWIFTLINT_DISABLE_SOURCEKIT=1`.
- `compose down` reverse-topological with compose file present; parallel fallback for explicit `-p` only (not `COMPOSE_PROJECT_NAME` or compose `name:`).
- Default compose discovery: `compose.yaml` → … → `docker-compose.yml` + paired `*.override.*`; `COMPOSE_FILE` when no `-f`. Project name: `-p` → `COMPOSE_PROJECT_NAME` → merged `name:` → first-file parent dir.
- Multi-file merge: unique-key ports/volumes; env list by var name; `depends_on` append-only. Relative bind-mount paths resolve against the compose file directory, not shell CWD.
- Per-file substitution before YAML parse: shell environment overrides `.env` beside each compose file; supports `${VAR}`, `${VAR:-default}`, `${VAR-default}`, and `$$` escapes; unresolved `${VAR}` errors; YAML anchors/aliases resolved by Yams during decode.
- CLI subcommands: `up`, `down`, `ps`, `logs`, `top`, `exec`, `run`; `up`/`down` accept `--progress auto|plain|none`; `up --attach` multiplexes logs after detached start; `-f`/`-p` on subcommands, not `compose` root.
- Profiles: default `up` skips profiled services; `--profile` (repeatable, OR) on `up`, `ps`, `logs`, `top`, `down`; `down --profile "*"` stops all project containers; `run` auto-enables the target service's profiles; filter before dependency graph with `profileExcludedDependency` for inactive deps; `COMPOSE_PROFILES` deferred.
- `ComposeCore/Terminal/` is presentation-only (no Container API imports); `Runtime/` holds orchestration (`ServiceRunner` waves only, `LogStream`, `SignalForwarding`, `ExecSession`, `AttachAfterUp`, `ProjectStatus`).
- `compose top` streams `ContainerClient.stats()` filtered by project labels (not in-container `ps`); `compose logs` multiplexes upstream file handles (merged containerLog + bootlog).
- SIGINT during `up`/`down` orchestration leaves started containers running; `SignalForwarding` coordinates stop/teardown for attach, logs follow, top, exec, and run.
- State tracking uses `com.docker.compose.*` labels on `ContainerRun`; discovery, `ps`, and `logs` read `snapshot.configuration.labels`.
- Scaling: `ReplicaPlanning` is pure validation/naming; replica loops live in `ServicePlanner.startupLayers`; `up` names are always `{project}_{service}_{index}` (1-based); `container_name` errors on `up` via `validateForUp` but still keys `run` via `runContainerBaseName`; `deploy.replicas` must be >= 1 at decode; static host port + replicas > 1 fails at plan time; container-only ports (`80`, `:80`) parse but emit no `-p`; replicas carry `com.docker.compose.container-number`; log multiplex keys by container name and disambiguates replica prefixes.
- Host Linux kernel must be configured (`container system kernel set`) before `container run` or `compose up` succeed.
- Explicit missing `-f` paths throw; only absent default discovery yields nil so `-p`-only `down`/`ps` can proceed.
