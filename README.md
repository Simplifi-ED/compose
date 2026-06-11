# container compose plugin

Native [`container compose`](https://github.com/apple/container) plugin for macOS — define and run multi-container apps from `docker-compose.yml` using Apple's `ContainerCommands` API.

Maintained by [Omnivya](https://www.omnivya.fr) ([Simplifi-ED](https://github.com/Simplifi-ED)).

## Requirements

- macOS 15+ on Apple Silicon (arm64)
- [container](https://github.com/apple/container) CLI 1.0.0+
- Swift 6.2+ (Command Line Tools or Xcode) — source builds only

## Install

**Homebrew (recommended):**

```bash
brew tap Simplifi-ED/compose
brew install container-compose
container system start
container --help | grep -A2 PLUGINS
```

`post_install` symlinks the plugin when the target directory is writable. If install used a root-owned `/usr/local` container PKG, run the manual symlink from `brew info container-compose` with `sudo`.

**GitHub Release:**

```bash
curl -fsSLO https://github.com/Simplifi-ED/compose/releases/latest/download/container-compose-macos-arm64.zip
unzip container-compose-macos-arm64.zip -d container-compose
# layout: bin/compose, config.toml
./scripts/install.sh   # from a git checkout, or copy into libexec manually
```

Prebuilt tarball for Homebrew: `compose-plugin.tar.gz` (same layout).

**From source:**

```bash
git clone https://github.com/Simplifi-ED/compose.git && cd compose
./scripts/install.sh
```

## Quick start

```bash
container system start
container compose up -f fixtures/minimal-compose.yml -p demo
curl http://127.0.0.1:18080/
container compose down -f fixtures/minimal-compose.yml -p demo
```

## Supported compose keys (v1)

| Key / feature | Status | Notes |
|---------------|--------|-------|
| `image`, `command`, `ports`, `environment` | supported | standard host-to-container ports |
| `volumes` (bind mounts, short syntax) | supported | project-relative paths only for `down -v` purge |
| `depends_on` (list) | supported | order-only between waves |
| `depends_on` (`service_started` / `service_healthy`) | supported | health via compose-side exec probe |
| `healthcheck` | supported | exec/CMD probes |
| `profiles`, `deploy.replicas`, `name:` | supported | `--scale` overrides replicas |
| `-f` merge, auto-discovery, `COMPOSE_FILE`, `include:` | supported | see sections below |
| `build`, networks, named volumes, `:ro`, `service_completed_successfully` | not supported | v1 deferred |

## Features (v1)

- Compose files (`-f`, auto-discovery of `compose.yaml` / `docker-compose.yml` + override; `COMPOSE_FILE`; repeat `-f` to merge; YAML `include:` for modular sub-projects)
- Project name (`-p`, `COMPOSE_PROJECT_NAME`, compose `name:`, default: parent directory of the first compose file)
- Per service: `image`, `command`, `ports`, `volumes` (bind mounts), `environment`, `depends_on` (list or long-form with `service_started` / `service_healthy`), `healthcheck`, `profiles`, `deploy.replicas`
- Service scaling: `deploy.replicas` in the compose file or `up --scale SERVICE=COUNT` (CLI wins); containers are named `{project}_{service}_{index}`
- `container compose up` (detached) and `container compose down` (stop and remove)
- Dependency-aware startup: topological waves with parallel starts; list-form `depends_on` is order-only; long-form `condition: service_healthy` waits for healthcheck probes (compose-side exec via `createProcess`; no native engine health status in container 1.0.0)
- Failed `up` rolls back containers started in earlier waves
- `down` stops dependents before dependencies when the compose file is present; `-p`-only `down` stops containers in parallel
- `down` validates only the dependency graph (not `image` or other startup fields), so teardown still works if the file was edited after `up`
- Containers without a `com.docker.compose.service` label (or not listed in the compose file) stop last and may not follow `depends_on` order; pass `--remove-orphans` on `up` to remove them before startup
- Opt-in `--remove-orphans` on `up` and `down` removes project containers whose service is missing from the compose file or not in the active profile set
- `down -v` / `down --volumes` removes project-local bind-mount host paths declared in the compose file (see [Workspace hygiene](#workspace-hygiene))
- Container labels for project tracking (`com.docker.compose.project`, `com.docker.compose.service`)
- `container compose ps` (list project containers), `container compose top` (live CPU/memory stats stream), `container compose run` (one-off foreground container from a service definition), and `container compose config` (parse and print the resolved compose file without starting containers)

Not supported yet: `depends_on` condition `service_completed_successfully`, networks, named volumes, volume drivers, read-only mounts (`:ro`), `build`, YAML `extends`, `${VAR:+replacement}` / `${VAR?error}` forms, unbraced `$VAR` interpolation, `COMPOSE_PROFILES` environment variable.

### Profiles

Services with `profiles` start only when a matching `--profile` is passed to `up`. Services without `profiles` always start on `up`. Repeat `--profile` to OR multiple profiles.

```bash
container compose up                          # unprofiled services only
container compose up --profile debug          # unprofiled + debug profile
container compose up --profile debug --profile metrics
container compose run debugger sh             # auto-enables the service's profiles
```

| Command | No `--profile` | With `--profile debug` | With `--profile "*"` |
|---------|----------------|------------------------|----------------------|
| `up`, `config` | Unprofiled services only | Unprofiled + `debug` services | N/A |
| `ps`, `logs`, `top` | All project containers | Unprofiled + `debug` containers | All project containers |
| `down` | All project containers | Unprofiled + `debug` containers | All project containers |

`depends_on` referencing a profile-only service that is not active fails at plan time with an actionable error.

`down --profile` is container-scoped only (no network or named-volume teardown in v1). Containers left running may still hold ports or bind mounts; resolve conflicts before re-running `up`.

With `--remove-orphans`, `up` removes stale containers before startup. On `down --profile`, it also stops profile-skipped containers that would otherwise keep running.

### Include

Compose files can pull in sibling or shared sub-projects with a top-level `include:` block. Paths resolve relative to the **including file's directory** (not the shell CWD).

```yaml
include:
  - ./infra/db.yml
  - path: ../shared/cache.yml
    project_directory: ../shared
    env_file: ../shared/.env
```

- **Local services win naming:** services defined in the parent file are loaded first; each `include` entry adds services. A duplicate service name is an error (unlike `-f` merge, where later files override).
- **Recursive includes:** included files may define their own `include:` entries. Circular chains are rejected with the file path chain in the error.
- **Environment:** each included file uses its own `env_file` list (or `.env` in `project_directory` by default). Shell environment variables override those values. The parent file's `.env` does not apply to included files.
- **Bind mounts:** relative volume paths in included services resolve against `project_directory` (default: the included compose file's directory).

### Config

`container compose config` parses, merges, substitutes variables, and expands `include:` entries, then prints canonical YAML to stdout. It does not contact the container runtime.

```bash
container compose config
container compose config -f docker-compose.yml
container compose config -f base.yml -f override.yml
container compose config --profile debug
container compose config --scale web=3
container compose config --quiet    # validate only; no output on success
```

| Flag | Behavior |
|------|----------|
| `-f` / auto-discovery | Same file resolution as `up` |
| `-p` | Accepted for CLI parity; does not change emitted YAML (only compose `name:` appears) |
| `--profile` | Output only services active under the same rules as `up` |
| `--scale` | Writes CLI replica overrides into `deploy.replicas` in the output |
| `--quiet` | Validate only; exit non-zero on failure without printing YAML |

Substitution always runs (`.env` beside each compose file, shell environment overrides). There is no `--no-interpolate` flag in v1. Unresolved `${VAR}` placeholders fail with a file path and variable name in the error.

Validation covers structural parsing, dependency graph checks, missing `image`, and the same planning rules as `up` for active services (for example `container_name` with scale, static host ports with multiple replicas). JSON Schema validation against the upstream compose-spec is deferred.

### Workspace hygiene

```bash
container compose up --remove-orphans     # remove stale containers before startup
container compose down --remove-orphans   # with --profile, also stop profile-skipped containers
container compose down -v                 # remove project-local bind-mount paths after containers stop
```

**`--remove-orphans`** (opt-in on `up` and `down`):

- Scopes to the active project via `com.docker.compose.project` (exact label match).
- Removes containers with no service label, a service removed from the compose file, or a service not in the current profile set (same rules as `up` / `down --profile`).
- Prints a one-line summary when orphans are removed on `up`. On plain `down` (no `--profile`), all project containers are already stopped.
- On `up`, orphan removal runs inside the same signal-handled phase as startup and honors `--parallel` when set. Discovery or teardown failures warn and startup continues; successfully removed orphans still print a summary when removal is partial.

**`down -v` / `--volumes`** (Phase 1 — bind mounts only):

| Removed | Not removed |
|---------|-------------|
| Relative bind-mount host paths (`./data:/app`) resolved under the compose file directory | Absolute host paths (`/var/data:/app`) |
| Paths declared on services in the tear-down scope | Named volumes, `:ro` mounts, root `volumes:` blocks |
| Duplicate paths across services (deduped) | Compose YAML files, compose root directory |
| | Paths outside the project after symlink resolution |

Containers are stopped before host paths are deleted. Named-volume purge is deferred until root `volumes:` support lands.

### Scaling

Run multiple instances of a service with `deploy.replicas` in the compose file or `--scale SERVICE=COUNT` on `up`. The CLI flag overrides the file value.

```yaml
services:
  web:
    image: docker.io/library/nginx:latest
    ports:
      - "80"          # container-only port; no host bind, so replicas don't collide
    deploy:
      replicas: 2
```

```bash
container compose up                  # 2 web replicas from deploy.replicas
container compose up --scale web=3   # CLI override: 3 replicas
container compose up --scale web=3 --scale db=2
container compose up --parallel 2    # at most 2 containers start per wave
container compose up --scale web=3 --parallel 2   # 3 web replicas, two-at-a-time in the same wave
```

- Containers are always named `{project}_{service}_{index}` with a 1-based index (`demo_web_1`, `demo_web_2`), even at one replica.
- All replicas share the `com.docker.compose.service` label, so `ps`, `logs web`, `top`, and `down` cover every replica. Each replica also gets a `com.docker.compose.container-number` label.
- Replicas of a service start within their `depends_on` wave; by default all containers in a wave start at once. Use `--parallel N` on `up` or `down` to cap how many containers start or stop at once within each wave (dependency order and health waits between waves are unchanged). The same limit applies to `up --remove-orphans` teardown and to rollback after a failed wave. A failed wave rolls back all replicas started in earlier waves.
- A static host port (`"8080:80"`) with more than one replica fails before any container starts — each replica would bind the same host port. Use a container-only port (`"80"` or `":80"`) to scale; the runtime doesn't allocate dynamic host ports, so container-only ports aren't bound on the host.
- `container_name` conflicts with indexed naming and fails `up` at plan time; remove it from services you start with `up`. (`run` still honors it for one-off `{container_name}_run_*` containers.)
- Other `deploy` keys (resources, placement, update_config, ...) are parsed and ignored.
- Containers from older versions without an index suffix aren't reused; `down` removes them by project label.
- After a successful `up`, stdout prints one aligned row per service (not one container name per line). Scripts that parsed flat stdout from older versions need to read the grouped rows or use `compose ps` instead:

  ```
  web  demo_web_1  demo_web_2
  db   demo_db_1
  ```

- `compose logs` and `up --attach` prefix each replica with its container name when multiple replicas share a service; single-replica services keep the service name prefix.

### Interrupt handling

Ctrl+C (SIGINT) or SIGTERM during long-running commands is handled gracefully:

| Command | Behavior |
|---------|----------|
| `logs -f` | Stops following logs; containers keep running |
| `up` (mid-wave) | Stops scheduling new waves; already-started containers keep running (no rollback) |
| `up --attach` | SIGTERM project containers, wait `-t` seconds (default 10), then SIGKILL |
| `exec` | SIGTERM project containers, wait `--timeout` seconds (default 10), then SIGKILL |
| `run` | SIGTERM and remove only the run container, wait `--timeout` seconds (default 10), then SIGKILL; other project containers keep running |
| `down` (mid-wave) | Stops after the current wave; some containers may remain |
| `top` | Stops streaming stats; containers keep running |

Interrupt stops scheduling new waves immediately and cancels in-flight container work; partially created containers are force-removed. Exit status follows the shell convention: 130 for SIGINT, 143 for SIGTERM.

### Attach mode

`container compose up --attach` starts containers detached (same as `up`), then follows multiplexed service logs in the foreground until every started service stops or you interrupt.

- Ctrl+C or SIGTERM during attach stops **all** project containers (unlike `logs -f`, which leaves them running).
- Use `-t` / `--timeout` with `up --attach` to set the SIGTERM grace period before SIGKILL (default 10 seconds).
- **Exit codes (v1):** `0` when all watched services reach `stopped`; 130 for SIGINT or 143 for SIGTERM during attach. Attach-phase errors do not roll back containers that already started.
- Per-container process exit codes are not available yet; attach detects completion by polling runtime status until containers stop. When the container API exposes init-process wait, compose will adopt first-non-zero exit aggregation (Docker parity).

### Top

`container compose top` displays a live resource table for project containers (CPU, memory, network, block I/O, PIDs).

```bash
container compose top
container compose top -f docker-compose.yml -p demo web db
container compose top | cat    # single snapshot when stdout is not a TTY
```

- Uses the same project scoping and service filter as `ps` (`-f`, `-p`, optional service names).
- Refreshes about once per second on an interactive TTY with in-place table redraw.
- Redirected output (`pipe` mode) prints one snapshot and exits.
- Ctrl+C (interactive, plain, or pipe) stops with exit code 0 via quiet cancel; containers keep running.

### Exec

`container compose exec SERVICE COMMAND [ARGS...]` runs a command in a running service container.

```bash
container compose exec web sh
container compose exec -f docker-compose.yml -p demo db psql -U postgres
```

- Resolves the container by `com.docker.compose.project` and `com.docker.compose.service` labels (no arbitrary container ID passthrough).
- Passes `COMMAND` and `ARGS` directly to the container runtime without wrapping in `/bin/sh -c` unless you supply that yourself.
- When stdin is a TTY, `-i` and `-t` are enabled automatically. Piped or redirected stdin stays non-interactive unless you pass `-i`. There is no `-T` flag yet to disable auto-allocation from an interactive terminal.
- Use `--timeout` to set the SIGTERM grace period before SIGKILL when you interrupt (default 10 seconds). On `exec`, `-t` allocates a pseudo-TTY (not the shutdown timeout).
- **Exit codes:** the exec process exit code on normal completion; 130 for SIGINT or 143 for SIGTERM when interrupted (project containers are stopped).
- Not supported at the compose layer yet: `-e`, `-w`, `-u`, detach, or replica index selection. When a service runs multiple replicas, `exec` asks you to target one with `container exec CONTAINER COMMAND`.
- Use `container compose run` to start a new container from the service definition when nothing is running yet.

### Run

`container compose run SERVICE [COMMAND] [ARGS...]` creates a new foreground container from a service definition.

```bash
container compose run web sh
container compose run --rm db psql -U postgres -c 'SELECT 1'
container compose run -f docker-compose.yml -p demo worker python manage.py migrate
```

- Reads the compose file for the service `image`, `command`, `environment`, `ports`, and bind-mount `volumes` (same mapping as `up`).
- Does not start `depends_on` services in v1.
- Names one-off containers `{project}_{service}_run_*` (or `{container_name}_run_*`) so they do not replace containers started by `up`.
- Containers started by `up` keep running; `run` does not attach to or stop them.
- One-off containers use the same `com.docker.compose.*` labels and appear in `ps`, `logs`, and `top`; `down` removes them with the project.
- Omit `COMMAND` to use the service `command` from the compose file (or the image default).
- Pass `--rm` to remove the container after it exits (opt-in; default keeps it until `down` or manual removal).
- When stdin is a TTY, `-i` and `-t` are enabled automatically (same rules as `exec`).
- Use `--timeout` for the SIGTERM grace period before SIGKILL when you interrupt (default 10 seconds). On `run`, `-t` allocates a pseudo-TTY (not the shutdown timeout).
- **Exit codes:** the container init process exit code on normal completion; 130 for SIGINT or 143 for SIGTERM when interrupted.
- If the same service ports are already published by `up`, `run` fails at bind time (no preflight).
- Interactive `-it` runs restore the host terminal on Ctrl+C (compose captures stdin state before `ContainerRun` enters raw mode).

### Multi-file merge

Pass `-f` more than once to layer compose files. Files merge left to right; later files override earlier ones.

When `-f` is omitted, the plugin discovers compose files in the current directory:

1. First match among `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`
2. Paired override file (`compose.override.yaml` / `compose.override.yml`, etc.) when present
3. `COMPOSE_FILE` (colon-separated paths) when set and no `-f` flags
4. Fallback to `docker-compose.yml`

Explicit `-f` paths ignore `COMPOSE_FILE` and do not auto-pair override files.

```bash
container compose up -f base.yml -f override.yml
container compose down -f base.yml -f override.yml
COMPOSE_FILE=base.yml:override.yml container compose up
COMPOSE_PROJECT_NAME=myapp container compose up
```

| Field | Merge rule |
|-------|------------|
| Top-level `name` | Last non-nil value wins |
| Service absent in later file | Unchanged |
| Service only in later file | Added |
| `image`, `container_name`, `command` | Last specified value wins |
| `ports` | Unique-key merge by `{host, container, protocol}` (short syntax) |
| `volumes` (bind mounts) | Unique-key merge by container mount path |
| `depends_on` | Keyed merge by service name (override wins per dependency) |
| `healthcheck` | Last specified value wins |
| `environment` (map) | Keys merged; later values override |
| `environment` (list) | Merge by variable name; later values override |
| `environment` (map vs list) | Later file's form replaces the earlier one |

**Breaking change (Docker parity):** duplicate port keys or bind-mount container paths no longer accumulate — the later file replaces the earlier entry. Non-colliding entries (e.g. `18080:80` + `18081:81`) are kept.

Use the same `-f` flags on `down` as on `up`, or pass `-p` to tear down by project name without reading compose files.

Relative bind-mount paths resolve against the **first** compose file's directory (Docker-identical). Keep overlay files beside the base file, or use absolute host paths. Override files cannot remove entries from an earlier file without matching the same merge key.

### Variable substitution

Interpolation runs on each compose file's raw text before YAML parse (per Compose spec, only **values** should use `${…}`; keys are not expanded unless you embed placeholders there). Multi-file merge happens after per-file substitution.

| Form | Behavior |
|------|----------|
| `${VAR}` | Required; errors if unset |
| `${VAR:-default}` | Uses `default` when `VAR` is unset or empty |
| `${VAR-default}` | Uses `default` only when `VAR` is unset (empty string is valid) |
| `$$` | Literal `$` (for example `$$VAR` → `$VAR`) |

**Variable sources (highest precedence first):** shell environment, then `.env` beside each compose file. Each `-f` file loads its own `.env` from its directory.

YAML anchors (`&`) and aliases (`*`) are resolved during parse, including `<<:` merge keys.

Relative bind-mount host paths that resolve outside the compose file directory are rejected after substitution. Absolute host paths are allowed.

### Container labels

Each container started by `compose up` gets two metadata labels:

| Label | Value |
|-------|-------|
| `com.docker.compose.project` | Project name (`-p`, `COMPOSE_PROJECT_NAME`, compose `name:`, or first compose file's parent directory) |
| `com.docker.compose.service` | Service name from the compose file |

`compose down` finds containers by `com.docker.compose.project`. Use the same project name you used with `up` (`-p`, `COMPOSE_PROJECT_NAME`, or compose `name:`). When `-p` is set explicitly, shutdown runs in parallel and does not read the compose file (even if `docker-compose.yml` is present). `COMPOSE_PROJECT_NAME` and compose `name:` still use ordered shutdown when compose files are present.

If the compose file has a broken dependency graph (circular or unknown `depends_on` references), ordered shutdown fails. Tear down in parallel with `compose down -p <project>`, or fix the graph first.

`compose down` prints one line per removed container name (discovered at runtime, not from the compose file). If no labeled containers match the project, it prints nothing and exits successfully.

Containers created before label support have no labels. `compose down` cannot find them, and `compose up` fails if the container name already exists. Remove them first with `container rm <name>`, then run `compose up`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Gatekeeper blocks the binary | Release builds are ad-hoc signed. Clear quarantine: `xattr -d com.apple.quarantine dist/compose/bin/compose` |
| Port `18080` in use | Change the host port in compose YAML or `container compose down -p <project>` |
| `compose` not under PLUGINS | Run `container system start`; verify plugin at `{INSTALL_ROOT}/libexec/container-plugins/compose` |
| Permission denied on `/usr/local` | Use `sudo` for mkdir/cp, or Homebrew symlink path from `brew info container-compose` |
| Kernel / runtime error on `up` | `container system kernel set --url <kernel-tarball-url>` |
| Smoke test image fails on arm64 | Use images with a `linux/arm64` manifest; see comment in `fixtures/minimal-compose.yml` |

Plugin install path: `{INSTALL_ROOT}/libexec/container-plugins/compose` where `INSTALL_ROOT` is the parent of `container`'s `bin` directory (or `opt/container` for Homebrew formula installs).

## Kernel setup

If `container run` or `compose up` fails with a kernel error:

```bash
container system kernel set --url <kernel-tarball-url>
```

## Development

```bash
make build
make lint
make test          # compose-verify (not swift test on CLT)
make dist          # dist/compose/, compose-plugin.tar.gz, container-compose-macos-arm64.zip
make smoke         # end-to-end: install, up, curl, down (requires container runtime)
```

Or without Make:

```bash
swift build -c release
swift run -c release compose-verify
./scripts/build-release.sh
```

CI on every pull request: `make lint`, debug build with warnings-as-errors, `compose-verify`, and release-build codesign verification on `macos-15`. Live smoke tests run on `main` with `continue-on-error` (GHA runners may lack nested virtualization).

## Release

Tag a semver version to publish release artifacts:

```bash
git tag v0.0.1
git push origin v0.0.1
```

The release workflow uploads `compose-plugin.tar.gz` and `container-compose-macos-arm64.zip` (each with SHA256 checksums), then opens a PR to bump [`Formula/container-compose.rb`](Formula/container-compose.rb). Release binaries are stripped and ad-hoc signed (`codesign -s -`).

**Migrating from manual installs:** reinstall via Homebrew or `./scripts/install.sh`; ensure the plugin symlink under `libexec/container-plugins/compose` points at the new version.

## Architecture

- `ComposeCore` — YAML parsing, service planning, `ContainerRun` for `up` and `run`, `ContainerTeardown` (stop + delete) for `down`, observability commands (`ps`, `logs`, `top`), interactive sessions (`exec`, `run`)
- `compose` — CLI plugin binary registered by `container`
- `compose-verify` — parser/planner checks (Command Line Tools friendly)

## License

Apache-2.0. See [LICENSE](LICENSE).
