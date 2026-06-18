# Manual test: guest clock sync after macOS wake (#102)

## Prerequisites

- macOS host with `container` 1.0.0+ and compose plugin installed
- `container system start` and kernel configured
- Skew threshold: **5 seconds** (`ClockSync.skewThresholdSeconds`)

## 1. Host sandbox — wake while long-running command

```bash
cd /path/to/project/with/compose.yaml
compose up -d
compose logs -f web   # or: compose watch
```

1. Note host time: `date`
2. Note container time: `compose exec web date`
3. Close Mac lid for ≥2 minutes
4. Wake Mac
5. Within a few seconds, re-check: `compose exec web date` vs `date`

**Pass:** container time within 5s of host (may take up to ~2s debounce after wake).

## 2. Detached `up` — eager sync on next command

```bash
compose up -d    # CLI exits
# sleep → wake
compose exec web date
```

**Pass:** first `exec` after wake triggers sync; times match within 5s.

## 3. Post-`up` one-shot

```bash
# sleep → wake with no compose CLI running
compose up -d
compose exec web date
```

**Pass:** sync runs after startup completes; times match within 5s.

## 4. No compose workloads

With no running compose-labeled containers:

```bash
compose ps -p nonexistent_project_123
```

**Pass:** no `clock_sync_started` lifecycle log lines (Unified Logging) and no sync warning on stderr.

## 5. Opt-out

```bash
COMPOSE_CLOCK_SYNC=0 compose exec web date
# or
compose exec web date --no-clock-sync
```

**Pass:** no sync attempt after wake when a long-running command would otherwise sync.

## 6. Failure is non-fatal

If sync fails (e.g. stopped container mid-sync), compose prints:

```text
Warning: Couldn't sync container clocks after wake. Run a compose command again or set COMPOSE_CLOCK_SYNC=0 if sync causes problems.
```

**Pass:** CLI exits 0; containers keep running.

## Telemetry

With Unified Logging enabled (`COMPOSE_OSLOG` unset):

```bash
log stream --predicate 'subsystem == "com.simplifi-ed.container-compose" AND eventMessage CONTAINS "clock_sync"'
```

Look for `event=clock_sync_started` and `event=clock_sync_finished` with counts only (no container IDs).
