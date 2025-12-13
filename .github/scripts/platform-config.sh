#!/usr/bin/env bash
# Initialize platform-specific configuration based on matrix variables
# Outputs build command, artifact extension, target, and other platform-specific settings

set -euo pipefail

PLATFORM="${1:-}"
ARCH="${2:-}"

if [ -z "$PLATFORM" ] || [ -z "$ARCH" ]; then
  echo "Usage: $0 <platform> <arch>"
  echo "Platforms: macos, windows, linux"
  echo "Architectures: aarch64 (macOS), x86_64 (all), x86 (Windows), i686 (Windows)"
  exit 1
fi

# Artifact naming functions (centralized)
normalize_arch() {
  local platform="$1"
  local arch="$2"
  
  case "$platform" in
    windows)
      case "$arch" in
        i686) echo "x86" ;;
        x86_64) echo "x64" ;;
        *) echo "$arch" ;;
      esac
      ;;
    *)
      echo "$arch"
      ;;
  esac
}

get_updater_archive_name() {
  local version="$1"
  local platform="$2"
  local arch="$3"
  
  case "$platform" in
    macos)
      echo "Rostoc-${version}-darwin-${arch}.app.tar.gz"
      ;;
    linux)
      echo "Rostoc-${version}-linux-${arch}.AppImage.tar.gz"
      ;;
    *)
      echo "::error::Unsupported platform for updater archive: $platform" >&2
      return 1
      ;;
  esac
}

get_installer_name() {
  local version="$1"
  local platform="$2"
  local arch="$3"
  
  case "$platform" in
    macos)
      echo "Rostoc_${version}_${arch}.dmg"
      ;;
    windows)
      local norm_arch
      norm_arch=$(normalize_arch "$platform" "$arch")
      echo "Rostoc-${version}-windows-${norm_arch}.msi"
      ;;
    linux)
      echo "Rostoc-${version}-linux-${arch}.AppImage"
      ;;
    *)
      echo "::error::Unsupported platform for installer: $platform" >&2
      return 1
      ;;
  esac
}

get_signature_name() {
  local artifact="$1"
  echo "${artifact}.sig"
}

case "$PLATFORM" in
  macos)
    {
      echo "build_command=python scripts/build.py --locked"
      echo "artifact_extension=tar.gz"
      echo "test_smoke=true"
      if [ "$ARCH" == "x86_64" ]; then
        echo "target=x86_64-apple-darwin"
        echo "py_url_fragment=macos-x64"
      else
        echo "target=aarch64-apple-darwin"
        echo "py_url_fragment=macos-arm64"
      fi
    }
    ;;
  windows)
    {
      echo "build_command=python scripts/build.py --locked --bundles msi"
      echo "artifact_extension=msi"
      echo "test_smoke=true"
      if [ "$ARCH" == "x86_64" ]; then
        echo "target=x86_64-pc-windows-msvc"
        echo "py_url_fragment=windows-x64"
      else
        echo "target=i686-pc-windows-msvc"
        echo "py_url_fragment=windows-x86"
        echo "cross_compile_args=--target i686-pc-windows-msvc"
      fi
    }
    ;;
  linux)
    {
      echo "build_command=python scripts/build.py --locked --bundles appimage"
      echo "artifact_extension=AppImage"
      echo "test_smoke=true"
      echo "target=x86_64-unknown-linux-gnu"
      echo "py_url_fragment=linux-x64"
    }
    ;;
  *)
    echo "::error::Unknown platform: $PLATFORM"
    exit 1
    ;;
esac
