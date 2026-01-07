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
echo "============================================================"
echo "[DEBUG] Variant Configuration"
echo "============================================================"
echo "ROSTOC_APP_VARIANT=${ROSTOC_APP_VARIANT}"
echo "TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG}"
echo "MODE_FLAG extracted: ${BUILD_COMMAND}" | grep -o '\-\-mode [^ ]*' || echo "  (no --mode flag)"
echo "============================================================"
echo ""

# Debug logging for Linux builds
if [[ "${PLATFORM}" == "linux" ]]; then
  echo "============================================================"
  echo "[DEBUG] Linux AppImage Build Environment"
  echo "============================================================"
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
  echo "============================================================"
fi

echo "[INFO] Starting build — output will be saved to ${LOG_FILE}"
# shellcheck disable=SC2086
${BUILD_COMMAND} 2>&1 | tee "${LOG_FILE}"
# CRITICAL: Use PIPESTATUS[0] to get build command exit code, not tee's exit code
BUILD_EXIT_CODE=${PIPESTATUS[0]}

# Debug: Print captured exit codes
echo ""
echo "============================================================"
echo "[DEBUG] Pipeline Exit Codes"
echo "============================================================"
echo "PIPESTATUS array: ${PIPESTATUS[*]}"
echo "BUILD_EXIT_CODE (from PIPESTATUS[0]): ${BUILD_EXIT_CODE}"
echo "Current \$? (last command): $?"
echo "============================================================"
echo ""

# Extract and highlight errors if build failed
if [[ ${BUILD_EXIT_CODE} -ne 0 ]]; then
  ERROR_LOG="errors-${PLATFORM}-${ARCH}.txt"
  {
    echo "=== ERRORS DETECTED IN BUILD ==="
    echo ""
    
    # Rust compilation errors
    grep -A 5 "^error\[E[0-9]\+\]:" "${LOG_FILE}" 2>/dev/null | head -100 || true
    
    # Rust panic messages
    grep -A 10 "thread '.*' panicked" "${LOG_FILE}" 2>/dev/null || true
    
    # Python errors
    grep -A 10 "Traceback (most recent call last):" "${LOG_FILE}" 2>/dev/null || true
    
    # Tauri errors
    grep -A 5 "Error:" "${LOG_FILE}" 2>/dev/null | grep -v "^--$" || true
    
    # Platform-specific errors
    if [[ "${PLATFORM}" == "macos" ]]; then
      grep -A 5 "codesign.*failed" "${LOG_FILE}" 2>/dev/null || true
      grep -A 5 "errSecInternalComponent" "${LOG_FILE}" 2>/dev/null || true
    elif [[ "${PLATFORM}" == "windows" ]]; then
      grep -A 5 "LINK : fatal error" "${LOG_FILE}" 2>/dev/null || true
      grep -A 5 "MSBuild.*failed" "${LOG_FILE}" 2>/dev/null || true
    fi
    
    echo ""
    echo "=== END ERRORS ==="
  } > "${ERROR_LOG}"
  
  echo ""
  echo "============================================================"
  echo "[ERROR] Build failed. Error summary saved to ${ERROR_LOG}"
  cat "${ERROR_LOG}"
  echo "============================================================"
  
  # Analyze errors and suggest solutions
  if [[ -f "../.github/scripts/analyze-error.sh" ]]; then
    echo ""
    echo "============================================================"
    echo "[INFO] Analyzing errors for known patterns..."
    echo "============================================================"
    bash "../.github/scripts/analyze-error.sh" "${ERROR_LOG}" || true
  fi
fi

# Generate step summary (visible in GitHub Actions UI)
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Build Summary: ${PLATFORM} ${ARCH}"
    echo ""
    echo "**Exit Code**: ${BUILD_EXIT_CODE}"
    echo "**Variant**: ${ROSTOC_APP_VARIANT}"
    echo "**Config**: ${TAURI_CONFIG_FLAG:-<base config>}"
    echo ""
    
    if [[ ${BUILD_EXIT_CODE} -eq 0 ]]; then
      echo "### ✅ Build Succeeded"
      echo ""
      echo "**Artifacts Created**:"
      
      # List created artifacts
      if [[ "${PLATFORM}" == "macos" ]]; then
        find src-tauri/target/release/bundle -name "*.dmg" -o -name "*.app.tar.gz" 2>/dev/null | while read -r artifact; do
          SIZE=$(stat -f%z "$artifact" 2>/dev/null || stat -c%s "$artifact" 2>/dev/null || echo "0")
          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "- \`$(basename "$artifact")\` (${SIZE_MB} MB)"
        done || true
      elif [[ "${PLATFORM}" == "windows" ]]; then
        find src-tauri/target -name "*.msi" -o -name "*.msi.zip" 2>/dev/null | while read -r artifact; do
          SIZE=$(stat -c%s "$artifact" 2>/dev/null || echo "0")
          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "- \`$(basename "$artifact")\` (${SIZE_MB} MB)"
        done || true
      elif [[ "${PLATFORM}" == "linux" ]]; then
        find src-tauri/target -name "*.AppImage" 2>/dev/null | while read -r artifact; do
          SIZE=$(stat -c%s "$artifact" 2>/dev/null || echo "0")
          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "- \`$(basename "$artifact")\` (${SIZE_MB} MB)"
        done || true
      fi
    else
      echo "### ❌ Build Failed"
      echo ""
      if [[ -f "${ERROR_LOG}" ]]; then
        echo "**Extracted Errors**:"
        echo '```'
        cat "${ERROR_LOG}"
        echo '```'
        echo ""
      fi
      echo "**Last 50 lines of build log**:"
      echo '```'
      tail -50 "${LOG_FILE}" || echo "(log file not found)"
      echo '```'
      echo ""
      echo "📎 Full build log available as artifact: \`build-logs-${PLATFORM}-${ARCH}\`"
      
      # Add error analysis if available
      if [[ -f "../.github/scripts/analyze-error.sh" ]]; then
        echo ""
        echo "### 💡 Suggested Solutions"
        echo ""
        bash "../.github/scripts/analyze-error.sh" "${ERROR_LOG}" || echo "No known error patterns detected"
      fi
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

# Post-build debug logging for Linux
if [[ "${PLATFORM}" == "linux" ]]; then
  echo "============================================================"
  echo "[DEBUG] Linux AppImage Build Results (exit code: ${BUILD_EXIT_CODE})"
  echo "============================================================"
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
  echo "============================================================"
fi

echo ""
echo "============================================================"
echo "[DEBUG] Script Exit"
echo "============================================================"
echo "Exiting with BUILD_EXIT_CODE: ${BUILD_EXIT_CODE}"
echo "============================================================"

exit "${BUILD_EXIT_CODE}"
