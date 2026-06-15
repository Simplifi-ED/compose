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
| `events` | Stream container start/die events (foreground polling). |
| `exec SERVICE CMD` | Run a command inside a running service container. |
| `cp SRC DEST` | Copy files between the host and a running service container. |
| `run SERVICE [CMD]` | Start a one-off container from a service definition. |
| `top` | Live CPU/memory/network/block I/O stats (Docker `compose stats` equivalent). |
| `stats` | Alias for `top`. |
| `watch` | Sync local file changes into running containers. |
| `config` | Print the resolved compose config without starting anything. |
| `doctor` | Run pre-flight checks for container and compose plugin readiness. |
| `save` | Export service images and resolved compose YAML to a portable archive. |
| `load` | Import images from a stack archive into the local image store. |

Supported on `up`, `down`, `ps`, `logs`, `events`, `exec`, and `cp`:

```bash
container compose up --machine dev -f compose.yaml
```

`watch`, `run`, `top`, `stats`, `config`, `save`, and `load` reject `--machine`.

### Top / Stats (`compose top`, `compose stats`)

`stats` is an alias for `top` — same flags, output, and behavior. Streams live resource usage for project containers (Docker Compose `stats` equivalent).

Default refresh interval is **2 seconds** (`--interval`, minimum 1). Interactive TTY mode redraws the table in place; plain mode prints a new table each tick; **piped** output (stdout not a TTY) prints a **single snapshot** (two internal samples spaced by `--interval` for CPU %).

```bash
container compose stats -p demo
container compose top -p demo --interval 3 web db
```

| Column | Meaning |
|--------|---------|
| NAME | Container name (`{project}_{service}_{index}`) |
| SERVICE | Compose service name |
| CPU % | CPU usage since the previous sample |
| MEM USAGE / LIMIT | Memory used / cgroup limit |
| NET RX/TX | Network bytes received / transmitted |
| BLOCK I/O | Block device bytes read / written |
| PIDS | Process count in the container |

Stopped containers show `--` for resource columns. Ctrl+C ends the stream without stopping containers.

### Host DNS (`up --host-dns`)

Maps declared service hostnames to `127.0.0.1` on the **macOS host** so browsers can reach published ports by name (e.g. `http://web.demo.local:8080`). In-container DNS from compose `networks:` is separate — this feature does not change VM/container resolver behavior.

Declare hostnames per service:

```yaml
services:
  web:
    image: nginx:1.27.3
    ports:
      - "8080:80"
    x-compose:
      hosts:
        - web.demo.local
```

Opt in on startup (compose itself stays unprivileged; macOS prompts for `/etc/hosts` access only):

```bash
container compose up --host-dns
```

**Do not** run `sudo container compose up` — elevation applies only to the hosts-file write. Ownership is tracked at `~/.config/container-compose/<project>/host-dns.json`.

`container compose down` removes the project's delimited block from `/etc/hosts` when possible. If the admin prompt is cancelled, stderr prints the exact block marker and ownership path for manual cleanup.

Manual acceptance:

```bash
container compose up --host-dns -f compose.yaml
# approve admin prompt
ping -c1 web.demo.local
container compose down -f compose.yaml
# approve prompt if needed; ping should fail afterward
```

Prefer `.local` / `.test` suffixes. Non-dev hostnames emit a warning because mapping affects the whole machine while the project is up.

### Events (`compose events`)

Streams **start** and **die** lifecycle lines for project containers using a **foreground polling loop** (default **1.5s** interval). There is no background daemon — polling runs only while the command is active.

Without `--follow`, prints a **one-shot snapshot** of currently running containers. Use `--follow` for a continuous stream until interrupted.

```bash
container compose events -p demo --follow
container compose events -f compose.yaml web db --follow --timeout 120
```

Output shape:

```text
[2026-06-13T12:00:00.000Z] container start demo_web_1 (demo_web_1)
[2026-06-13T12:00:03.500Z] container die demo_web_1 (demo_web_1)
```

**Limitations:** polling is not a native engine event stream. Containers that start and stop in **under ~1 second** may never appear in a list tick and will not emit events. Worst-case detection latency is roughly one poll interval. Event types **oom** and **health** are not available in container 1.0.0.

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

If `COMPOSE_PROFILES` is exported in your shell, `ps`, `logs`, `top`, `stats`, `config`, `watch`, and `down` need a compose file to apply profile filtering—even with `-p` only. Use `COMPOSE_PROFILES=*` (or `down --profile "*"`) to stop every project container without a compose file.

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

Process environment (not compose `${}` substitution): `COMPOSE_FILE`, `COMPOSE_PROJECT_NAME`, `COMPOSE_PROFILES` (comma-separated; merged with `--profile`), and `COMPOSE_OSLOG` (set to `0` to disable Unified Logging telemetry).

