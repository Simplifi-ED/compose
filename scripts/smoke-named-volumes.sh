#!/usr/bin/env bash
# Live runtime smoke for compose named volumes: create, mount, persist across
# down, and removal on down -v.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/fixtures/volume-named-smoke/compose.yml"
PROJECT_NAME="volume-named-smoke"
VOLUME_NAME="${PROJECT_NAME}_appdata"
MARKER="named-volume-smoke-$(date +%s)"

cleanup() {
  container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" -v 2>/dev/null || true
  container volume rm "$VOLUME_NAME" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: named volume smoke requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

echo "==> Smoke: compose up with named volume"
container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --progress none

echo "==> Smoke: project volume exists"
if ! container volume ls --quiet | grep -qx "$VOLUME_NAME"; then
  echo "FAIL: volume $VOLUME_NAME not found after up" >&2
  exit 1
fi

echo "==> Smoke: write data into named volume"
container compose exec -f "$COMPOSE_FILE" -p "$PROJECT_NAME" app sh -c "echo '$MARKER' > /data/marker.txt"

echo "==> Smoke: down without -v keeps volume"
container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME"
if ! container volume ls --quiet | grep -qx "$VOLUME_NAME"; then
  echo "FAIL: volume removed by down without -v" >&2
  exit 1
fi

echo "==> Smoke: up again and verify persistence"
container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --progress none
READ_BACK="$(container compose exec -f "$COMPOSE_FILE" -p "$PROJECT_NAME" app cat /data/marker.txt | tr -d '\r')"
if [[ "$READ_BACK" != "$MARKER" ]]; then
  echo "FAIL: expected marker '$MARKER', got '$READ_BACK'" >&2
  exit 1
fi

echo "==> Smoke: down -v removes named volume"
container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" -v
if container volume ls --quiet | grep -qx "$VOLUME_NAME"; then
  echo "FAIL: volume still present after down -v" >&2
  exit 1
fi

echo "PASS: named volume smoke"
