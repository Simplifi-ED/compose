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
if [[ ! -x "${BIN_DIR}/compose-xpc" ]] || [[ ! -x "${BIN_DIR}/compose-xpc-sample" ]]; then
  make build BUILD_CONFIGURATION=release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  SOURCE_BINARY="${BIN_DIR}/compose"
fi
if [[ ! -x "${BIN_DIR}/compose-xpc" ]]; then
  echo "error: release binary not found at ${BIN_DIR}/compose-xpc" >&2
  exit 1
fi

mkdir -p dist/compose/bin dist/compose/LaunchAgents
DEST_BINARY="dist/compose/bin/compose"
DEST_XPC="dist/compose/bin/compose-xpc"
DEST_SAMPLE="dist/compose/bin/compose-xpc-sample"
cp "$SOURCE_BINARY" "$DEST_BINARY"
cp "${BIN_DIR}/compose-xpc" "$DEST_XPC"
cp "${BIN_DIR}/compose-xpc-sample" "$DEST_SAMPLE"
strip -x "$DEST_BINARY"
strip -x "$DEST_XPC"
strip -x "$DEST_SAMPLE"
chmod 755 "$DEST_BINARY" "$DEST_XPC" "$DEST_SAMPLE"
codesign --entitlements "$ENTITLEMENTS" --force -s - "$DEST_BINARY"
codesign --entitlements "$ENTITLEMENTS" --force -s - "$DEST_XPC"
codesign --entitlements "$ENTITLEMENTS" --force -s - "$DEST_SAMPLE"

cp config.toml dist/compose/
cp Resources/LaunchAgents/com.simplifi-ed.container-compose.xpc.plist dist/compose/LaunchAgents/

echo "Release package assembled in dist/compose/"
VERIFY="$(dirname "${BASH_SOURCE[0]}")/verify-codesign.sh"
"$VERIFY" "$DEST_BINARY" "$ENTITLEMENTS"
"$VERIFY" "$DEST_XPC" "$ENTITLEMENTS"
"$VERIFY" "$DEST_SAMPLE" "$ENTITLEMENTS"
