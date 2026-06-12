#!/usr/bin/env bash
# Live runtime smoke for bind-mount volume options (:ro, :z, :ro,z).
# Exercises container run -v passthrough and compose up/exec with fixtures/volume-mount-smoke/.
# Invoked by make smoke-volumes and scripts/smoke-test.sh (after plugin install).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/fixtures/volume-mount-smoke/compose.yml"
PROJECT_NAME="volume-mount-smoke"
IMAGE="docker.io/library/alpine:3.20"
DATA_DIR="$(mktemp -d)"

cleanup() {
  container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" 2>/dev/null || true
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: volume mount smoke requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

echo "==> Smoke: container run with :ro,z"
container run --rm -v "${DATA_DIR}:/mnt:ro,z" "$IMAGE" ls /mnt

echo "==> Smoke: :ro,z rejects writes"
if container run --rm -v "${DATA_DIR}:/mnt:ro,z" "$IMAGE" touch /mnt/readonly-test 2>/dev/null; then
  echo "FAIL: touch succeeded on :ro,z mount" >&2
  exit 1
fi
echo "PASS: :ro,z mount is read-only at runtime"

echo "==> Smoke: container run with :z"
container run --rm -v "${DATA_DIR}:/mnt:z" "$IMAGE" touch /mnt/z-write-test
if [[ ! -f "${DATA_DIR}/z-write-test" ]]; then
  echo "FAIL: :z mount did not propagate host write" >&2
  exit 1
fi
echo "PASS: :z mount allows write at runtime"

echo "==> Smoke: compose up with :ro,z bind mount"
container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --progress none

if ! container compose ps -f "$COMPOSE_FILE" -p "$PROJECT_NAME" | grep -q "web"; then
  echo "FAIL: compose ps did not list web service after :ro,z up" >&2
  exit 1
fi

if container compose exec -f "$COMPOSE_FILE" -p "$PROJECT_NAME" web touch /mnt/data/compose-write-test 2>/dev/null; then
  echo "FAIL: compose exec wrote to :ro,z mount" >&2
  exit 1
fi
echo "PASS: compose :ro,z service mount is read-only at runtime"

echo "PASS: volume mount option runtime smoke complete"
