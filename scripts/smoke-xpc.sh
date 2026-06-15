#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "skip: smoke-xpc requires arm64" >&2
  exit 0
fi

swift build -c release --product compose --product compose-xpc --product compose-xpc-sample >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
COMPOSE="${BIN_DIR}/compose"
SAMPLE="${BIN_DIR}/compose-xpc-sample"
XPC="${BIN_DIR}/compose-xpc"

for binary in "$COMPOSE" "$SAMPLE" "$XPC"; do
  if [[ ! -x "$binary" ]]; then
    echo "error: missing $binary" >&2
    exit 1
  fi
done

ALLOWLIST="${HOME}/.config/container-compose/xpc-clients.json"
mkdir -p "$(dirname "$ALLOWLIST")"
ALLOWLIST_BACKUP="$(mktemp)"
ALLOWLIST_HAD_ORIGINAL=0
if [[ -f "$ALLOWLIST" ]]; then
  cp "$ALLOWLIST" "$ALLOWLIST_BACKUP"
  ALLOWLIST_HAD_ORIGINAL=1
fi
echo '{"teamIDs":[],"clients":[],"allowAnySigned":true}' >"$ALLOWLIST"
chmod 600 "$ALLOWLIST"

"$COMPOSE" xpc uninstall >/dev/null 2>&1 || true
"$COMPOSE" xpc serve --binary "$XPC" &
SERVE_PID=$!
trap '
  "$COMPOSE" xpc uninstall >/dev/null 2>&1 || true
  kill "$SERVE_PID" 2>/dev/null || true
  if [[ "$ALLOWLIST_HAD_ORIGINAL" -eq 1 ]]; then
    cp "$ALLOWLIST_BACKUP" "$ALLOWLIST"
  else
    rm -f "$ALLOWLIST"
  fi
  rm -f "$ALLOWLIST_BACKUP"
' EXIT
sleep 2

OUTPUT="$("$SAMPLE" --mach --project demo status 2>&1)" || true
echo "$OUTPUT"
echo "$OUTPUT" | grep -Eq '"exitStatus"[[:space:]]*:[[:space:]]*0' || {
  echo "error: expected successful JSON status response" >&2
  exit 1
}

echo "smoke-xpc: ok"
