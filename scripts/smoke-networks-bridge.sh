#!/usr/bin/env bash
# Live runtime smoke for compose bridged networks (requires upstream bridge create).
# Skips gracefully when container 1.0.0 cannot create bridge networks yet.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/fixtures/network-bridge-smoke/compose.yml"
PROJECT_NAME="network-bridge-smoke"
NETWORK_NAME="${PROJECT_NAME}_backend"

cleanup() {
  container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" 2>/dev/null || true
  container network rm "$NETWORK_NAME" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: bridge network smoke requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo "error: bridged networks require macOS 26 or newer" >&2
  exit 1
fi

echo "==> Smoke: compose up with bridged backend network"
set +e
UP_OUTPUT="$(container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --progress none 2>&1)"
UP_STATUS=$?
set -e
if [[ $UP_STATUS -ne 0 ]]; then
  if echo "$UP_OUTPUT" | grep -q "Bridged network.*isn't supported by container"; then
    echo "SKIP: upstream bridge network create not available in this container build"
    echo "See docs/bridged-network-spike.md"
    exit 0
  fi
  echo "$UP_OUTPUT" >&2
  exit $UP_STATUS
fi

echo "==> Smoke: project network exists"
if ! container network ls --quiet | grep -qx "$NETWORK_NAME"; then
  echo "FAIL: network $NETWORK_NAME not found after up" >&2
  exit 1
fi
echo "PASS: $NETWORK_NAME created"

MODE="$(container network inspect "$NETWORK_NAME" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['configuration'].get('mode',''))" 2>/dev/null || true)"
if [[ "$MODE" != "bridge" ]]; then
  echo "SKIP: network mode is '$MODE' (expected bridge when upstream ships)"
  exit 0
fi
echo "PASS: network mode is bridge"

echo "==> Smoke: compose ps shows routable IP"
PS_OUT="$(container compose ps -f "$COMPOSE_FILE" -p "$PROJECT_NAME")"
echo "$PS_OUT"
SERVER_IP="$(echo "$PS_OUT" | awk '/server/ && /running/ {
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit }
  }
}')"
if [[ -z "$SERVER_IP" ]]; then
  echo "FAIL: couldn't read server IP from compose ps" >&2
  exit 1
fi
echo "PASS: server IP $SERVER_IP"

echo "==> Smoke: host reachability to bridge IP"
if ! ping -c 1 -W 5 "$SERVER_IP" >/dev/null 2>&1; then
  echo "FAIL: host could not ping $SERVER_IP" >&2
  exit 1
fi
echo "PASS: host ping $SERVER_IP"

echo "==> Smoke: compose down removes the network"
container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME"
if container network ls --quiet | grep -qx "$NETWORK_NAME"; then
  echo "FAIL: network $NETWORK_NAME still exists after down" >&2
  exit 1
fi
echo "PASS: $NETWORK_NAME removed on down"

echo "PASS: compose bridged networks runtime smoke complete"
