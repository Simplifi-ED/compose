#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <binary> [expected-entitlements.plist]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

BINARY="$1"
EXPECTED_PLIST="${2:-entitlements.plist}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$EXPECTED_PLIST" != /* ]]; then
  EXPECTED_PLIST="${ROOT_DIR}/${EXPECTED_PLIST}"
fi

if [[ ! -f "$BINARY" ]]; then
  echo "error: binary not found: ${BINARY}" >&2
  exit 1
fi

if [[ ! -f "$EXPECTED_PLIST" ]]; then
  echo "error: entitlements plist not found: ${EXPECTED_PLIST}" >&2
  exit 1
fi

dump_embedded() {
  echo "embedded entitlements:" >&2
  codesign -d --entitlements :- "$BINARY" 2>&1 || true
}

codesign -v "$BINARY"

EMBEDDED="$(mktemp)"
EXPECTED_XML="$(mktemp)"
EMBEDDED_XML="$(mktemp)"
trap 'rm -f "$EMBEDDED" "$EXPECTED_XML" "$EMBEDDED_XML"' EXIT

if ! codesign -d --entitlements :- "$BINARY" 2>/dev/null >"$EMBEDDED"; then
  echo "error: no embedded entitlements in ${BINARY}" >&2
  dump_embedded
  exit 1
fi

plutil -convert xml1 -o "$EXPECTED_XML" "$EXPECTED_PLIST"
plutil -convert xml1 -o "$EMBEDDED_XML" "$EMBEDDED"

if ! diff -u "$EXPECTED_XML" "$EMBEDDED_XML" >/dev/null; then
  echo "error: embedded entitlements do not match ${EXPECTED_PLIST}" >&2
  diff -u "$EXPECTED_XML" "$EMBEDDED_XML" >&2 || true
  dump_embedded
  exit 1
fi

echo "codesign entitlements OK: ${BINARY}"
