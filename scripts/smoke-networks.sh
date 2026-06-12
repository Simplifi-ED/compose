#!/usr/bin/env bash
# Live runtime smoke for compose networks: project-scoped subnet creation,
# container-name DNS between two services, and network removal on down.
# DNS resolves container names ({project}_{service}_{index}), not Docker-style
# service shorthand. Custom networks require macOS 26 or newer.
# Invoked by make smoke-networks (after plugin install).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/fixtures/network-smoke/compose.yml"
PROJECT_NAME="network-smoke"
NETWORK_NAME="${PROJECT_NAME}_backend"

cleanup() {
  container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" 2>/dev/null || true
  container network rm "$NETWORK_NAME" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: network smoke requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo "error: custom networks require macOS 26 or newer" >&2
  exit 1
fi

echo "==> Smoke: compose up with shared backend network"
container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --progress none

echo "==> Smoke: project network exists"
if ! container network ls --quiet | grep -qx "$NETWORK_NAME"; then
  echo "FAIL: network $NETWORK_NAME not found after up" >&2
  exit 1
fi
echo "PASS: $NETWORK_NAME created"

echo "==> Smoke: container-name DNS across the network"
if ! container compose exec -f "$COMPOSE_FILE" -p "$PROJECT_NAME" client \
  ping -c 1 -W 5 "${PROJECT_NAME}_server_1" >/dev/null; then
  echo "FAIL: client could not reach ${PROJECT_NAME}_server_1 by container name" >&2
  exit 1
fi
echo "PASS: ${PROJECT_NAME}_server_1 resolves from client"

echo "==> Smoke: compose down removes the network"
container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME"
if container network ls --quiet | grep -qx "$NETWORK_NAME"; then
  echo "FAIL: network $NETWORK_NAME still exists after down" >&2
  exit 1
fi
echo "PASS: $NETWORK_NAME removed on down"

echo "PASS: compose networks runtime smoke complete"
