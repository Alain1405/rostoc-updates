#!/usr/bin/env bash

set -euo pipefail

COMMAND=${1:?COMMAND is required}
shift

variant_uses_dev_tooling() {
  case "${ROSTOC_APP_VARIANT:-production}" in
    staging|dev)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_target_triple() {
  local platform arch
  platform=${1:?platform is required}
  arch=${2:?arch is required}

  case "$platform:$arch" in
    macos:x86_64)
      echo "x86_64-apple-darwin"
      ;;
    macos:aarch64)
      echo "aarch64-apple-darwin"
      ;;
    windows:x86_64)
      echo "x86_64-pc-windows-msvc"
      ;;
    windows:i686)
      echo "i686-pc-windows-msvc"
      ;;
    linux:x86_64)
      echo "x86_64-unknown-linux-gnu"
      ;;
    *)
      echo "::error::Unsupported platform/arch combination: $platform/$arch" >&2
      exit 1
      ;;
  esac
}

resolve_python_url_fragment() {
  local platform arch
  platform=${1:?platform is required}
  arch=${2:?arch is required}

  case "$platform:$arch" in
    macos:x86_64)
      echo "macos-x64"
      ;;
    macos:aarch64)
      echo "macos-arm64"
      ;;
    windows:x86_64)
      echo "windows-x64"
      ;;
    windows:i686)
      echo "windows-x86"
      ;;
    linux:x86_64)
      echo "linux-x64"
      ;;
    *)
      echo "::error::Unsupported platform/arch combination for embedded Python: $platform/$arch" >&2
      exit 1
      ;;
  esac
}

resolve_bundle_flag() {
  local bundle_target
  bundle_target=${1:-all}

  case "$bundle_target" in
    all)
      echo ""
      ;;
    app|msi|nsis|dmg|appimage)
      echo "--bundles $bundle_target"
      ;;
    *)
      echo "::error::Unsupported bundle target: $bundle_target" >&2
      exit 1
      ;;
  esac
}

init_platform_config() {
  local platform arch target py_url_fragment bundle_target bundle_flag
  platform=${1:?platform is required}
  arch=${2:?arch is required}
  bundle_target=${3:-all}
  target=$(resolve_target_triple "$platform" "$arch")
  py_url_fragment=$(resolve_python_url_fragment "$platform" "$arch")
  bundle_flag=$(resolve_bundle_flag "$bundle_target")

  local mode_flag=""
  local features_flag=""

  # Non-production variants keep development-mode tooling enabled in CI.
  if variant_uses_dev_tooling; then
    mode_flag="--mode development"
    features_flag="--features devtools"
  fi

  case "$platform" in
    macos)
      {
        echo "build_command=python scripts/build.py --locked $bundle_flag $mode_flag $features_flag"
        echo "artifact_extension=tar.gz"
        echo "test_smoke=true"
        echo "target=$target"
        echo "py_url_fragment=$py_url_fragment"
      } >> "$GITHUB_OUTPUT"
      ;;
    windows)
      {
        if [[ "$arch" == "x86_64" ]]; then
          echo "build_command=python scripts/build.py --locked --bundles msi $mode_flag $features_flag"
        else
          echo "build_command=python scripts/build.py --locked --bundles msi --target i686-pc-windows-msvc $mode_flag $features_flag"
        fi
        echo "target=$target"
        echo "py_url_fragment=$py_url_fragment"
        echo "artifact_extension=msi"
        echo "test_smoke=true"
      } >> "$GITHUB_OUTPUT"
      ;;
    linux)
      {
        echo "build_command=python scripts/build.py --locked --bundles appimage $mode_flag $features_flag"
        echo "artifact_extension=AppImage"
        echo "test_smoke=true"
        echo "target=$target"
        echo "py_url_fragment=$py_url_fragment"
      } >> "$GITHUB_OUTPUT"
      ;;
    *)
      echo "::error::Unknown platform: $platform"
      exit 1
      ;;
  esac
}