### Unified Logging

Orchestration events (container start/stop, startup waves, rollbacks, builds, volumes, networks, signals) are emitted to macOS Unified Logging under subsystem `com.simplifi-ed.container-compose`. Filter in Console.app or from the terminal:

```bash
log stream --predicate 'subsystem == "com.simplifi-ed.container-compose" AND category == "orchestration"'
log show --last 5m --info --predicate 'subsystem == "com.simplifi-ed.container-compose" AND eventMessage CONTAINS "rollback"'
```

Categories: `orchestration`, `lifecycle`, `signals`, `volumes`, `networks`, `build`.

Disable telemetry with `COMPOSE_OSLOG=0` or `--no-oslog` on `up`, `down`, `run`, and other commands that support the flag. `compose up --dry-run` does not emit lifecycle execution events. Secrets, environment values, and build args are never written to the unified log.

### Instruments signposts

Startup hot paths emit interval signposts under the same subsystem for profiling in Instruments (Points of Interest template):

| Signpost | When |
|----------|------|
| `compose.parse` | YAML load, merge, include, substitution |
| `compose.plan` | Dependency layers, replica expansion, validation |
| `compose.network` | Project network create before waves |
| `compose.volume` | Project volume create before waves |
| `compose.execute.wave` | Each startup wave (parallel container batch) |
| `compose.discovery` | Orchestration discovery via `ContainerDiscovery.containers` (`up`/`down` orphan checks; not `ps`/`logs`/`events` polling) |

Workflow:

1. Open **Instruments** → **Points of Interest** template.
2. Filter subsystem `com.simplifi-ed.container-compose`.
3. Run `compose up` in a terminal; nested intervals appear for parse → plan → network/volume → waves.

Signposts use the same opt-out as unified logs (`COMPOSE_OSLOG=0`, `--no-oslog`, `--dry-run`). For log lines (not intervals), use the Logging template or:

```bash
log stream --predicate 'subsystem == "com.simplifi-ed.container-compose" AND category == "orchestration"'
```

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

**Limits:** Dockerfile size capped at 16 KiB by the Apple build engine; cross-arch `build.platform` is not supported (service `platform` applies to `container run` only); no registry push; `develop.watch` `rebuild` is not supported yet. Build context paths must stay inside the compose file directory (absolute paths are allowed when they still resolve within it).

### Rosetta / `platform` (Apple Silicon)

Service-level `platform: linux/amd64` (or `linux/x86_64`, normalized to `linux/amd64`) runs x86_64 Linux images via Rosetta 2 on Apple Silicon. Compose maps it to `container run --platform linux/amd64`; the engine enables Rosetta automatically.

- **`compose config`** prints the normalized `platform` field.
- **`compose doctor`** reports Rosetta installation (advisory); `up`/`run` fail at plan time when `platform: linux/amd64` is set and Rosetta is missing.
- **`build:` + `platform`:** image builds still target native arm64; compose warns that `platform` applies to container run only.
- **`--machine`:** not supported when a service declares `platform`.
- **Compose spec:** only per-service `platform` is supported (no file-level default).

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

