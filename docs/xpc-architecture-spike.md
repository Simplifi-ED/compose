# XPC architecture spike (#92)

Scope: additive local automation API for compose lifecycle. Issue #39 (App Sandbox) deferred.

## Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Listener placement | **Separate `compose-xpc` binary** + **`compose xpc serve`** reuses same listener code | CLI plugin stays one-shot; long-lived Mach listener is a sibling binary in `dist/compose/bin/` |
| Foreground dev | **`compose xpc serve`** bootstraps a user LaunchAgent, blocks until Ctrl+C, then bootouts | NSXPCListenerEndpoint cannot be archived to disk; Mach + launchd only |
| Persistent service | **Opt-in** `compose xpc install` installs user LaunchAgent plist with `MachServices` → `com.simplifi-ed.container-compose.xpc` | Not wired into `install.sh` until stable |
| Mach service name | `com.simplifi-ed.container-compose.xpc` | Fixed constant in `ComposeXPCConstants` |
| App Sandbox | **v1: unsandboxed server and clients** (matches `entitlements.plist`) | Sandboxed menubar apps can connect to unsandboxed helper later via Mach + client audit token |
| `network.server` | **Not required** | Mach XPC is not TCP |
| Ad-hoc server + SecCode clients | **Works for validity check**; team/bundle allowlist is config-driven | Empty allowlist rejects all clients unless `"allowAnySigned": true` |

## Layout

```text
dist/compose/bin/compose          # existing CLI
dist/compose/bin/compose-xpc      # Mach / foreground listener
dist/compose/bin/compose-xpc-sample
dist/compose/LaunchAgents/com.simplifi-ed.container-compose.xpc.plist
```

## Smoke (local)

```bash
# Terminal 1 — foreground
swift run -c release compose xpc serve

# Terminal 2 — sample client (ad-hoc signed with same identity)
swift run -c release compose-xpc-sample status --project demo

# LaunchAgent (optional)
swift run -c release compose xpc install
swift run -c release compose-xpc-sample status --project demo --mach
```

## Future (#39)

Sandboxed client → unsandboxed `compose-xpc` helper; may need `com.apple.security.application-groups` or Mach lookup entitlements on the client only.
