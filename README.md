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
- Per service: `image`, `command`, `ports`, `volumes` (bind mounts), `environment`, `container_name`, `depends_on` (list form)
- `container compose up` (detached) and `container compose down` (stop and remove)
- Dependency-aware startup: services start in `depends_on` order (start order only, not health/readiness); independent services run in parallel
- Failed `up` rolls back containers started in earlier waves
- `down` stops dependents before dependencies when the compose file is present; `-p`-only `down` stops containers in parallel
- `down` validates only the dependency graph (not `image` or other startup fields), so teardown still works if the file was edited after `up`
- Containers without a `com.docker.compose.service` label (or not listed in the compose file) stop last and may not follow `depends_on` order
- Container labels for project tracking (`com.docker.compose.project`, `com.docker.compose.service`)

Not supported yet: long-form `depends_on` with health conditions, networks, named volumes, volume drivers, read-only mounts (`:ro`), `build`, profiles, YAML `extends` / `include`.

### Interrupt handling

Ctrl+C (SIGINT) or SIGTERM during long-running commands is handled gracefully:

| Command | Behavior |
|---------|----------|
| `logs -f` | Stops following logs; containers keep running |
| `up` (mid-wave) | Stops scheduling new waves; already-started containers keep running (no rollback) |
| `up --attach` | SIGTERM project containers, wait `-t` seconds (default 10), then SIGKILL |
| `down` (mid-wave) | Stops after the current wave; some containers may remain |
| Future `top`, `exec` | SIGTERM project containers, wait `-t` seconds (default 10), then SIGKILL |

Interrupt stops scheduling new waves immediately and cancels in-flight container work; partially created containers are force-removed. Exit status follows the shell convention: 130 for SIGINT, 143 for SIGTERM.

### Attach mode

`container compose up --attach` starts containers detached (same as `up`), then follows multiplexed service logs in the foreground until every started service stops or you interrupt.

- Ctrl+C or SIGTERM during attach stops **all** project containers (unlike `logs -f`, which leaves them running).
- Use `-t` / `--timeout` with `up --attach` to set the SIGTERM grace period before SIGKILL (default 10 seconds).
- **Exit codes (v1):** `0` when all watched services reach `stopped`; 130 for SIGINT or 143 for SIGTERM during attach. Attach-phase errors do not roll back containers that already started.
- Per-container process exit codes are not available yet; attach detects completion by polling runtime status until containers stop. When the container API exposes init-process wait, compose will adopt first-non-zero exit aggregation (Docker parity).

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
| `depends_on` | Appended |
| `environment` (map) | Keys merged; later values override |
| `environment` (list) | Merge by variable name; later values override |
| `environment` (map vs list) | Later file's form replaces the earlier one |

**Breaking change (Docker parity):** duplicate port keys or bind-mount container paths no longer accumulate — the later file replaces the earlier entry. Non-colliding entries (e.g. `18080:80` + `18081:81`) are kept.

Use the same `-f` flags on `down` as on `up`, or pass `-p` to tear down by project name without reading compose files.

Relative bind-mount paths resolve against the **first** compose file's directory (Docker-identical). Keep overlay files beside the base file, or use absolute host paths. Each compose file loads its own `.env` from its directory during parsing. Override files cannot remove entries from an earlier file without matching the same merge key.

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

- `ComposeCore` — YAML parsing, service planning, `ContainerRun` for up, `ContainerTeardown` (stop + delete) for down
- `compose` — CLI plugin binary registered by `container`
- `compose-verify` — parser/planner checks (Command Line Tools friendly)

## License

Apache-2.0. See [LICENSE](LICENSE).
