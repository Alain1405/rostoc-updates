#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR=${1:-.}
PNPM_LOCK="$TARGET_DIR/pnpm-lock.yaml"
UV_LOCK="$TARGET_DIR/uv.lock"

if [ ! -f "$PNPM_LOCK" ]; then
  echo "::error::pnpm-lock.yaml not found in $TARGET_DIR" >&2
  exit 1
fi

pnpm_hash=$(shasum -a 256 "$PNPM_LOCK" | awk '{print $1}')
if [ -f "$UV_LOCK" ]; then
  uv_hash=$(shasum -a 256 "$UV_LOCK" | awk '{print $1}')
else
  uv_hash="missing"
fi

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "pnpm=$pnpm_hash"
  echo "uv=$uv_hash"
else
  {
    echo "pnpm=$pnpm_hash"
    echo "uv=$uv_hash"
  } >> "$GITHUB_OUTPUT"
fi
