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
- Per service: `image`, `command`, `ports`, `environment`, `container_name`
- `container compose up` (detached) and `container compose down` (stop and remove)
- Parallel service orchestration via Swift structured concurrency

Not supported yet: `depends_on`, networks, volumes, `build`, profiles, multi-file merge.

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
