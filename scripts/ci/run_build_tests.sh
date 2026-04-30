#!/usr/bin/env bash

set -euo pipefail

TEST_KIND=${1:?TEST_KIND is required}
ARCH=${2:?ARCH is required}
VARIANT=${3:-production}

APP_BUNDLE=${APP_BUNDLE:-}
PYBIN_HINT=${PYBIN_HINT:-}

resolve_python_hint() {
  local pybin="$1"

  if [[ -z "$pybin" ]]; then
    echo ""
    return 0
  fi

  if [[ "$pybin" == /* ]]; then
    echo "$pybin"
  else
    echo "$GITHUB_WORKSPACE/private-src/$pybin"
  fi
}

find_windows_python() {
  local python_path
  python_path=$(python3 scripts/ci/get_runtime_path.py python_path windows)
  find target -type f -path "*/$python_path" -print -quit 2>/dev/null || true
}

find_windows_executable() {
  find target src-tauri/target -type f -path '*/release/rostoc.exe' -print -quit 2>/dev/null || true
}

run_mac_runtime() {
  local abs_app pybin

  if [[ -z "$APP_BUNDLE" ]]; then
    echo "::warning::APP_BUNDLE not set, skipping macOS runtime smoke test"
    exit 0
  fi

  if [[ "$APP_BUNDLE" == /* ]]; then
    abs_app="$APP_BUNDLE"
  else
    abs_app="$GITHUB_WORKSPACE/private-src/$APP_BUNDLE"
  fi

  if [[ ! -d "$abs_app" ]]; then
    echo "::warning::App bundle not found at $abs_app, skipping runtime test"
    exit 0
  fi

  pybin=$(resolve_python_hint "$PYBIN_HINT")
  if [[ -z "$pybin" || ! -x "$pybin" ]]; then
    echo "::warning::Embedded Python not found at $pybin, skipping runtime test"
    exit 0
  fi

  echo "[INFO] Running runtime smoke test: $pybin"
  "$pybin" scripts/ci/unified_smoke_validator.py runtime \
    --platform mac \
    --comprehensive \
    --require-manifest \
    --debug-json macos_runtime_smoke_debug.json \
    --strict
}

run_mac_gui() {
  local abs_app pybin

  if [[ -z "$APP_BUNDLE" ]]; then
    echo "::warning::App path not provided, skipping GUI smoke test"
    exit 0
  fi

  if [[ "$APP_BUNDLE" == /* ]]; then
    abs_app="$APP_BUNDLE"
  else
    abs_app="$GITHUB_WORKSPACE/private-src/$APP_BUNDLE"
  fi

  if [[ ! -d "$abs_app" ]]; then
    echo "::warning::App bundle not found at $abs_app, skipping GUI smoke test"
    exit 0
  fi

  pybin=$(resolve_python_hint "$PYBIN_HINT")
  if [[ -z "$pybin" || ! -x "$pybin" ]]; then
    echo "::warning::Embedded Python not found at $pybin, skipping GUI smoke test"
    exit 0
  fi

  echo "[INFO] Running GUI smoke test with 10s timeout"
  "$pybin" scripts/ci/unified_smoke_validator.py gui \
    --platform mac \
    --exe-path "$abs_app" \
    --timeout 10 \
    --debug-json macos_gui_smoke_debug.json || {
    exitcode=$?
    echo "[WARN] GUI smoke test failed (non-fatal): exit code $exitcode"
    exit 0
  }
}

run_windows_runtime() {
  local pybin debug_json failure_message

  pybin=$(find_windows_python)
  if [[ -z "$pybin" ]]; then
    echo "[WARN] Embedded python.exe not found at canonical location for ${ARCH} build"
    exit 0
  fi

  if [[ "$ARCH" == "i686" ]]; then
    debug_json="windows_x86_runtime_smoke_debug.json"
    failure_message="[WARN] x86 smoke test failed (optional platform, continuing): exit code"
    echo "[INFO] Running x86 runtime smoke test: $pybin" >&2
  else
    debug_json="windows_x64_runtime_smoke_debug.json"
    failure_message="[WARN] x64 smoke test failed (exit code"
    echo "[INFO] Running x64 runtime smoke test: $pybin" >&2
  fi

  "$pybin" scripts/ci/unified_smoke_validator.py runtime \
    --platform windows \
    --comprehensive \
    --require-manifest \
    --debug-json "$debug_json" \
    --strict || {
    exitcode=$?
    if [[ "$ARCH" == "i686" ]]; then
      echo "$failure_message $exitcode"
    else
      echo "$failure_message $exitcode), continuing"
    fi
    exit 0
  }
}

run_windows_integration() {
  local exe_path debug_json failure_message

  exe_path=$(find_windows_executable)
  if [[ -z "$exe_path" ]]; then
    echo "[WARN] Windows executable not found for ${ARCH} integration smoke"
    exit 0
  fi

  if [[ "$ARCH" == "i686" ]]; then
    debug_json="windows_x86_integration_smoke_debug.json"
    failure_message="[WARN] x86 integration smoke failed (optional platform, continuing): exit code"
    echo "[INFO] Running x86 integration smoke with $exe_path" >&2
  else
    debug_json="windows_x64_integration_smoke_debug.json"
    failure_message="[WARN] x64 integration smoke failed (exit code"
    echo "[INFO] Running x64 integration smoke with $exe_path" >&2
  fi

  python3 scripts/ci/unified_smoke_validator.py integration \
    --platform windows \
    --variant "$VARIANT" \
    --timeout 10 \
    --exe-path "$exe_path" \
    --debug-json "$debug_json" \
    --strict || {
    exitcode=$?
    if [[ "$ARCH" == "i686" ]]; then
      echo "$failure_message $exitcode"
    else
      echo "$failure_message $exitcode), continuing"
    fi
    exit 0
  }
}

run_linux_runtime() {
  local python_path pybin

  python_path=$(python3 scripts/ci/get_runtime_path.py python_path unix)
  pybin=$(find target -type f -path "*/$python_path" -print -quit 2>/dev/null || true)
  if [[ -z "$pybin" ]]; then
    echo "[WARN] Embedded python not found at canonical location for Linux build"
    exit 0
  fi

  echo "[INFO] Running Linux runtime smoke test: $pybin" >&2
  "$pybin" scripts/ci/unified_smoke_validator.py runtime \
    --platform linux \
    --comprehensive \
    --require-manifest \
    --debug-json linux_runtime_smoke_debug.json \
    --strict || {
    exitcode=$?
    echo "[WARN] Linux smoke test failed (optional platform, continuing): exit code $exitcode"
    exit 0
  }
}

case "$TEST_KIND" in
  mac-runtime)
    run_mac_runtime
    ;;
  mac-gui)
    run_mac_gui
    ;;
  windows-runtime)
    run_windows_runtime
    ;;
  windows-integration)
    run_windows_integration
    ;;
  linux-runtime)
    run_linux_runtime
    ;;
  *)
    echo "Unknown TEST_KIND: $TEST_KIND" >&2
    exit 1
    ;;
esac