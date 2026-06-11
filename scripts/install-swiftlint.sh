#!/usr/bin/env bash
set -euo pipefail

SWIFTLINT_VERSION="${SWIFTLINT_VERSION:-0.63.3}"
INSTALL_DIR="${SWIFTLINT_INSTALL_DIR:-${HOME}/.local/bin}"

export PATH="${INSTALL_DIR}:${PATH}"

if command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint already installed: $(swiftlint version)"
  exit 0
fi

mkdir -p "$INSTALL_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ZIP_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
echo "Downloading SwiftLint ${SWIFTLINT_VERSION}..."
curl -fsSL "$ZIP_URL" -o "$TMP_DIR/swiftlint.zip"
unzip -q "$TMP_DIR/swiftlint.zip" -d "$TMP_DIR"
install -m 755 "$TMP_DIR/swiftlint" "$INSTALL_DIR/swiftlint"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$INSTALL_DIR" >> "$GITHUB_PATH"
fi

echo "Installed: $(swiftlint version)"
