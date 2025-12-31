#!/usr/bin/env bash
# Generate Python config from Tauri config and verify file presence
set -euo pipefail

TAURI_CONFIG_FLAG="${TAURI_CONFIG_FLAG:-}"
ROSTOC_APP_VARIANT="${ROSTOC_APP_VARIANT:-production}"

echo "::group::🔧 Generating Python config from Tauri config"
echo "[DEBUG] PWD: $(pwd)"
echo "[DEBUG] ROSTOC_APP_VARIANT: ${ROSTOC_APP_VARIANT}"
echo "[DEBUG] TAURI_CONFIG_FLAG: ${TAURI_CONFIG_FLAG:-<not set>}"

if [ -n "$TAURI_CONFIG_FLAG" ]; then
  echo "[INFO] Generating Python config with overlay: $TAURI_CONFIG_FLAG"
  python3 scripts/generate_python_config.py --config "$TAURI_CONFIG_FLAG"
else
  echo "[INFO] Generating Python config (production)"
  python3 scripts/generate_python_config.py
fi

# Verify file was created
CONFIG_PATH="src-tauri/src-python/rostoc/generated_config.py"
if [ -f "$CONFIG_PATH" ]; then
  echo "[DEBUG] ✅ generated_config.py created at: $CONFIG_PATH"
  echo "[DEBUG] File size: $(wc -c < "$CONFIG_PATH") bytes"
  echo "[DEBUG] Contents preview:"
  head -20 "$CONFIG_PATH" | sed 's/^/  /'
else
  echo "::error::❌ generated_config.py was NOT created at expected path: $CONFIG_PATH"
  exit 1
fi
echo "::endgroup::"
