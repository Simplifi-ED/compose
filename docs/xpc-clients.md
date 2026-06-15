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
  "bundleIDs": ["com.example.menubar-compose"]
}
```

If both arrays are empty, **no signed client is admitted** unless you set `"allowAnySigned": true` (local development only).

Unsigned clients are always rejected. Ad-hoc signed binaries need a matching team or bundle ID on the allowlist, or `allowAnySigned` for dev smoke tests.

## `up` requests

Always pass explicit compose file paths in `files[]`. The XPC listener does not inherit your app's working directory (especially under LaunchAgent, where CWD is `/`).

## Connect from your app

1. Sign your app (Developer ID or ad-hoc for local dev).
2. Add your team ID or bundle ID to the allowlist.
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
