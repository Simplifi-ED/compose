# container compose plugin

Native [`container compose`](https://github.com/apple/container) plugin for macOS — define and run multi-container apps from `docker-compose.yml` using Apple's `ContainerCommands` API.

Maintained by [Omnivya](https://www.omnivya.fr) ([Simplifi-ED](https://github.com/Simplifi-ED)).

## Requirements

- macOS 15+ on Apple Silicon
- [container](https://github.com/apple/container) CLI 1.0.0+
- Swift 6.2+ (Command Line Tools or Xcode)

## Features (v1)

- Compose files (`-f`, auto-discovery of `compose.yaml` / `docker-compose.yml` + override; `COMPOSE_FILE`; repeat `-f` to merge)
- Project name (`-p`, `COMPOSE_PROJECT_NAME`, compose `name:`, default: parent directory of the first compose file)
- Per service: `image`, `command`, `ports`, `volumes` (bind mounts), `environment`, `depends_on` (list or long-form with `service_started` / `service_healthy`), `healthcheck`, `profiles`, `deploy.replicas`
- Service scaling: `deploy.replicas` in the compose file or `up --scale SERVICE=COUNT` (CLI wins); containers are named `{project}_{service}_{index}`
- `container compose up` (detached) and `container compose down` (stop and remove)
- Dependency-aware startup: topological waves with parallel starts; list-form `depends_on` is order-only; long-form `condition: service_healthy` waits for healthcheck probes (compose-side exec via `createProcess`; no native engine health status in container 1.0.0)
- Failed `up` rolls back containers started in earlier waves
- `down` stops dependents before dependencies when the compose file is present; `-p`-only `down` stops containers in parallel
- `down` validates only the dependency graph (not `image` or other startup fields), so teardown still works if the file was edited after `up`
- Containers without a `com.docker.compose.service` label (or not listed in the compose file) stop last and may not follow `depends_on` order
- Container labels for project tracking (`com.docker.compose.project`, `com.docker.compose.service`)
- `container compose ps` (list project containers), `container compose top` (live CPU/memory stats stream), and `container compose run` (one-off foreground container from a service definition)

Not supported yet: `depends_on` condition `service_completed_successfully`, networks, named volumes, volume drivers, read-only mounts (`:ro`), `build`, YAML `extends` / `include`, `${VAR:+replacement}` / `${VAR?error}` forms, unbraced `$VAR` interpolation, `COMPOSE_PROFILES` environment variable.

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
| `up` | Unprofiled services only | Unprofiled + `debug` services | N/A |
| `ps`, `logs`, `top` | All project containers | Unprofiled + `debug` containers | All project containers |
| `down` | All project containers | Unprofiled + `debug` containers | All project containers |

`depends_on` referencing a profile-only service that is not active fails at plan time with an actionable error.

`down --profile` is container-scoped only (no network or named-volume teardown in v1). Containers left running may still hold ports or bind mounts; resolve conflicts before re-running `up`.

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
```

- Containers are always named `{project}_{service}_{index}` with a 1-based index (`demo_web_1`, `demo_web_2`), even at one replica.
- All replicas share the `com.docker.compose.service` label, so `ps`, `logs web`, `top`, and `down` cover every replica. Each replica also gets a `com.docker.compose.container-number` label.
- Replicas of a service start in parallel within their `depends_on` wave, and a failed wave rolls back all replicas started in earlier waves.
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

## Quick start

```bash
swift build -c release
./scripts/install-plugin.sh
```

If install requires elevated permissions (e.g. `/usr/local`):

```bash
sudo mkdir -p "$(dirname "$(dirname "$(command -v container)")")/libexec/container-plugins/compose"
sudo cp -R dist/compose/* "$(dirname "$(dirname "$(command -v container)")")/libexec/container-plugins/compose/"
```

Verify:

```bash
container system start
container --help | grep -A2 PLUGINS
container compose --help
```

Run a sample stack:

```bash
container compose up -f fixtures/minimal-compose.yml -p demo
curl http://127.0.0.1:18080/
container compose down -f fixtures/minimal-compose.yml -p demo
```

## Kernel setup

If `container run` or `compose up` fails with a kernel error:

```bash
container system kernel set --url <kernel-tarball-url>
```

## Development

```bash
swift build -c release
swift run -c release compose-verify
.build/release/compose up -f fixtures/minimal-compose.yml -p dev
```

## Architecture

- `ComposeCore` — YAML parsing, service planning, `ContainerRun` for `up` and `run`, `ContainerTeardown` (stop + delete) for `down`, observability commands (`ps`, `logs`, `top`), interactive sessions (`exec`, `run`)
- `compose` — CLI plugin binary registered by `container`
- `compose-verify` — parser/planner checks (Command Line Tools friendly)

## License

Apache-2.0. See [LICENSE](LICENSE).
