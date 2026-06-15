#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: install requires arm64 (Apple Silicon)" >&2
  exit 1
fi

if ! CONTAINER_PATH="$(command -v container)"; then
  echo "error: container CLI not found in PATH" >&2
  exit 1
fi

resolve_install_root() {
  if [[ -n "${CONTAINER_INSTALL_ROOT:-}" ]]; then
    printf '%s' "$CONTAINER_INSTALL_ROOT"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    local brew_container_prefix brew_container_bin
    if brew_container_prefix="$(brew --prefix container 2>/dev/null)"; then
      brew_container_bin="${brew_container_prefix}/bin/container"
      # Homebrew formula sets CONTAINER_INSTALL_ROOT to opt/container; only use
      # that layout when the active `container` binary is the Homebrew one.
      if [[ "$CONTAINER_PATH" == "$brew_container_bin" ]] \
        || [[ "$CONTAINER_PATH" == "${brew_container_prefix}"* ]]; then
        printf '%s/opt/container' "$brew_container_prefix"
        return
      fi
    fi
  fi

  dirname "$(dirname "$CONTAINER_PATH")"
}

INSTALL_ROOT="$(resolve_install_root)"
PLUGIN_DEST="${INSTALL_ROOT}/libexec/container-plugins/compose"

if [[ "${INSTALL_FROM_DIST:-0}" == "1" ]]; then
  if [[ ! -f dist/compose/bin/compose ]]; then
    echo "error: dist/compose/bin/compose not found; run make dist first" >&2
    exit 1
  fi
else
  bash "$ROOT_DIR/scripts/build-release.sh"
fi

echo "Starting container system (required for plugin discovery)..."
if ! container system start; then
  echo "warning: container system start did not complete successfully" >&2
fi

install_plugin_copy() {
  mkdir -p "$PLUGIN_DEST"
  cp -R dist/compose/* "$PLUGIN_DEST/"
  chmod 755 "$PLUGIN_DEST"/bin/*
}

install_plugin_symlink() {
  local source_dir="$1"
  mkdir -p "$(dirname "$PLUGIN_DEST")"
  ln -sfn "$source_dir" "$PLUGIN_DEST"
}

if [[ -n "${PLUGIN_SOURCE_DIR:-}" ]]; then
  echo "Linking plugin from ${PLUGIN_SOURCE_DIR} to ${PLUGIN_DEST}..."
  if install_plugin_symlink "$PLUGIN_SOURCE_DIR"; then
    echo "Symlink installed."
  else
    echo "error: failed to create plugin symlink" >&2
    exit 1
  fi
elif mkdir -p "$PLUGIN_DEST" 2>/dev/null && install_plugin_copy; then
  echo "Installed to ${PLUGIN_DEST}."
else
  echo "Plugin directory is not writable. Run manually:" >&2
  echo "  sudo mkdir -p \"$(dirname "$PLUGIN_DEST")\"" >&2
  echo "  sudo cp -R dist/compose/* \"${PLUGIN_DEST}/\"" >&2
  echo "  sudo chmod 755 \"${PLUGIN_DEST}/bin/compose\"" >&2
  exit 1
fi

echo "Verifying plugin registration..."
if container --help | grep -A 5 "PLUGINS:"; then
  echo "Done."
else
  echo "warning: compose plugin not listed; ensure container system is running" >&2
  exit 1
fi
