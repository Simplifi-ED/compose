# container compose

A native plugin for [Apple's `container` CLI](https://github.com/apple/container) that brings `docker compose`-style orchestration to macOS — start, stop, and manage multi-container apps from a standard `docker-compose.yml`.

Maintained by [Omnivya](https://www.omnivya.fr) · [Simplifi-ED](https://github.com/Simplifi-ED)

---

## Requirements

- macOS 15+ on Apple Silicon (macOS 26+ for container machines / `--machine` and custom `networks:`)
- [`container`](https://github.com/apple/container) CLI 1.0.0+
- Swift 6.2+ — only needed if building from source

---

## Install

Pick one path:

1. **Homebrew (recommended)** — tap installs and upgrades the plugin
2. **Pre-built binary** — download the release zip (no Swift toolchain)
3. **From source** — clone and run `./scripts/install.sh`

After install, run `which container` — if it prints `/usr/local/bin/container`, use the PKG symlink block under Homebrew; if it is under Homebrew's prefix, use the **Caveats** path from `brew info container-compose`.

## Homebrew (recommended)

`container-compose` also exists in Homebrew core (a different project). Install from this tap using the **fully qualified** formula name:

```bash
brew tap Simplifi-ED/compose
brew trust --formula simplifi-ed/compose/container-compose
brew install simplifi-ed/compose/container-compose
```

If `container` was installed via Apple's PKG/Cask to `/usr/local`, link the plugin manually. **Remove any existing plugin directory first** — `ln -sf` into an existing directory nests the symlink instead of replacing it:

```bash
sudo rm -rf /usr/local/libexec/container-plugins/compose
sudo mkdir -p /usr/local/libexec/container-plugins
sudo ln -sf "$(brew --prefix container-compose)/libexec" /usr/local/libexec/container-plugins/compose
```

If `container` was installed via Homebrew (`brew install container`), use the path from `brew info container-compose` under **Caveats** instead.

Start the runtime and verify the plugin (you should see `ps`, `logs`, `exec`, `config`, `watch`, etc. — not only `up`/`down`):

```bash
container system start
container compose --help
container --help | grep -A2 PLUGINS
```

## Pre-built binary

The release zip contains only the plugin (`bin/compose`, `config.toml`) — not `scripts/install.sh`.

```bash
curl -fsSLO https://github.com/Simplifi-ED/compose/releases/latest/download/container-compose-macos-arm64.zip
unzip container-compose-macos-arm64.zip -d container-compose
INSTALL_ROOT="$(dirname "$(dirname "$(command -v container)")")"
sudo mkdir -p "$INSTALL_ROOT/libexec/container-plugins/compose"
sudo cp -R container-compose/* "$INSTALL_ROOT/libexec/container-plugins/compose/"
sudo chmod 755 "$INSTALL_ROOT/libexec/container-plugins/compose/bin/compose"
```

If `container` is from Homebrew (`brew install container`), set `INSTALL_ROOT="$(brew --prefix container)/opt/container"` instead. Override with `CONTAINER_INSTALL_ROOT`.

## From source

```bash
git clone https://github.com/Simplifi-ED/compose.git && cd compose
./scripts/install.sh
```

`scripts/install.sh` installs next to the `container` binary on your PATH — Homebrew's `opt/container` layout when `container` comes from `brew install container`, otherwise the parent of `bin/container` (for example `/usr/local` for PKG/Cask installs). Set `CONTAINER_INSTALL_ROOT` to override.

---

## Quick start

```bash
container system start
container compose up -f fixtures/minimal-compose.yml -p demo
curl http://127.0.0.1:18080/
container compose down -f fixtures/minimal-compose.yml -p demo
```

---

## Commands

| Command | What it does |
|---------|-------------|
| `up` | Start all services (detached). Respects `depends_on` order. |
| `down` | Stop and remove project containers. |
| `ps` | List running containers for the project. |
| `logs` | Stream or print service logs. |
| `exec SERVICE CMD` | Run a command inside a running service container. |
| `cp SRC DEST` | Copy files between the host and a running service container. |
| `run SERVICE [CMD]` | Start a one-off container from a service definition. |
| `top` | Live CPU/memory stats for all project containers. |
| `watch` | Sync local file changes into running containers. |
| `config` | Print the resolved compose config without starting anything. |
| `save` | Export service images and resolved compose YAML to a portable archive. |
| `load` | Import images from a stack archive into the local image store. |

Supported on `up`, `down`, `ps`, `logs`, `exec`, and `cp`:

```bash
container compose up --machine dev -f compose.yaml
```

`watch`, `run`, `top`, `config`, `save`, and `load` reject `--machine`.

---

## Save / load (offline migration)

Bundle resolved compose configuration and local OCI images into a single archive for offline transfer between machines.

```bash
container compose save -f compose.yaml -o stack.tar
container compose load -i stack.tar
container compose up -f compose.yaml
```

**`compose save`** resolves the project the same way as `config` (`-f`, `-p`, profiles, `--scale`). It exports every active service image that is already present in the local Apple container image store. Images are not pulled or built during save — run `compose up` or `container build` first if a tag is missing. Use `--dry-run` to list tags that would be exported without writing an archive.

**`compose load`** imports the nested OCI image tar into the local image store, writes the bundled resolved compose file (default `compose.yaml`, override with `-o`), prints loaded image tags, and shows a manifest summary. It does not start containers. Pass `--force` to load when the nested OCI archive contains invalid members.

**Archive contents (format v1):**

| Member | Contents |
|--------|----------|
| `manifest.json` | Format version, project name, service→image mapping |
| `compose.yaml` | Fully resolved compose configuration |
| `images.tar` | OCI archive (`container image save` format) |

**Limits:** images and resolved YAML only — no volumes, container filesystem state, staged config/secret files, registry push/pull, or encryption. After load, copy any required config/secret source files beside the extracted compose file before `compose up`.

---

## Container machines (`--machine`)

Run a project inside an existing [container machine](https://github.com/apple/container/blob/main/Documentation/Container-Machines.md) instead of the application sandbox.

## Prerequisites

1. macOS 26+ with container machines enabled.
2. Create and name a machine outside compose: `container machine create --name dev` (see `container machine --help`).
3. The machine must already exist. Which commands boot a stopped machine:

| Action | Boots stopped machine? |
|--------|------------------------|
| `up`, `down` | Yes (mutating commands) |
| `ps`, `logs` | No — exits gracefully with "Machine stopped" |
| `--dry-run` | No |
| `exec`, `cp` | No — requires an already-running machine |

## Examples

```bash
container machine list
container compose up --machine dev -f compose.yaml -p demo
container compose ps --machine dev -p demo
container compose logs --machine dev -p demo
container compose exec --machine dev -p demo web sh
container compose cp --machine dev -p demo ./local.txt web:/tmp/local.txt
container compose down --machine dev -p demo
```

Compose prints the active context on stderr once per command (`Execution context: application sandbox` or `Execution context: container machine 'dev'`).

## Volumes and bind mounts

- Machine home mount (`home-mount` on the machine) maps your macOS `$HOME` into the VM at the same path. Compose-relative bind mounts still resolve against the compose file directory on the host; those paths must be visible inside the machine at the same absolute path when home is mounted. Short-syntax options (`:ro`, `:z`, `:ro,z`) apply the same way as in the application sandbox.
- Image builds (`build:`) run inside the machine during `compose up --machine` via the in-VM `container build` CLI. Build context paths must be visible inside the machine (typically under `$HOME`).
- Staged `configs:` / `secrets:` files are written under `~/.config/container-compose/<project>/`, which is inside the mounted home directory.
- A project runs entirely in one context (sandbox or one machine); mixed mode is not supported.

## Limits

- `depends_on: service_completed_successfully` is not supported with `--machine` (plan-time error). Run migrations in the application sandbox or use `compose run` inside the VM. See [How startup works](#how-startup-works).

---

## How startup works

Services start in **dependency waves** — all services in a wave start in parallel, then the next wave begins once the previous one is healthy.

- `depends_on` (list form) → ordering only; no readiness wait
- `depends_on` with `condition: service_started` → waits for the dependency container to reach running state before starting dependents
- `depends_on` with `condition: service_healthy` → waits for the healthcheck probe to pass before starting dependents
- `depends_on` with `condition: service_completed_successfully` → waits for a one-shot dependency to exit with code 0 (one-shot / migration services; unrelated to the `init:` service key); host sandbox only (not `--machine`); long-running daemons time out on exit wait
- `init: true` → see [Init (`init: true`)](#init-init-true) below
- If a wave fails, containers from earlier waves are rolled back automatically

```yaml
services:
  db:
    image: postgres:16
    healthcheck:
      test: ["CMD", "pg_isready"]
      interval: 5s
      timeout: 3s
      retries: 5

  api:
    image: myapp:latest
    depends_on:
      db:
        condition: service_healthy
```

---

## Init (`init: true`)

Apple's container runtime can run a lightweight PID-1 init process that reaps zombie processes and forwards signals. Enable it per service when your container runs shell scripts or other workloads that spawn child processes.

```yaml
services:
  web:
    image: myapp:latest
    init: true
```

| Behavior | Detail |
|----------|--------|
| Mapping | `init: true` → `container run --init` on `up` and `run` |
| When to skip | Single-process images that exit cleanly without extra reaping |
| Multi-file `-f` merge | Later file's explicit `init` wins; omitted `init` inherits from the base file. `init: false` disables `init: true` from a base file |

`init: true` composes with other keys (including `depends_on: service_completed_successfully` on the same service).

### Init vs one-shot dependencies

| Goal | Approach |
|------|----------|
| Reap zombies / signal handling on long-running services | `init: true` on the service |
| Run a migration before the app during `up` | Separate one-shot service + `depends_on: condition: service_completed_successfully` |
| Ad hoc migration or debug task | `compose run --rm SERVICE …` (does not change the running stack) |

```yaml
services:
  migrate:
    image: alpine:3.24
    command: ["sh", "-c", "exit 0"]
  app:
    image: alpine:3.24
    command: ["sleep", "300"]
    depends_on:
      migrate:
        condition: service_completed_successfully
```

---

## Project naming

Every set of containers belongs to a **project**. The name is resolved in this order:

1. `-p` flag on the CLI
2. `COMPOSE_PROJECT_NAME` env var
3. `name:` field in the compose file
4. Parent directory of the compose file (default)

Use the same project name for `up` and `down`, or containers won't be found.

---

## Compose file resolution

When you don't pass `-f`, the plugin resolves compose files in this order:

1. `COMPOSE_FILE` env var (colon-separated paths), when set
2. First discovered standard name in the working directory: `compose.yaml`, `compose.yml`, `docker-compose.yaml`, or `docker-compose.yml`
3. A paired override file for that base (e.g. `compose.override.yaml`) when present
4. Implicit `docker-compose.yml` (may be absent — allows `-p`-only commands such as `down` without a compose file on disk)

Pass `-f` multiple times to merge files — later files override earlier ones:

```bash
container compose up -f base.yml -f production.yml
```

---

## Scaling

Run multiple replicas of a service via the compose file or the CLI:

```yaml
services:
  web:
    image: nginx:latest
    ports:
      - "80"        # container-only port — required for scaling
    deploy:
      replicas: 3
```

```bash
container compose up --scale web=5   # CLI overrides the file
container compose up --parallel 2    # start at most 2 containers per wave
```

**Important:** static host ports (`"8080:80"`) will conflict across replicas and fail at startup. Use container-only ports (`"80"`) when scaling.

Containers are always named `{project}_{service}_{index}` (e.g. `demo_web_1`, `demo_web_2`).

### Resource limits

Set per-service CPU and memory caps under `deploy.resources.limits`:

```yaml
services:
  web:
    image: docker.io/library/alpine:3.24
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 512M
```

**CPU:** whole integers only (`1`, `2`, …). Values like `2.0` normalize to whole cores. Zero, empty, fractional decimals (`0.5`), and millicore notation (`50m`) are rejected at plan time — Apple’s container hypervisor allocates whole cores via Virtualization.framework.

**Omit `cpus` for lightweight services:** when a container does not need a dedicated core, leave the limit unset. The host macOS scheduler distributes work across efficiency (E) and performance (P) cores; idle containers stay low-power.

**Memory:** compose size strings (`512M`, `1G`, bare byte counts). Invalid values fail at plan time.

Limits apply to every replica when scaling. `compose config` (including `--quiet`) validates limits the same way as `up` and `run` — invalid values error before any container starts.

---

## Profiles

Use profiles to define optional services (e.g. debug tools, metrics exporters) that don't start by default.

```yaml
services:
  app:
    image: myapp:latest         # starts always

  debugger:
    image: mytools:latest
    profiles: [debug]           # only starts with --profile debug
```

```bash
container compose up                   # app only
container compose up --profile debug   # app + debugger
COMPOSE_PROFILES=debug container compose up   # same as --profile debug
COMPOSE_PROFILES=debug container compose up --profile metrics   # debug + metrics (union)
```

`--profile` flags add to any profiles set in `COMPOSE_PROFILES` (comma-separated process environment). `COMPOSE_PROFILES` in a `.env` file beside the compose file is not supported yet.

If `COMPOSE_PROFILES` is exported in your shell, `ps`, `logs`, `top`, `config`, `watch`, and `down` need a compose file to apply profile filtering—even with `-p` only. Use `COMPOSE_PROFILES=*` (or `down --profile "*"`) to stop every project container without a compose file.

`compose run debugger sh` auto-enables the service's profiles.

---

## Environment variables

Variables are substituted in compose files before parsing. Each `-f` file loads its own `.env` from its directory. Shell environment takes precedence over `.env`.

| Syntax | Behavior |
|--------|----------|
| `${VAR}` | Required — errors if unset |
| `${VAR:-default}` | Uses `default` if unset or empty |
| `${VAR-default}` | Uses `default` only if unset |
| `$$` | Literal `$` |

Process environment (not compose `${}` substitution): `COMPOSE_FILE`, `COMPOSE_PROJECT_NAME`, and `COMPOSE_PROFILES` (comma-separated; merged with `--profile`).

---

## Configs and secrets

Mount local files into containers as read-only config or secret files:

```yaml
configs:
  app_config:
    file: ./config/app.json

secrets:
  db_password:
    file: ./secrets/db.txt

services:
  api:
    configs: [app_config]    # mounted at /run/configs/app_config
    secrets: [db_password]   # mounted at /run/secrets/db_password
```

File contents are never printed by `compose config`.

---

## Building images (`build:`)

Services can build from a local context instead of pulling a pre-built `image`:

```yaml
services:
  web:
    build: ./app          # short form — context path relative to the compose file
    command: sleep 300

  api:
    image: my_api         # optional — names the built image tag
    build:
      context: ./api
      dockerfile: Dockerfile
      args:
        APP_VERSION: "1.0.0"
      target: runtime
```

**Startup order:** on `up`, all profile-active `build:` services compile before the first startup wave. On `run`, the target service and any transitive `depends_on` services with `build:` compile in dependency order before the one-off container starts.

**Default image tag:** `{project}_{service}` (for example `demo_web`). When both `image` and `build` are set, `image` is the output tag.

**`compose config`:** prints the resolved `image:` tag alongside the `build` block. Does not require build contexts to exist on disk — filesystem checks run only on `up`/`run`.

**Dry-run:** `up --dry-run` / `run --dry-run` emit `[DRY-RUN] build image "…"` lines without invoking the builder.

**Limits:** Dockerfile size capped at 16 KiB by the Apple build engine; no cross-arch `platform` builds; no registry push; `develop.watch` `rebuild` is not supported yet. Build context paths must stay inside the compose file directory (absolute paths are allowed when they still resolve within it).

---

## File watching (`compose watch`)

Sync local changes into running containers without restarting. Start the stack first, then run `watch` in another terminal.

```yaml
services:
  web:
    image: nginx:1.27.3
    develop:
      watch:
        - action: sync
          path: ./html
          target: /usr/share/nginx/html
          ignore: [node_modules/]

        - action: sync+restart   # syncs file then restarts the service
          path: ./conf/nginx.conf
          target: /etc/nginx/conf.d/default.conf
```

```bash
container compose up -p demo
container compose watch -p demo        # watch all services
container compose watch -p demo web    # watch one service
```

Ctrl+C stops watching — containers keep running.

---

## Modular compose files (`include:`)

Split large projects across multiple files using `include:`. Unlike `-f` merge, duplicate service names are an error.

```yaml
include:
  - ./infra/db.yml
  - path: ../shared/cache.yml
    project_directory: ../shared
    env_file: ../shared/.env
```

- Paths resolve relative to the **including file**, not your shell CWD
- Each included file uses its own `.env`
- Recursive includes are supported; circular chains are rejected

---

## Cleanup

```bash
# Remove containers no longer in the compose file
container compose up --remove-orphans

# Remove containers + project bind-mount directories and named volumes
container compose down -v
```

`down -v` removes **relative** bind-mount paths (e.g. `./data:/app`) and project-scoped named volumes created by compose. Absolute bind-mount paths are not touched.

---

## Bind mounts

Short-syntax host bind mounts map to `container run -v`. Relative host paths resolve against the **compose file directory**, not your shell CWD.

```yaml
services:
  web:
    volumes:
      - "./config:/etc/app:ro"       # read-only
      - "./cache:/var/cache:z"         # :z passthrough
      - "./data:/var/data:ro,z"        # comma-separated options
```

| Suffix | Behavior |
|--------|----------|
| *(none)* | Read-write bind mount |
| `:ro` | Read-only at runtime |
| `:z` | Accepted and passed through to the runtime (macOS has no SELinux relabeling; compose does not enforce extra semantics) |
| `:ro,z` / `:z,ro` | Comma-separated; order normalized |

**Not supported:** long-form `read_only: true`, explicit `:rw`.

Multi-file `-f` merge replaces bind mounts by host+container path key — an override can change options (for example writable → `:ro`).

---

## Named volumes

Declare volumes at the root and mount them in services with short syntax. Each volume becomes a project-scoped engine volume named `{project}_{volume}`, created before startup and removed on `down -v`.

```yaml
volumes:
  mydata: {}

services:
  api:
    image: nginx:1.27
    volumes:
      - mydata:/app/data
  worker:
    image: alpine:3.24
    volumes:
      - mydata:/var/data:ro
```

| Behavior | Detail |
|----------|--------|
| Naming | `mydata` in project `demo` → `demo_mydata` |
| Persistence | `compose down` keeps named volumes; `compose down -v` removes project-labeled volumes |
| Validation | Service refs must exist in root `volumes:` |
| Cleanup | `-p`-only `down` (no compose file) cannot name volumes — remove with `container volume rm` |

**Not supported:** volume drivers, NFS/cloud storage, `external: true`, cross-project sharing.

Multi-file `-f` merge: override wins per root volume name; service volume lists union by container path.

---

## Networks

Declare networks at the root and attach services to them. Each network becomes a project-scoped subnet named `{project}_{network}`, created before startup and removed on `down`.

```yaml
networks:
  backend: {}

services:
  api:
    image: nginx:1.27
    networks: [backend]
  db:
    image: postgres:16
    networks:
      backend: {}
```

| Behavior | Detail |
|----------|--------|
| Naming | `backend` in project `demo` → `demo_backend` |
| Default | Services without `networks:` join the builtin `default` network |
| DNS | Containers resolve each other by **container name** (`demo_db_1`), not Docker-style service shorthand (`db`) |
| Cleanup | `compose down` removes project networks after containers; `-p`-only `down` (no compose file) leaves them — remove with `container network rm` |
| Requirements | Custom networks need macOS 26 or newer |

**Not supported:** network drivers, `aliases`, static IP addresses, `priority`, `network_mode`, `external: true`, cross-project sharing.

---

## cp — copy files

Copy files to or from a **running** service container without a bind mount:

```bash
container compose cp web:/app/config.yml ./config.yml    # container → host
container compose cp ./bootstrap.sh web:/app/bootstrap.sh  # host → container
```

**Replica selection** (when a service runs multiple containers):

| Flag | Behavior |
|------|----------|
| *(default)* | Single replica only; errors if more than one is running |
| `--index N` | Target `{project}_{service}_{N}` (1-based) |
| `--all` | Copy into every running replica (**host → container only**) |

**Host paths:** relative paths resolve from your shell's current directory and can't escape it (`..` is rejected). Absolute paths are allowed; compose prints a warning when they fall outside the current directory.

Container paths must be absolute (`SERVICE:/path`) and can't contain `..` segments.

---

## exec vs run

| | `exec` | `run` |
|--|--------|-------|
| Target | Running container | New container from service definition |
| Use for | Debugging live services | Migrations, one-off tasks |
| Affects running stack | No | No (separate container) |
| `depends_on` | N/A | Not started in v1 |

```bash
container compose exec db psql -U postgres       # shell into running db
container compose run --rm db psql -U postgres -c 'SELECT 1'  # one-off query
```

---

## Attach mode

`up --attach` starts containers and streams their logs to your terminal. Ctrl+C stops all containers (unlike `logs -f`, which leaves them running).

```bash
container compose up --attach
container compose up --attach -t 30   # 30s grace period before SIGKILL
```

Exit codes: `0` = all services stopped cleanly · `130` = SIGINT · `143` = SIGTERM

---

## Supported compose fields (v1)

| Field | Status |
|-------|--------|
| `image`, `command`, `ports`, `environment` | ✅ |
| `init` | ✅ |
| `volumes` (bind mounts; named short syntax; `:ro`, `:z`, `:ro,z` on bind mounts) | ✅ |
| `depends_on` (list; long-form `service_started`, `service_healthy`, `service_completed_successfully`†) | ✅ |
| `healthcheck` | ✅ |
| `profiles`, `deploy.replicas`, `deploy.resources.limits` (`cpus`, `memory`) | ✅ |
| `configs`, `secrets` (local `file:`) | ✅ |
| `develop.watch` | ✅ |
| `name:` (project name; overridden by `-p` / `COMPOSE_PROJECT_NAME`) | ✅ |
| `-f` merge, `include:`, `COMPOSE_FILE` | ✅ |
| `build` (`context`, `dockerfile`, `args`, `target`) | ✅ |
| `networks` (project-scoped subnets; container-name DNS) ‡ | ✅ |
| named volumes (project-scoped; short syntax) | ✅ |
| long-form `read_only: true`, explicit `:rw` | ❌ v1 deferred |
| `COMPOSE_PROFILES` env var | ✅ (process env; `.env` file deferred) |

† `service_completed_successfully` is supported in the application sandbox only; `compose up --machine` rejects it at plan time.

‡ Custom declared networks require macOS 26+; default network behavior is unchanged on macOS 15+.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Gatekeeper blocks the binary | `xattr -d com.apple.quarantine dist/compose/bin/compose` |
| `compose` not listed under PLUGINS | `container system start` — then verify the symlink exists at `{INSTALL_ROOT}/libexec/container-plugins/compose` |
| Permission denied on `/usr/local` | Use `sudo`, or use the Homebrew symlink path from `brew info container-compose` |
| `container compose` only shows `up`/`down` | Stale plugin dir at `/usr/local/libexec/container-plugins/compose`. Run `sudo rm -rf` that path, then recreate the symlink (see Install). Confirm with `container compose --help`. |
| Plugin installed but `compose up` rejects `:ro` | Plugin landed under Homebrew while `which container` is `/usr/local/bin/container`. Re-run `./scripts/install.sh` (it follows the active `container` binary) or set `CONTAINER_INSTALL_ROOT`. |
| `brew install container-compose` installs the wrong package | Core has a different formula. Use `brew install simplifi-ed/compose/container-compose`. |
| Kernel / runtime error on `up` | `container system kernel set --url <kernel-tarball-url>` |
| Build fails / builder unreachable | `container system start` — BuildKit (`buildkit`) must be running |
| Port already in use | Change the host port in the compose file, or `container compose down -p <project>` |
| arm64 image fails | Use images with a `linux/arm64` manifest |
| Old containers not found by `down` | Pre-label containers lack metadata. Remove with `container rm <name>` first. |

---

## Development

```bash
make build
make lint
make test    # runs compose-verify
make smoke          # end-to-end: install → up → curl → down (requires runtime)
make smoke-volumes  # install + live :ro/:z bind-mount runtime checks
make dist           # produces dist/compose/, compose-plugin.tar.gz, and .zip
```

Without Make:

```bash
swift build -c release
swift run -c release compose-verify
./scripts/build-release.sh
```

---

## Architecture

| Component | Role |
|-----------|------|
| `ComposeCore` | YAML parsing, service planning, startup/teardown, `ps`/`logs`/`top`/`exec`/`cp`/`run` |
| `compose` | CLI binary registered as a `container` plugin |
| `compose-verify` | Parser and planner tests (Command Line Tools compatible) |

---

## License

[Apache-2.0](LICENSE)
