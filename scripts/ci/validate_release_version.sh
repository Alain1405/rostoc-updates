#!/usr/bin/env bash
# Validate that git tag version matches tauri.conf.json version
set -euo pipefail

VERSION=$(jq -r '.version' src-tauri/tauri.conf.json)
REF="${GITHUB_REF:-}"

if [[ "$REF" =~ ^refs/tags/v([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
  TAG_VERSION="${BASH_REMATCH[1]}"
  echo "[INFO] Tag version: $TAG_VERSION"
  echo "[INFO] Code version: $VERSION"

  if [ "$TAG_VERSION" != "$VERSION" ]; then
    echo "::error::Version mismatch! Tag is v$TAG_VERSION but tauri.conf.json has $VERSION"
    exit 1
  fi
  echo "[INFO] ✅ Version validation passed"
else
  echo "::warning::Not a version tag, skipping validation"
fi
