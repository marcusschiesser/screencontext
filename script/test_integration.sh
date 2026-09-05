#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$ROOT_DIR/IntegrationTests/.build/test-cache"
mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm"

exec env \
  CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/swiftpm" \
  swift test --package-path "$ROOT_DIR/IntegrationTests" "$@"
