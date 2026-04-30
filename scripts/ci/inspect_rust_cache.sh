#!/usr/bin/env bash
set -euo pipefail

MODE=${1:?usage: inspect_rust_cache.sh <pre|post> [workspace_dir] [cache_hit]}
WORKSPACE_DIR=${2:-.}
CACHE_HIT=${3:-false}

cd "$WORKSPACE_DIR"

case "$MODE" in
  pre)
    echo "::group::Rust cache configuration"
    echo "[INFO] pwd=$(pwd)"
    echo "[INFO] CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-<unset>}"
    cargo metadata --format-version 1 --manifest-path src-tauri/Cargo.toml --no-deps \
      | jq -r '"[INFO] workspace_root=\(.workspace_root)\n[INFO] target_directory=\(.target_directory)"'
    echo "[INFO] Existing target directories before restore:"
    ls -ld target src-tauri/target 2>/dev/null || true
    echo "::endgroup::"
    ;;
  post)
    echo "::group::Rust cache restore result"
    echo "[INFO] rust-cache cache-hit=$CACHE_HIT"
    if [ -d src-tauri/target ]; then
      echo "[INFO] src-tauri/target restored contents:"
      find src-tauri/target -maxdepth 2 -mindepth 1 -type d | sort | head -50
      du -sh src-tauri/target || true
    else
      echo "[INFO] src-tauri/target not present after restore"
    fi
    if [ -d target ]; then
      echo "[INFO] repo-root target also exists after restore:"
      du -sh target || true
    fi
    echo "::endgroup::"
    ;;
  *)
    echo "::error::Unknown mode: $MODE" >&2
    exit 1
    ;;
esac