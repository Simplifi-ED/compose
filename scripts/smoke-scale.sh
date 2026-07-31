#!/usr/bin/env bash
# Live runtime smoke for compose scale: delta reconcile up/down and static-port rejection.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/fixtures/scale-smoke/compose.yml"
PROJECT_NAME="scale-smoke"

cleanup() {
  container compose down -f "$COMPOSE_FILE" -p "$PROJECT_NAME" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: scale smoke requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

count_web() {
  container compose ps -f "$COMPOSE_FILE" -p "$PROJECT_NAME" 2>/dev/null \
    | grep -c "${PROJECT_NAME}_web_" || true
}

echo "==> Smoke: compose up (deploy.replicas=2 for web)"
container compose up -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --progress none

WEB_COUNT="$(count_web)"
if [[ "$WEB_COUNT" -ne 2 ]]; then
  echo "FAIL: expected 2 web replicas after up, got $WEB_COUNT" >&2
  exit 1
fi

echo "==> Smoke: scale web to 3 (delta — adds web_3 only)"
container compose scale -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --scale web=3
WEB_COUNT="$(count_web)"
if [[ "$WEB_COUNT" -ne 3 ]]; then
  echo "FAIL: expected 3 web replicas after scale up, got $WEB_COUNT" >&2
  exit 1
fi

echo "==> Smoke: scale web to 1 (stops excess replicas)"
container compose scale -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --scale web=1
WEB_COUNT="$(count_web)"
if [[ "$WEB_COUNT" -ne 1 ]]; then
  echo "FAIL: expected 1 web replica after scale down, got $WEB_COUNT" >&2
  exit 1
fi

echo "==> Smoke: static host port blocks scale above 1"
if container compose scale -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --scale api=2 2>/dev/null; then
  echo "FAIL: scale api=2 should fail (static host port)" >&2
  exit 1
fi
echo "PASS: static host port rejected at plan time"

echo "==> Smoke: scale dry-run"
if ! container compose scale -f "$COMPOSE_FILE" -p "$PROJECT_NAME" --scale web=2 --dry-run \
  | grep -q "scale ${PROJECT_NAME}_web_2"; then
  echo "FAIL: dry-run did not list scale target" >&2
  exit 1
fi

echo "PASS: compose scale smoke"
