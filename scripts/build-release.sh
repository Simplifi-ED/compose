#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${ROOT_DIR}/entitlements.plist"
# ponytail: capability-only v1; see docs/entitlements-audit.md before adding app-sandbox
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: release builds require arm64 (Apple Silicon)" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: entitlements plist not found at ${ENTITLEMENTS}" >&2
  exit 1
fi

rm -rf dist/compose

BIN_DIR="$(swift build -c release --show-bin-path)"
SOURCE_BINARY="${BIN_DIR}/compose"
if [[ ! -x "$SOURCE_BINARY" ]]; then
  make build BUILD_CONFIGURATION=release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  SOURCE_BINARY="${BIN_DIR}/compose"
fi
if [[ ! -x "$SOURCE_BINARY" ]]; then
  echo "error: release binary not found at ${SOURCE_BINARY}" >&2
  exit 1
fi

mkdir -p dist/compose/bin
DEST_BINARY="dist/compose/bin/compose"
cp "$SOURCE_BINARY" "$DEST_BINARY"
strip -x "$DEST_BINARY"
chmod 755 "$DEST_BINARY"
codesign --entitlements "$ENTITLEMENTS" --force -s - "$DEST_BINARY"

cp config.toml dist/compose/

echo "Release package assembled in dist/compose/"
exec "$(dirname "${BASH_SOURCE[0]}")/verify-codesign.sh" "$DEST_BINARY" "$ENTITLEMENTS"
