#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORK_DIR=""
cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    container compose -f "$WORK_DIR/docker-compose.yml" -p bindmounttest down 2>/dev/null || true
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

echo "==> Building and installing plugin..."
bash "$ROOT_DIR/scripts/install-plugin.sh"

echo "==> Preparing bind-mount workspace..."
WORK_DIR="$(mktemp -d)"
mkdir -p "$WORK_DIR/data"
echo "hello from host" >"$WORK_DIR/data/hello.txt"

cat >"$WORK_DIR/docker-compose.yml" <<'EOF'
services:
  web:
    image: docker.io/library/alpine:latest
    command: ["sleep", "600"]
    volumes:
      - "./data:/mnt/data"
EOF

echo "==> Starting compose project from a different working directory..."
OTHER_DIR="$(mktemp -d)"
(
  cd "$OTHER_DIR"
  container compose -f "$WORK_DIR/docker-compose.yml" -p bindmounttest up
)

CONTAINER_NAME="bindmounttest_web"
echo "==> Verifying mounted file inside container..."
CONTENT="$(container exec "$CONTAINER_NAME" cat /mnt/data/hello.txt)"
if [[ "$CONTENT" != "hello from host" ]]; then
  echo "FAIL: expected 'hello from host', got '$CONTENT'" >&2
  exit 1
fi

rm -rf "$OTHER_DIR"

echo "==> Stopping compose project..."
container compose -f "$WORK_DIR/docker-compose.yml" -p bindmounttest down

echo "PASS: bind mount verified"