# Reclaim APFS sparse backing space (opt-in; APFS hosts only)
container compose down --trim
container compose down -v --trim
```

`down -v` removes **relative** bind-mount paths (e.g. `./data:/app`) and project-scoped named volumes created by compose. Absolute bind-mount paths are not touched.

### APFS sparse trim (`--trim`)

Opt-in guest `fstrim` during teardown to return freed blocks from sparse ext4 disk images to the host APFS store. Trim runs **inside Linux guests** (container rootfs, named volumes, or machine guest) — compose does not run `fstrim` on the macOS host root and never prompts for `sudo`.

| Flag combo | What gets trimmed |
|------------|-------------------|
| `down --trim` | Project container root filesystems (before delete) |
| `down -v --trim` | Containers + project-labeled named volumes (volumes via privileged helper) |
| `down --machine NAME --trim` | Same as above, plus machine guest filesystem after project cleanup |

## Requirements and limits

- Host backing store must be **APFS** (skipped with a warning on ExFAT, external NTFS, etc.)
- Named-volume trim uses a short-lived privileged helper container (`CAP_SYS_ADMIN`)
- Container rootfs trim succeeds only when guest `fstrim` is permitted (typically requires `cap_add: [SYS_ADMIN]` on the service, or use `down -v --trim` for named volumes)
- Trim failures emit **warnings**; `down` still completes
- No new `compose volume prune` subcommand — volume trim hooks the existing `down -v` removal path

## Manual verification (Tier B — guest reclaim confirmed)

```bash
# Named volume on APFS host
container compose up -d -f compose.yaml
container compose exec SERVICE sh -c 'dd if=/dev/zero of=/mount/big bs=1M count=100; rm /mount/big'
du -k "$HOME/Library/Application Support/com.apple.container/volumes/PROJECT_VOLUME/volume.img"
container compose down -v --trim
du -k "$HOME/Library/Application Support/com.apple.container/volumes/PROJECT_VOLUME/volume.img"  # path gone after -v
```

Compare allocated size (`du -k`) on the host `.img` / `rootfs.ext4` before and after when the volume is not removed. Host shrink may require guest trim only (Tier B); full host byte drop depends on engine/APFS behavior (Tier A).

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

## Security & distribution

Release builds of `bin/compose` are **ad-hoc signed** (`codesign -s -`) with embedded entitlements from [`entitlements.plist`](entitlements.plist):

- `com.apple.security.hypervisor` — Virtualization.framework path used by the `container` API in application-sandbox mode
- `com.apple.security.network.client` — outbound API traffic to the `container` daemon

**App Sandbox is not enabled in v1.** The release plist does not include `com.apple.security.app-sandbox`. Capability entitlements alone do not isolate the process; they document least-privilege intent for a future Developer ID signing pipeline.

**Not included (by design):**

- `com.apple.security.network.server` — compose does not bind TCP listeners; port publishing is handled by the `container` runtime (local Mach XPC uses `compose-xpc`; see [docs/xpc-clients.md](docs/xpc-clients.md))
- `com.apple.security.files.user-selected.read-write` — powerbox access only; does not cover headless CLI paths or bind mounts

For the full entitlement matrix, sandbox blocker register, and spike results, see [`docs/entitlements-audit.md`](docs/entitlements-audit.md). Opt-in sandbox spike: `./scripts/smoke-sandbox-entitlements.sh`.

**Ad-hoc vs Developer ID:** GitHub releases and the Homebrew tap ship ad-hoc signed binaries. Corporate Developer ID signing and notarization are follow-up work (out of scope for the current release pipeline).

**Verify a local release build:**

```bash
make verify-codesign
codesign -d --entitlements :- dist/compose/bin/compose
```

Embedded entitlements are not the same as notarization. Gatekeeper may still quarantine downloaded artifacts — see Troubleshooting.

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

## Doctor

`container compose doctor` runs **non-mutating** pre-flight checks before you hit failures during `up` or `down`. It does not change compose projects, system configuration, or auto-repair with `sudo`. Some probes may run subprocesses or a cached-image container run; doctor never pulls images automatically.

```bash
container compose doctor
container compose doctor --quiet   # exit code only (0 = all critical checks passed)
```

Example output:

```text
✅ Host architecture
   Running on Apple Silicon (arm64).

❌ Container API server
   Container API is not reachable.
   → container system start

⏭ Host kernel configuration
   Skipped because the container API is not reachable.

Summary: 6 passed, 1 warnings, 1 critical, 2 skipped
```

**Checks:** Apple Silicon, disk space (temp + `~/.config/container-compose`), Rosetta 2 (advisory), plugin bundle files, plugin install path writability (advisory), `container` CLI on PATH and version, API reachability, plugin subcommand registration (from [`ComposeSubcommandRegistry`](Sources/ComposeCore/Commands/ComposeSubcommandRegistry.swift)), local cache of the kernel probe image, and kernel/runtime verification when the probe image is already cached.

**Skip chain:** when an upstream check fails, downstream runtime checks are marked skipped instead of emitting duplicate errors. For example, a missing `container` CLI skips API and kernel checks; a down API server skips plugin discovery and kernel checks.

**Kernel probe:** there is no non-invasive `container system kernel status` in container 1.0.0. When the API is reachable, doctor warns if `docker.io/library/busybox:1.36.1` is not cached locally and skips the kernel run probe until you pull it manually (`container image pull docker.io/library/busybox:1.36.1`). Registry/network failures are reported separately from kernel misconfiguration.

**CI:** [`compose-verify`](Sources/compose-verify/) tests doctor report formatting and skip logic without a live container runtime. GitHub Actions does not run `compose doctor` by default. A full doctor run requires a local `container` install and running API (`container system start`).

---

## Development

```bash
make build
make lint
make test    # runs compose-verify
make smoke          # end-to-end: install → up → curl → down (requires runtime)
make smoke-volumes  # install + live :ro/:z bind-mount runtime checks
make dist           # produces dist/compose/, compose-plugin.tar.gz, and .zip
make verify-codesign   # release build + entitlements gate (see entitlements.plist)
```

Without Make:

```bash
swift build -c release
swift run -c release compose-verify
./scripts/build-release.sh
./scripts/verify-codesign.sh dist/compose/bin/compose entitlements.plist
./scripts/smoke-sandbox-entitlements.sh   # opt-in app-sandbox spike (not CI)
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
