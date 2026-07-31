# Compose XPC clients

Trusted local apps connect to compose lifecycle operations over NSXPC instead of shelling out to `container compose`.

## Service name

`com.simplifi-ed.container-compose.xpc`

## Start the listener

**Foreground (development):**

```bash
container compose xpc serve
# bootstraps a user LaunchAgent Mach listener until Ctrl+C
```

**Persistent (user LaunchAgent):**

```bash
container compose xpc install --binary /path/to/compose-xpc
container compose xpc uninstall
```

## Client allowlist

Create `~/.config/container-compose/xpc-clients.json` (mode `0600`):

```json
{
  "teamIDs": ["YOURTEAMID"],
  "clients": [
    { "teamID": "YOURTEAMID", "bundleID": "com.example.menubar-compose" }
  ]
}
```

`teamIDs` grants any app signed by that team. `clients` requires an exact **team ID + bundle ID** pair (bundle ID alone is not unique across teams).

If both arrays are empty, **no signed client is admitted** unless you set `"allowAnySigned": true` (local development only).

Unsigned clients are always rejected. Ad-hoc signed binaries need a matching `teamIDs` entry, a `clients` pair, or `allowAnySigned` for dev smoke tests.

## `up` and `scale` requests

Always pass explicit compose file paths in `files[]`. The XPC listener does not inherit your app's working directory (especially under LaunchAgent, where CWD is `/`).

For `scale`, include `scales` as a JSON object mapping service names to desired replica counts. Same delta reconcile semantics as `compose scale` on the CLI.

**`scale` request** ([`docs/examples/xpc-scale-request.json`](examples/xpc-scale-request.json)):

```json
{
  "projectName": "scale-smoke",
  "files": ["/absolute/path/to/fixtures/scale-smoke/compose.yml"],
  "scales": { "web": 3 }
}
```

**`scale` dry-run** ([`docs/examples/xpc-scale-dry-run.json`](examples/xpc-scale-dry-run.json)):

```json
{
  "projectName": "scale-smoke",
  "files": ["/absolute/path/to/fixtures/scale-smoke/compose.yml"],
  "dryRun": true,
  "scales": { "web": 3 }
}
```

**Sample client:**

```bash
# Terminal 1
container compose xpc serve

# Terminal 2 — scale web to 3 replicas
compose-xpc-sample --project scale-smoke \
  -f /absolute/path/to/fixtures/scale-smoke/compose.yml \
  --scale web=3 scale

# Dry-run
compose-xpc-sample --project scale-smoke \
  -f /absolute/path/to/fixtures/scale-smoke/compose.yml \
  --scale web=3 --dry-run scale
```

## Connect from your app

1. Sign your app (Developer ID or ad-hoc for local dev).
2. Add your team ID and/or a `(teamID, bundleID)` client entry to the allowlist.
3. Connect with `NSXPCConnection(machServiceName: "com.simplifi-ed.container-compose.xpc")` after `compose xpc serve` or `compose xpc install`.
4. Call `ComposeXPCProtocol` methods with JSON request bodies (`ComposeXPCProjectRequest`).

## Sample client

```bash
# Terminal 1
container compose xpc serve

# Terminal 2
compose-xpc-sample --mach --project demo status
```

Use `--mach` when connecting to an installed LaunchAgent.

## Security

- No secrets, env values, or staged config paths in responses.
- Compose file paths must not contain `..`.
- XPC is local-only; no network RPC.
