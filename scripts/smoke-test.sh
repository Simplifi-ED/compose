#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="$ROOT_DIR/fixtures/minimal-compose.yml"
PROJECT_NAME="smoke"
HOST_PORT="18080"
CURL_URL="http://127.0.0.1:${HOST_PORT}/"
MAX_ATTEMPTS=30
SLEEP_SECONDS=2

cleanup() {
  container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: smoke test requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl not found in PATH" >&2
  exit 1
fi

echo "==> Installing plugin..."
bash "$ROOT_DIR/scripts/install.sh"

echo "==> Starting container system..."
if ! container system start; then
  echo "warning: container system start did not complete successfully" >&2
fi

if [[ "${SKIP_KERNEL_CHECK:-0}" != "1" ]]; then
  echo "==> Checking container runtime prerequisites..."
  if ! container run --rm docker.io/library/busybox:1.36.1 true 2>/dev/null; then
    echo "error: container runtime check failed; configure kernel with:" >&2
    echo "  container system kernel set --url <kernel-tarball-url>" >&2
    echo "Set SKIP_KERNEL_CHECK=1 to skip this gate." >&2
    exit 1
  fi
fi

echo "==> Starting compose project..."
container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME"

echo "==> Waiting for HTTP response on ${CURL_URL}..."
attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  if curl -fsS --max-time 5 "$CURL_URL" >/dev/null 2>&1; then
    echo "PASS: received HTTP response from ${CURL_URL}"
    exit 0
  fi
  sleep "$SLEEP_SECONDS"
  attempt=$((attempt + 1))
done

echo "FAIL: no HTTP response from ${CURL_URL} after $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds" >&2
exit 1
