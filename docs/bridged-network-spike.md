# Bridged network spike (#109)

Verified against pinned deps: `container` 1.0.0, `containerization` 0.33.3. Host: macOS 26.5.1, `container` CLI 1.0.0 (ee848e3).

## Problem

NAT vmnet subnets (`192.168.64.0/24`, etc.) give containers isolated addresses reachable from the host but not LAN-routable without port mapping. Bridge mode should assign per-container IPs on the physical LAN (DHCP/mDNS) so services are reachable without `ports:` and host DNS can map hostnames directly to container addresses.

## Upstream API (container 1.0.0)

| Primitive | Status | Location |
|-----------|--------|----------|
| `NetworkMode` | `.nat`, `.hostOnly` only — **no `.bridge`** | `ContainerResource/Network/NetworkMode.swift` |
| `NetworkConfiguration` | `mode`, `plugin`, `ipv4Subnet`, `options` | `ContainerResource/Network/NetworkConfiguration.swift` |
| `container network create` | `--internal` → `hostOnly`; default `nat` | `ContainerCommands/Network/NetworkCreate.swift` |
| `ContainerSnapshot.networks` | `[Attachment]` with `ipv4Address`, `ipv4Gateway` | `ContainerResource/Container/ContainerSnapshot.swift` |
| `container inspect` | Runtime IPs under `status.networks[]` | CLI JSON |

`--option mode=bridge` on `container network create` is stored in `configuration.options` but **`configuration.mode` stays `nat`** — not functional bridge.

### In-flight upstream

| PR | Notes |
|----|-------|
| [apple/container#1463](https://github.com/apple/container/pull/1463) | `NetworkMode.bridge`, `--bridge` on network create, DHCP via kernel IP_PNP |
| [apple/container#1622](https://github.com/apple/container/pull/1622) | Helper-based bridging (dev without entitlement) |
| [apple/container#1661](https://github.com/apple/container/pull/1661) | `vmnet-helper` plugin approach |

**Compose v1 gate:** `NetworkRunner` throws `ComposeError.bridgeNetworksUnsupported` until a released `container` dependency exposes bridge create. Parser, planning, IP discovery, `ps`, and host-DNS prep ship behind that runtime gate.

## IP discovery (available today)

```
ContainerClient.get(id) / list(filters:)
  → ContainerSnapshot.networks: [Attachment]
  → attachment.ipv4Address  // CIDRv4, e.g. "192.168.64.32/24"
```

`container inspect <id>` mirrors this under `status.networks`.

**NAT baseline (verified):** host can `ping` vmnet IP immediately after start (no retry needed on default network).

**Bridge (expected):** DHCP may complete slightly after container `running`; compose uses a short post-start retry (`ContainerNetworkDiscovery`, 3× 500ms) — ponytail ceiling; upgrade path = upstream event/stream when bridge lands.

## Host reachability

| Mode | Subnet | Host ping without `ports:` | LAN / mDNS |
|------|--------|----------------------------|------------|
| NAT (vmnet shared) | `192.168.64.0/24` (typical) | Yes (host ↔ vmnet) | No |
| Bridge (target) | Physical LAN DHCP | Yes | Yes |

**Ports interaction:** On bridged services, `ports:` host binds are redundant for direct IP access; compose emits a **config warning** when both bridge network membership and static host `ports:` are set. NAT behavior unchanged.

## Entitlements

Bridge via `VZBridgedNetworkDeviceAttachment` requires `com.apple.vm.networking` (Apple-provisioned profile). See [container#1463](https://github.com/apple/container/pull/1463#issuecomment-2841234567) — local dev may need `ENABLE_BRIDGE_NETWORKING` or helper-based path.

Compose release [`entitlements.plist`](../entitlements.plist) stays `hypervisor` + `network.client` only; bridge execution is delegated to `container` / `container-runtime-linux`. Re-audit before claiming bridge in release notes.

## Machine mode

**Out of scope v1.** `NetworkPlanning` rejects bridge networks with `--machine` (same posture as `--host-dns`). In-VM bridge depends on upstream machine networking.

## Compose YAML schema (v1)

```yaml
networks:
  backend:
    x-compose:
      network:
        mode: bridge   # omit or "nat" → current NAT behavior
```

Sugar: `driver: bridge` parses as bridge mode; other `driver` values still warn as unsupported.

## Host DNS coordination

| Network mode | Target IP | Install timing | Published port required |
|--------------|-----------|----------------|----------------------|
| NAT | `127.0.0.1` | Before startup | Yes |
| Bridge | Container `Attachment` IPv4 | After startup (+ retry) | No |

## Manual repro (NAT IP discovery — works today)

```bash
container system start
container run -d --name bridge-spike --network default docker.io/library/alpine:3.20 sleep 300
container inspect bridge-spike | jq '.[0].status.networks[0].ipv4Address'
ping -c1 "$(container inspect bridge-spike | jq -r '.[0].status.networks[0].ipv4Address' | cut -d/ -f1)"
container rm -f bridge-spike
```

## Manual repro (bridge — blocked until upstream)

```bash
# After container ships bridge create:
container network create --bridge mybridge
container compose up -f fixtures/network-bridge-smoke/compose.yml -p bridge-smoke
container compose ps   # IP column
ping -c1 "$(container compose ps -q | head -1)"  # or read IP from ps
```

## Risks

- Upstream bridge not in 1.0.0: runtime gate + clear error with upstream link.
- DHCP race: bounded retry; warn if IP still empty.
- Double admin prompt for `--host-dns` mixed NAT+bridge: loopback pre-start, bridge refresh post-start.
