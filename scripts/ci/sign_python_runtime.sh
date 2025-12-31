#!/usr/bin/env bash
# Sign Python binaries and libraries in staged runtime (macOS only)
set -euo pipefail

APPLE_SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"

if [ -z "$APPLE_SIGNING_IDENTITY" ]; then
  echo "::error::APPLE_SIGNING_IDENTITY not set"
  exit 1
fi

echo "[INFO] Signing Python binaries and libraries in build/runtime_staging/pyembed/python"
echo "[INFO] These will be synced to src-tauri/ by build.py, preserving signatures"

# Sign all executables in bin/
if [ -d "build/runtime_staging/pyembed/python/bin" ]; then
  find build/runtime_staging/pyembed/python/bin -type f \( -perm +111 -o -name "python*" \) | while read -r binary; do
    if file "$binary" | grep -q "Mach-O"; then
      echo "  Signing: $(basename "$binary")"
      codesign --force --sign "$APPLE_SIGNING_IDENTITY" \
        --timestamp \
        --options runtime \
        "$binary" || echo "    Warning: failed to sign $binary"
    fi
  done
fi

# Sign all dylibs and .so files in lib/
if [ -d "build/runtime_staging/pyembed/python/lib" ]; then
  find build/runtime_staging/pyembed/python/lib -type f \( -name "*.dylib" -o -name "*.so" \) | while read -r lib; do
    echo "  Signing: $(basename "$lib")"
    codesign --force --sign "$APPLE_SIGNING_IDENTITY" \
      --timestamp \
      --options runtime \
      "$lib" || echo "    Warning: failed to sign $lib"
  done
fi

echo "[INFO] Python runtime signing complete in staging area"
