#!/usr/bin/env bash
# Verify Python architecture matches expected architecture
# Usage: ./verify_python_arch.sh <expected_arch>
#   expected_arch: x64, x86, or arm64

set -euo pipefail

EXPECTED_ARCH="${1:-x64}"

echo "🔍 Verifying Python architecture..."
echo ""

# Get Python version and path
PYTHON_VERSION=$(python --version 2>&1)
PYTHON_PATH=$(which python)

echo "Python version: $PYTHON_VERSION"
echo "Python path: $PYTHON_PATH"
echo ""

# Check Python architecture
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
  # Windows
  PYTHON_ARCH=$(python -c "import platform; print(platform.architecture()[0])")
  echo "Python architecture: $PYTHON_ARCH"
  
  # Verify matches expected
  if [[ "$EXPECTED_ARCH" == "x64" && "$PYTHON_ARCH" == "64bit" ]]; then
    echo "✅ Python architecture matches expected x64"
    exit 0
  elif [[ "$EXPECTED_ARCH" == "x86" && "$PYTHON_ARCH" == "32bit" ]]; then
    echo "✅ Python architecture matches expected x86"
    exit 0
  else
    echo "❌ ERROR: Expected $EXPECTED_ARCH but got $PYTHON_ARCH"
    exit 1
  fi
else
  # macOS/Linux
  PYTHON_ARCH=$(python -c "import platform; print(platform.machine())")
  echo "Python architecture: $PYTHON_ARCH"
  
  if [[ "$EXPECTED_ARCH" == "x64" && "$PYTHON_ARCH" == "x86_64" ]]; then
    echo "✅ Python architecture matches expected x64"
    exit 0
  elif [[ "$EXPECTED_ARCH" == "arm64" && "$PYTHON_ARCH" == "arm64" ]]; then
    echo "✅ Python architecture matches expected arm64"
    exit 0
  else
    echo "✅ Python architecture: $PYTHON_ARCH (platform default)"
    exit 0
  fi
fi
