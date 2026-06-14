#!/usr/bin/env bash
set -euo pipefail

# Opt-in spike: re-sign release binary with app-sandbox and record pass/fail matrix.
# Does not modify production entitlements.plist or build-release.sh output.
# Intentionally exits 0 — never wire into CI (records matrix only).
# See docs/entitlements-audit.md.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SANDBOX_PLIST="${ROOT_DIR}/entitlements.sandbox.plist"
CAPABILITY_PLIST="${ROOT_DIR}/entitlements.plist"
BINARY="${ROOT_DIR}/dist/compose/bin/compose"
CAPABILITY_COPY="${ROOT_DIR}/dist/compose/bin/compose-capability-spike"
SANDBOX_COPY="${ROOT_DIR}/dist/compose/bin/compose-sandbox-spike"

pass=0
fail=0
skip=0

record() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  printf '| %s | %s | %s |\n' "$name" "$status" "$detail"
  case "$status" in
    PASS) pass=$((pass + 1)) ;;
    FAIL) fail=$((fail + 1)) ;;
    SKIP) skip=$((skip + 1)) ;;
  esac
}

run_help() {
  local bin="$1"
  if ( "$bin" --help >/dev/null 2>&1 ); then
    return 0
  fi
  return 1
}

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: sandbox entitlement spike requires arm64" >&2
  exit 1
fi

if [[ ! -f "$SANDBOX_PLIST" ]]; then
  echo "error: ${SANDBOX_PLIST} not found" >&2
  exit 1
fi

echo "==> Building release binary..."
bash "$ROOT_DIR/scripts/build-release.sh" >/dev/null

cp "$BINARY" "$CAPABILITY_COPY"
cp "$BINARY" "$SANDBOX_COPY"
codesign --entitlements "$CAPABILITY_PLIST" --force -s - "$CAPABILITY_COPY" >/dev/null
codesign --entitlements "$SANDBOX_PLIST" --force -s - "$SANDBOX_COPY" >/dev/null

echo
echo "## Capability-only matrix (release posture)"
echo '| Check | Result | Notes |'
echo '|-------|--------|-------|'

if bash "$ROOT_DIR/scripts/verify-codesign.sh" "$CAPABILITY_COPY" "$CAPABILITY_PLIST" >/dev/null 2>&1; then
  record 'verify-codesign (capability)' PASS 'embedded hypervisor + network.client'
else
  record 'verify-codesign (capability)' FAIL 'entitlements gate'
fi

if run_help "$CAPABILITY_COPY"; then
  record 'compose --help (capability)' PASS ''
else
  record 'compose --help (capability)' FAIL "exit $?"
fi

echo
echo "## App Sandbox candidate matrix (entitlements.sandbox.plist — not shipped)"
echo '| Check | Result | Notes |'
echo '|-------|--------|-------|'

if run_help "$SANDBOX_COPY"; then
  record 'compose --help (sandbox)' PASS ''
else
  record 'compose --help (sandbox)' FAIL 'expected until blockers B1–B5 mitigated'
fi

if command -v container >/dev/null 2>&1; then
  record 'compose up/down (sandbox)' SKIP 'requires plugin install + runtime; run manually after mitigations'
else
  record 'compose up/down (sandbox)' SKIP 'container CLI not on PATH'
fi

record 'compose watch (sandbox)' SKIP 'blocked by FSEvents + arbitrary paths (B2)'
record 'up --host-dns (sandbox)' SKIP 'blocked by /etc/hosts + osascript (B3)'
record 'compose doctor (sandbox)' SKIP 'blocked by container subprocess (B4)'

echo
echo "Summary: ${pass} passed, ${fail} failed, ${skip} skipped"
echo "Full blocker register: docs/entitlements-audit.md"

rm -f "$CAPABILITY_COPY" "$SANDBOX_COPY"

exit 0