download_embedded_python() {
  local platform arch python_target
  platform=${1:?platform is required}
  arch=${2:?arch is required}
  python_target=$(resolve_target_triple "$platform" "$arch")

  case "$platform" in
    macos)
      PYTHON_TARGET="$python_target" bash scripts/macos/download-py.sh
      ;;
    windows)
      PYTHON_TARGET="$python_target" pwsh scripts/windows/download-py.ps1
      ;;
    linux)
      PYTHON_TARGET="$python_target" bash scripts/linux/download-py.sh
      ;;
    *)
      echo "::error::Unknown platform: $platform"
      exit 1
      ;;
  esac
}

verify_embedded_python_architecture() {
  local platform arch python_exe python_info machine is_64bit
  platform=${1:?platform is required}
  arch=${2:?arch is required}

  echo "🔍 Verifying embedded Python architecture matches target: $arch"

  case "$platform" in
    windows)
      python_exe="src-tauri/pyembed/python/python.exe"
      ;;
    *)
      python_exe="src-tauri/pyembed/python/bin/python3"
      ;;
  esac

  if [[ ! -f "$python_exe" ]]; then
    echo "❌ ERROR: Embedded Python not found at $python_exe"
    echo "Contents of src-tauri/pyembed/:"
    ls -la src-tauri/pyembed/ || echo "Directory does not exist"
    exit 1
  fi

  python_info=$($python_exe -c "import platform, sys; print(f'{platform.machine()},{sys.maxsize > 2**32}')" 2>&1)
  machine=$(echo "$python_info" | cut -d',' -f1)
  is_64bit=$(echo "$python_info" | cut -d',' -f2)

  echo "📊 Embedded Python info:"
  echo "  - Machine: $machine"
  echo "  - 64-bit: $is_64bit"
  echo "  - Target arch: $arch"

  if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
    if [[ "$is_64bit" != "True" ]]; then
      echo "❌ ERROR: Expected 64-bit Python for $arch target, but got 32-bit!"
      exit 1
    fi
  elif [[ "$arch" == "i686" ]]; then
    if [[ "$is_64bit" != "False" ]]; then
      echo "❌ ERROR: Expected 32-bit Python for i686 target, but got 64-bit!"
      exit 1
    fi
  fi

  echo "✅ Embedded Python architecture matches target"
}

set_tauri_config_flag() {
  local platform config_flag
  platform=${1:-}

  case "${ROSTOC_APP_VARIANT:-production}" in
    staging)
      config_flag="src-tauri/tauri.staging.conf.json"
      ;;
    dev)
      config_flag="src-tauri/tauri.dev.conf.json"
      ;;
    production)
      # Production Windows builds still need the Windows-only overlay so Tauri
      # embeds the WebView2 bootstrapper in installers.
      if [[ "$platform" == "windows" ]]; then
        config_flag="src-tauri/tauri.windows.production.conf.json"
      else
        config_flag=""
      fi
      ;;
    *)
      echo "::warning::Unknown variant '${ROSTOC_APP_VARIANT:-}', defaulting to production"
      if [[ "$platform" == "windows" ]]; then
        config_flag="src-tauri/tauri.windows.production.conf.json"
      else
        config_flag=""
      fi
      ;;
  esac

  echo "TAURI_CONFIG_FLAG=$config_flag" >> "$GITHUB_ENV"
  echo "[INFO] TAURI_CONFIG_FLAG=${config_flag:-<empty>}"
}

configure_python_bytecode_mode() {
  local platform variant is_release bytecode_mode experiment_label
  platform=${1:?platform is required}
  variant=${2:?variant is required}
  is_release=${3:?is_release is required}

  bytecode_mode="default"
  experiment_label="disabled"

  if [[ "$platform" == "windows" && "$variant" == "production" && "$is_release" != "true" ]]; then
    bytecode_mode="skip"
    experiment_label="windows-production-non-release"
    echo "PYTHONDONTWRITEBYTECODE=1" >> "$GITHUB_ENV"
  fi

  {
    echo "ROSTOC_PYTHON_BYTECODE_MODE=$bytecode_mode"
    echo "ROSTOC_PYTHON_BYTECODE_EXPERIMENT=$experiment_label"
  } >> "$GITHUB_ENV"

  echo "[INFO] Python bytecode mode: $bytecode_mode"
  echo "[INFO] Python bytecode experiment: $experiment_label"
  if [[ "$bytecode_mode" == "skip" ]]; then
    echo "[INFO] Exported PYTHONDONTWRITEBYTECODE=1 for CI experiment"
  fi
}

