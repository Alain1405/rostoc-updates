#!/usr/bin/env bash
# Execute Tauri build with comprehensive logging and platform-specific debugging
set -euo pipefail

# Required env vars
: "${ROSTOC_APP_VARIANT:?}"
# TAURI_CONFIG_FLAG can be empty for production builds
: "${TAURI_CONFIG_FLAG+x}"

# Inputs from GitHub Actions
PLATFORM="${1:?Platform required (macos, windows, linux)}"
ARCH="${2:?Architecture required (aarch64, x86_64, i686)}"
BUILD_COMMAND="${3:?Build command required}"

LOG_FILE="build-${PLATFORM}-${ARCH}.log"

# Debug variant configuration (all platforms)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[DEBUG] Variant Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ROSTOC_APP_VARIANT=${ROSTOC_APP_VARIANT}"
echo "TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG}"
echo "MODE_FLAG extracted: ${BUILD_COMMAND}" | grep -o '\-\-mode [^ ]*' || echo "  (no --mode flag)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Debug logging for Linux builds
if [[ "${PLATFORM}" == "linux" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "[DEBUG] Linux AppImage Build Environment"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "APPIMAGE_EXTRACT_AND_RUN=${APPIMAGE_EXTRACT_AND_RUN:-<not set>}"
  echo "NO_STRIP=${NO_STRIP:-<not set>}"
  echo "OUTPUT=${OUTPUT:-<not set>}"
  echo "VERBOSE=${VERBOSE:-<not set>}"
  echo "OUTPUT=${OUTPUT:-<not set>}"
  echo "VERBOSE=${VERBOSE:-<not set>}"
  echo ""
  echo "FUSE installations:"
  dpkg -l | grep -i fuse || echo "  No FUSE packages found"
  echo ""
  echo "FUSE version: $(fusermount3 --version 2>&1 || echo 'fusermount3 not available')"
  echo "fusermount version: $(fusermount --version 2>&1 || echo 'fusermount not available')"
  echo ""
  echo "Available disk space: $(df -h . | tail -1 | awk '{print $4}')"
  echo "Kernel: $(uname -r)"
  echo "User: $(whoami)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[TRACE] Pre-Build Diagnostics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Build command: ${BUILD_COMMAND}"
echo "Working directory: $(pwd)"
echo "Tauri config: ${TAURI_CONFIG_FLAG:-<not set, using base>}"
echo ""
echo "Available Tauri config files:"
find . -maxdepth 3 -name "tauri*.conf.json" 2>/dev/null || echo "  (no config files found)"
echo ""
echo "Python runtime status:"
if [[ -d "build/runtime_staging/pyembed" ]]; then
  echo "  Runtime staged: YES"
  echo "  Python binary: $(ls -lh build/runtime_staging/pyembed/python 2>/dev/null | awk '{print $9, $5}' || echo 'not found')"
  echo "  DLL count: $(find build/runtime_staging/pyembed -name '*.dll' 2>/dev/null | wc -l)"
else
  echo "  Runtime staged: NO"
fi
echo ""
echo "Disk space before build: $(df -h . | tail -1 | awk '{print $4}')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "[INFO] Starting build — output will be saved to ${LOG_FILE}"
# shellcheck disable=SC2086
${BUILD_COMMAND} 2>&1 | tee "${LOG_FILE}"
BUILD_EXIT_CODE=$?

# Post-build debug logging for Linux
if [[ "${PLATFORM}" == "linux" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "[DEBUG] Linux AppImage Build Results (exit code: ${BUILD_EXIT_CODE})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Checking for AppImage artifacts in target directories..."
  find target -name "*.AppImage" 2>/dev/null || echo "  No AppImage found in target/"
  find src-tauri/target -name "*.AppImage" 2>/dev/null || echo "  No AppImage found in src-tauri/target/"
  
  echo ""
  echo "Last 100 lines of build log (to capture linuxdeploy errors):"
  tail -100 "${LOG_FILE}" || echo "  (Could not read log file)"
  
  echo ""
  echo "Searching for error patterns in build log:"
  grep -i "error\|failed\|linuxdeploy" "${LOG_FILE}" | tail -30 || echo "  (No error patterns found)"
  
  echo ""
  echo "AppImage build directory contents:"
  find src-tauri/target -type d -name "appimage" -exec sh -c 'echo "Contents of {}"; ls -lah "{}" 2>/dev/null || echo "  (directory not accessible)"' \; || echo "  (No appimage directory found)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Post-build artifact listing (all platforms)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[TRACE] Build Artifacts Created (exit code: ${BUILD_EXIT_CODE})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Listing all artifacts in target/release/bundle:"
if [[ -d "src-tauri/target/release/bundle" ]]; then
  find src-tauri/target/release/bundle -type f \( -name "*.dmg" -o -name "*.app" -o -name "*.msi" -o -name "*.zip" -o -name "*.sig" -o -name "*.AppImage" \) -exec sh -c 'echo "  {} ($(stat -f%z "{}" 2>/dev/null || stat -c%s "{}" 2>/dev/null | numfmt --to=iec-i 2>/dev/null || echo "unknown size"))"' \; | sort
else
  echo "  (bundle directory not found)"
fi

echo ""
echo "Checking for updater archives (.msi.zip):"
find src-tauri/target -name "*.msi.zip" 2>/dev/null | while read -r file; do
  echo "  Found: ${file}"
  echo "    Size: $(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}" 2>/dev/null | numfmt --to=iec-i 2>/dev/null || echo 'unknown')"
  echo "    Signature: $(ls -1 "${file}.sig" 2>/dev/null && echo 'YES' || echo 'NO')"
done
[[ -z "$(find src-tauri/target -name '*.msi.zip' 2>/dev/null)" ]] && echo "  (no .msi.zip files found)"

echo ""
echo "Disk space after build: $(df -h . | tail -1 | awk '{print $4}')"
echo "Build log size: $(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null | numfmt --to=iec-i 2>/dev/null || echo 'unknown')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "${BUILD_EXIT_CODE}"
