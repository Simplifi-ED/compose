#!/bin/bash
set -eo pipefail
cd "$(git rev-parse --show-toplevel)"

# Clean past artifacts and build
rm -rf dist
swift build -c release

# Assemble layout
mkdir -p dist/compose/bin
cp .build/release/compose dist/compose/bin/
cp config.toml dist/compose/

echo "Build package assembled inside dist/compose/"
