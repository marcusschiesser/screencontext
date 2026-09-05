#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -type d -name .build -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type f \( \
    -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o \
    -name 'package.json' -o -name 'package-lock.json' -o -name 'yarn.lock' -o \
    -name 'pnpm-lock.yaml' \
  \) -print -quit | grep -q .; then
  echo "Native-only check failed: JavaScript or TypeScript artifact found." >&2
  exit 1
fi

if find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -type d -name .build -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type d -name node_modules -print -quit | grep -q .; then
  echo "Native-only check failed: node_modules found." >&2
  exit 1
fi

if rg -i --glob '!README.md' --glob '!check_native_only.sh' \
  --glob '!.git/**' --glob '!**/.build/**' --glob '!dist/**' \
  '\b(electron|wkwebview|webview|ffmpeg)\b' "$ROOT_DIR" >/dev/null; then
  echo "Native-only check failed: forbidden runtime reference found." >&2
  exit 1
fi

echo "Native-only check passed."
