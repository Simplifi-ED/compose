#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="${HOME}/.local/bin:${PATH}"
SWIFTLINT="${SWIFTLINT:-swiftlint}"
if ! command -v "$SWIFTLINT" >/dev/null; then
  echo "error: swiftlint not found (~/.local/bin or PATH)" >&2
  exit 1
fi

export SWIFTLINT_DISABLE_SOURCEKIT="${SWIFTLINT_DISABLE_SOURCEKIT:-1}"
exec "$SWIFTLINT" lint --strict --disable-sourcekit Sources "$@"
