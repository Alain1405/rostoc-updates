#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR=${1:-.}
PNPM_LOCK="$TARGET_DIR/pnpm-lock.yaml"
UV_LOCK="$TARGET_DIR/uv.lock"

if [ ! -f "$PNPM_LOCK" ]; then
  echo "::error::pnpm-lock.yaml not found in $TARGET_DIR" >&2
  exit 1
fi

# Cross-platform hash function
hash_file() {
  local file=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    # Fallback for Windows (Git Bash doesn't have shasum by default)
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  fi
}

pnpm_hash=$(hash_file "$PNPM_LOCK")
if [ -f "$UV_LOCK" ]; then
  uv_hash=$(hash_file "$UV_LOCK")
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
