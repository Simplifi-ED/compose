#!/usr/bin/env bash
# Example external autoscaling loop for container compose.
#
# Production controllers should:
#   - Poll `container compose stats` (CPU + memory per replica)
#   - Average utilization across replicas (see README "Autoscaling")
#   - Apply min/max, cooldowns, and skip services with static host ports
#   - Call `container compose scale --scale SERVICE=COUNT`
#
# This demo scales `web` up to MAX_REPLICAS then back down using only `compose ps`
# replica counts — replace the placeholder logic with real metrics.
#
# Usage: scale-external-controller.sh [COMPOSE_FILE] [PROJECT] [SERVICE]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${1:-"$ROOT_DIR/fixtures/scale-smoke/compose.yml"}"
PROJECT="${2:-scale-smoke}"
SERVICE="${3:-web}"
MAX_REPLICAS="${MAX_REPLICAS:-4}"
INTERVAL="${INTERVAL_SEC:-3}"

COMPOSE_FILE="$(cd "$(dirname "$COMPOSE_FILE")" && pwd)/$(basename "$COMPOSE_FILE")"

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found" >&2
  exit 1
fi

replica_count() {
  container compose ps -f "$COMPOSE_FILE" -p "$PROJECT" 2>/dev/null \
    | grep -c "${PROJECT}_${SERVICE}_" || true
}

echo "External controller demo: $PROJECT / $SERVICE (max=$MAX_REPLICAS, interval=${INTERVAL}s)"
echo "Ensure the project is up: container compose up -f $COMPOSE_FILE -p $PROJECT"
echo ""

phase=up
while true; do
  count="$(replica_count)"
  if [[ "$count" -lt 1 ]]; then
    echo "error: no running replicas for $SERVICE" >&2
    exit 1
  fi

  if [[ "$phase" == "up" ]]; then
    if [[ "$count" -ge "$MAX_REPLICAS" ]]; then
      phase=down
      echo "demo: reached max replicas, scaling down"
      continue
    fi
    target=$((count + 1))
    echo "$(date -u +%H:%M:%S) scale up $SERVICE -> $target"
    container compose scale -f "$COMPOSE_FILE" -p "$PROJECT" --scale "${SERVICE}=${target}"
  else
    if [[ "$count" -le 1 ]]; then
      echo "demo: back at 1 replica — exit"
      exit 0
    fi
    target=$((count - 1))
    echo "$(date -u +%H:%M:%S) scale down $SERVICE -> $target"
    container compose scale -f "$COMPOSE_FILE" -p "$PROJECT" --scale "${SERVICE}=${target}"
  fi
  sleep "$INTERVAL"
done
