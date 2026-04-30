#!/usr/bin/env bash
set -euo pipefail

BASE_VERSION="${BASE_VERSION:?BASE_VERSION is required}"
UPDATE_SMOKE_VERSION="${DEV_WINDOWS_VERSION:-$BASE_VERSION}"

{
  echo "version=$BASE_VERSION"
  echo "update_smoke_version=$UPDATE_SMOKE_VERSION"
} >> "$GITHUB_OUTPUT"

echo "[INFO] Base version: $BASE_VERSION"
echo "[INFO] Windows smoke version: $UPDATE_SMOKE_VERSION"