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
