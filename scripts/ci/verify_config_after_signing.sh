#!/usr/bin/env bash
# Verify generated_config.py persists after signing (macOS only)
set -euo pipefail

echo "::group::🔍 Verifying generated_config.py persistence"

# Detect Python version dynamically
PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

STAGED_CONFIG="build/runtime_staging/pyembed/python/lib/python${PY_VERSION}/site-packages/rostoc/generated_config.py"
if [ -f "$STAGED_CONFIG" ]; then
  echo "[DEBUG] ✅ generated_config.py still present after signing"
else
  echo "::error::❌ generated_config.py disappeared after signing!"
  exit 1
fi
echo "::endgroup::"
