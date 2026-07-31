# Compose scale examples

Runnable fixtures and scripts for `compose scale` and external autoscaling controllers.

## Fixture

[`fixtures/scale-smoke/compose.yml`](../../fixtures/scale-smoke/compose.yml) — `web` scales on container-only port `80` with CPU/memory limits; `api` has static host port `18080:80` (max one replica).

## Manual scale workflow

```bash
# From repo root (plugin installed)
PROJECT=scale-smoke
FILE=fixtures/scale-smoke/compose.yml

container compose up -f "$FILE" -p "$PROJECT"

container compose ps -f "$FILE" -p "$PROJECT"
# demo_web_1, demo_web_2 running

# Delta reconcile: start web_3 only (web_1 and web_2 stay running)
container compose scale -f "$FILE" -p "$PROJECT" --scale web=3

container compose scale -f "$FILE" -p "$PROJECT" --scale web=1
# stops demo_web_2 and demo_web_3; demo_web_1 keeps running

# Static host port — scale above 1 fails at plan time
container compose scale -f "$FILE" -p "$PROJECT" --scale api=2
# error: static host port blocks scaling

container compose down -f "$FILE" -p "$PROJECT"
```

Compare with `compose up --scale web=3` after `up` — that tears down and recreates every `web` replica.

## Dry run

```bash
container compose scale -f fixtures/scale-smoke/compose.yml -p scale-smoke \
  --scale web=5 --dry-run
```

## External controller (example script)

[`scale-external-controller.sh`](scale-external-controller.sh) polls `compose stats` in pipe mode and calls `compose scale` when average memory exceeds a threshold. **Illustration only** — no cooldowns, min/max bounds, or CPU normalization.

```bash
./docs/examples/scale-external-controller.sh fixtures/scale-smoke/compose.yml scale-smoke web 70
```

## XPC `scale`

Request body ([`xpc-scale-request.json`](xpc-scale-request.json)):

```json
{
  "projectName": "scale-smoke",
  "files": ["/absolute/path/to/fixtures/scale-smoke/compose.yml"],
  "scales": { "web": 3 }
}
```

```bash
# Terminal 1
container compose xpc serve

```bash
# Terminal 1
container compose xpc serve

# Terminal 2
compose-xpc-sample --project scale-smoke \
  -f "$(pwd)/fixtures/scale-smoke/compose.yml" \
  --scale web=3 scale
```
```

See [`xpc-clients.md`](../xpc-clients.md) for allowlist and Mach service setup.

## Live smoke

```bash
make smoke-scale
# or: ./scripts/smoke-scale.sh
```