capture_diagnostic_environment() {
  local platform arch
  platform=${1:?platform is required}
  arch=${2:?arch is required}

  {
    echo "# Build Environment Diagnostics"
    echo ""
    echo "**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "**Runner**: ${RUNNER_OS:-unknown} ${RUNNER_ARCH:-unknown}"
    echo "**Platform**: $platform"
    echo "**Architecture**: $arch"
    echo "**Variant**: ${ROSTOC_APP_VARIANT:-production}"
    echo ""

    echo "## Disk Space"
    df -h . || true
    echo ""

    echo "## Installed Tools"
    echo "- Node: $(node --version 2>/dev/null || echo 'not installed')"
    echo "- pnpm: $(pnpm --version 2>/dev/null || echo 'not installed')"
    echo "- Rust: $(rustc --version 2>/dev/null || echo 'not installed')"
    echo "- Python: $(python3 --version 2>/dev/null || echo 'not installed')"
    echo "- uv: $(uv --version 2>/dev/null || echo 'not installed')"

    if [[ "$platform" == "macos" ]]; then
      echo "- codesign: $(codesign --version 2>&1 | head -1 || echo 'not available')"
      echo "- xcrun: $(xcrun --version 2>&1 || echo 'not available')"
    fi
    echo ""

    echo "## Environment Variables"
    echo '```'
    env | grep -E '^(ROSTOC|TAURI|SENTRY|GITHUB|RUNNER|PYO3)' | sort || true
    echo '```'
    echo ""

    echo "## Available Tauri Configs"
    find src-tauri -maxdepth 1 -name "tauri*.json" -exec basename {} \; | sort
    echo ""

    echo "## Python Runtime Status"
    if [[ -d "build/runtime_staging" ]]; then
      echo "Runtime staged: YES"
      find build/runtime_staging -type f \( -name "python*" -o -name "*.dll" -o -name "*.dylib" \) 2>/dev/null | head -20
    else
      echo "Runtime staged: NO"
    fi
  } > "diagnostics-${platform}-${arch}.md"
}

generate_build_fingerprint() {
  local platform arch
  platform=${1:?platform is required}
  arch=${2:?arch is required}

  {
    echo "# Build Fingerprint"
    echo "timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "platform: $platform"
    echo "arch: $arch"
    echo "variant: ${ROSTOC_APP_VARIANT:-production}"
    echo "runner_os: ${RUNNER_OS:-unknown}"
    echo "github_sha: ${GITHUB_SHA:-unknown}"
    echo "github_run_number: ${GITHUB_RUN_NUMBER:-unknown}"
    echo ""
    echo "# Dependencies"
    echo "package_json_hash: $(shasum package.json 2>/dev/null | awk '{print $1}' || echo 'N/A')"
    echo "cargo_lock_hash: $(shasum src-tauri/Cargo.lock 2>/dev/null | awk '{print $1}' || echo 'N/A')"
    echo "pnpm_lock_hash: $(shasum pnpm-lock.yaml 2>/dev/null | awk '{print $1}' || echo 'N/A')"
    echo ""
    echo "# Tool Versions"
    echo "node: $(node --version 2>/dev/null || echo 'unknown')"
    echo "rust: $(rustc --version 2>/dev/null || echo 'unknown')"
    echo "python: $(python3 --version 2>/dev/null || echo 'unknown')"
    echo ""
    echo "# Config Selection"
    echo "tauri_config: ${TAURI_CONFIG_FLAG:-<base>}"
    echo "python_bytecode_mode: ${ROSTOC_PYTHON_BYTECODE_MODE:-default}"
    echo "python_bytecode_experiment: ${ROSTOC_PYTHON_BYTECODE_EXPERIMENT:-disabled}"
    echo "pythondontwritebytecode: ${PYTHONDONTWRITEBYTECODE:-0}"
    if [[ -n "${TAURI_CONFIG_FLAG:-}" && -f "${TAURI_CONFIG_FLAG}" ]]; then
      echo "config_hash: $(shasum "${TAURI_CONFIG_FLAG}" 2>/dev/null | awk '{print $1}' || echo 'N/A')"
    fi
  } > build-fingerprint.txt
}

