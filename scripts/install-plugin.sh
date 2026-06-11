#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! CONTAINER_PATH="$(command -v container)"; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi
INSTALL_ROOT="$(dirname "$(dirname "$CONTAINER_PATH")")"
PLUGIN_DEST="${INSTALL_ROOT}/libexec/container-plugins/compose"

bash "$ROOT_DIR/scripts/package.sh"

echo "Starting container system (required for plugin discovery)..."
if ! container system start; then
  echo "warning: container system start did not complete successfully" >&2
fi

echo "Installing plugin to ${PLUGIN_DEST}..."
if mkdir -p "$PLUGIN_DEST" 2>/dev/null && cp -R dist/compose/* "$PLUGIN_DEST/"; then
  echo "Installed without elevated permissions."
else
  echo "Plugin directory is not writable. Run manually:" >&2
  echo "  sudo mkdir -p \"${PLUGIN_DEST}\"" >&2
  echo "  sudo cp -R dist/compose/* \"${PLUGIN_DEST}/\"" >&2
  exit 1
fi

echo "Verifying plugin registration..."
if container --help | grep -A 5 "PLUGINS:"; then
  echo "Done."
else
  echo "warning: compose plugin not listed; ensure container system is running" >&2
  exit 1
fi
