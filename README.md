# container compose plugin

Native [`container compose`](https://github.com/apple/container) plugin for macOS — define and run multi-container apps from `docker-compose.yml` using Apple's `ContainerCommands` API.

Maintained by [Omnivya](https://www.omnivya.fr) ([Simplifi-ED](https://github.com/Simplifi-ED)).

## Requirements

- macOS 15+ on Apple Silicon
- [container](https://github.com/apple/container) CLI 1.0.0+
- Swift 6.2+ (Command Line Tools or Xcode)

## Features (v1)

- Single compose file (`-f`, default `docker-compose.yml`)
- Project name (`-p`, default: parent directory of compose file)
- Per service: `image`, `command`, `ports`, `volumes` (bind mounts), `environment`, `container_name`, `depends_on` (list form)
- `container compose up` (detached) and `container compose down` (stop and remove)
- Dependency-aware startup: services start in `depends_on` order (start order only, not health/readiness); independent services run in parallel
- Failed `up` rolls back containers started in earlier waves
- `down` stops dependents before dependencies when the compose file is present; `-p`-only `down` stops containers in parallel
- `down` validates only the dependency graph (not `image` or other startup fields), so teardown still works if the file was edited after `up`
- Containers without a `com.docker.compose.service` label (or not listed in the compose file) stop last and may not follow `depends_on` order
- Container labels for project tracking (`com.docker.compose.project`, `com.docker.compose.service`)

Not supported yet: long-form `depends_on` with health conditions, networks, named volumes, volume drivers, read-only mounts (`:ro`), `build`, profiles, multi-file merge.

### Container labels

Each container started by `compose up` gets two metadata labels:

| Label | Value |
|-------|-------|
| `com.docker.compose.project` | Project name (`-p`, or the compose file's parent directory) |
| `com.docker.compose.service` | Service name from the compose file |

`compose down` finds containers by `com.docker.compose.project`. Use the same `-p` value you used with `up`. With `-p`, the compose file does not need to exist. Services removed from the compose file are still stopped if they carry the project label.

If the compose file has a broken dependency graph (circular or unknown `depends_on` references), `down` cannot compute shutdown order. Tear down in parallel with `compose down -p <project>` and no `-f`, or fix the graph first.

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