set_windows_pyo3_python() {
  local arch python_exe arch_info machine is_64bit expected_64bit python_exe_win
  arch=${1:?arch is required}

  echo "🔧 Configuring PyO3 to use staged embedded Python..."

  python_exe="$(pwd)/build/runtime_staging/pyembed/python/python.exe"
  if [[ ! -f "$python_exe" ]]; then
    echo "❌ ERROR: Staged Python not found at $python_exe"
    echo "   This should have been created by the staging step."
    ls -la build/runtime_staging/ 2>/dev/null || echo "   Staging directory doesn't exist!"
    exit 1
  fi

  echo "🔍 Verifying Python architecture matches target: $arch"
  arch_info=$("$python_exe" -c "import platform, sys; print(f'{platform.machine()},{sys.maxsize > 2**32}')" 2>&1)
  machine=$(echo "$arch_info" | cut -d',' -f1)
  is_64bit=$(echo "$arch_info" | cut -d',' -f2)

  expected_64bit=""
  if [[ "$arch" == "x86_64" ]]; then
    expected_64bit="True"
  elif [[ "$arch" == "i686" ]]; then
    expected_64bit="False"
  fi

  if [[ -n "$expected_64bit" && "$is_64bit" != "$expected_64bit" ]]; then
    echo "❌ ERROR: Python architecture mismatch!"
    echo "   Target: $arch ($([[ "$expected_64bit" == "True" ]] && echo "64-bit" || echo "32-bit"))"
    echo "   Python: $machine ($is_64bit = $([[ "$is_64bit" == "True" ]] && echo "64-bit" || echo "32-bit"))"
    echo "   This will cause PyO3 compilation to fail."
    exit 1
  fi

  python_exe_win=$(cygpath -w "$python_exe" 2>/dev/null || echo "$python_exe")
  echo "PYO3_PYTHON=$python_exe_win" >> "$GITHUB_ENV"

  echo "✅ PYO3_PYTHON configured: $python_exe_win"
  echo "   Architecture: $machine ($([[ "$is_64bit" == "True" ]] && echo "64-bit" || echo "32-bit")) - matches target $arch"
}

remove_windows_git_path_entries() {
  local new_path

  new_path=$(echo "$PATH" | tr ':' '\n' \
    | grep -v "Git/usr/bin" \
    | grep -v "Git/mingw64/bin" \
    | grep -v "^/usr/bin$" \
    | grep -v "^/mingw64/bin$" \
    | tr '\n' ':' | sed 's/:$//')
  echo "PATH=$new_path" >> "$GITHUB_ENV"
  echo "✅ Removed Git usr/bin and mingw64/bin from PATH (including MSYS2-native forms)"
  echo "Updated PATH (first 500 chars): ${new_path:0:500}"
}

install_linux_appimage_dependencies() {
  sudo apt-get update -qq
  sudo apt-get install -y \
    libssl-dev \
    libffi-dev \
    libglib2.0-0 \
    libglib2.0-dev \
    libgtk-3-dev \
    libwebkit2gtk-4.1-dev \
    libjavascriptcoregtk-4.1-dev \
    librsvg2-dev \
    libayatana-appindicator3-dev \
    libwebp-dev \
    patchelf \
    pkg-config \
    libx11-6 \
    fuse3 \
    libfuse2
  echo "✅ AppImage build dependencies installed"
}

case "$COMMAND" in
  init-platform-config)
    init_platform_config "$@"
    ;;
  download-embedded-python)
    download_embedded_python "$@"
    ;;
  verify-embedded-python-arch)
    verify_embedded_python_architecture "$@"
    ;;
  set-tauri-config-flag)
    set_tauri_config_flag "$@"
    ;;
  configure-python-bytecode-mode)
    configure_python_bytecode_mode "$@"
    ;;
  capture-diagnostic-environment)
    capture_diagnostic_environment "$@"
    ;;
  generate-build-fingerprint)
    generate_build_fingerprint "$@"
    ;;
  set-windows-pyo3-python)
    set_windows_pyo3_python "$@"
    ;;
  remove-windows-git-path-entries)
    remove_windows_git_path_entries "$@"
    ;;
  install-linux-appimage-deps)
    install_linux_appimage_dependencies "$@"
    ;;
  *)
    echo "Unknown COMMAND: $COMMAND" >&2
    exit 1
    ;;
esac
