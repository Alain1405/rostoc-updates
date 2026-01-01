#!/usr/bin/env bash
# Stage Python runtime and verify generated_config.py is included
set -euo pipefail

echo "::group::🐍 Staging Python runtime"
echo "[INFO] Pre-staging Python runtime to ensure stable file attributes before signing"

# Verify generated_config.py exists before staging
CONFIG_PATH="src-tauri/src-python/rostoc/generated_config.py"
if [ -f "$CONFIG_PATH" ]; then
  echo "[DEBUG] ✅ generated_config.py exists before staging"
else
  echo "::error::❌ generated_config.py missing before staging! This will cause fallback to production values."
  exit 1
fi

python3 scripts/bundle_runtime.py --target=release --stage-only

# Detect Python version dynamically
PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "[DEBUG] Detected Python version: ${PY_VERSION}"

# Verify file was included in staged runtime
STAGED_CONFIG="build/runtime_staging/pyembed/python/lib/python${PY_VERSION}/site-packages/rostoc/generated_config.py"
if [ -f "$STAGED_CONFIG" ]; then
  echo "[DEBUG] ✅ generated_config.py included in staged runtime"
  echo "[DEBUG] Staged file size: $(wc -c < "$STAGED_CONFIG") bytes"
else
  echo "::error::❌ generated_config.py NOT found in staged runtime at: $STAGED_CONFIG"
  echo "[DEBUG] Listing Python lib directories:"
  find build/runtime_staging/pyembed/python/lib -name "rostoc" -type d || true
  exit 1
fi

echo "[INFO] Runtime staging complete - files are now stable for Tauri's signing"
echo "::endgroup::"
