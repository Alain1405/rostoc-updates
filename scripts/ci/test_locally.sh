#!/usr/bin/env bash
# Test harness for local CI script validation
# Usage: ./scripts/ci/test_locally.sh [script_name]
#
# This script creates a mock GitHub Actions environment to test CI scripts locally
# without pushing to GitHub and waiting for CI runners.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_WORKSPACE="${TEST_WORKSPACE:-/tmp/ci-test-workspace}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
  echo -e "${RED}❌ $*${NC}"
}

echo "🧪 Setting up mock GitHub Actions environment..."
mkdir -p "$TEST_WORKSPACE"
export GITHUB_WORKSPACE="$TEST_WORKSPACE"
export RUNNER_TEMP="$TEST_WORKSPACE/tmp"
export RUNNER_OS="macOS"
mkdir -p "$RUNNER_TEMP"

# Mock GitHub Actions environment files
export GITHUB_OUTPUT="$RUNNER_TEMP/github_output.txt"
export GITHUB_ENV="$RUNNER_TEMP/github_env.txt"
export GITHUB_STEP_SUMMARY="$RUNNER_TEMP/step_summary.md"
export GITHUB_PATH="$RUNNER_TEMP/github_path.txt"
touch "$GITHUB_OUTPUT" "$GITHUB_ENV" "$GITHUB_STEP_SUMMARY" "$GITHUB_PATH"

# Set default test inputs (can be overridden by environment)
export ROSTOC_APP_VARIANT="${ROSTOC_APP_VARIANT:-production}"
export INPUT_PLATFORM="${INPUT_PLATFORM:-macos}"
export INPUT_ARCH="${INPUT_ARCH:-aarch64}"
export INPUT_IS_RELEASE="${INPUT_IS_RELEASE:-false}"
export PRIVATE_REPO="${PRIVATE_REPO:-alain1405/rostoc}"

# Mock common CI variables
export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Alain1405/rostoc-updates}"
export GITHUB_REF="${GITHUB_REF:-refs/heads/main}"
export GITHUB_SHA="${GITHUB_SHA:-abc123def456}"
export GITHUB_RUN_ID="${GITHUB_RUN_ID:-12345}"
export GITHUB_RUN_NUMBER="${GITHUB_RUN_NUMBER:-42}"
export GITHUB_ACTOR="${GITHUB_ACTOR:-test-user}"

log_info "Mock environment configured:"
log_info "  GITHUB_WORKSPACE: $GITHUB_WORKSPACE"
log_info "  RUNNER_TEMP: $RUNNER_TEMP"
log_info "  ROSTOC_APP_VARIANT: $ROSTOC_APP_VARIANT"
log_info "  INPUT_PLATFORM: $INPUT_PLATFORM"
log_info "  INPUT_ARCH: $INPUT_ARCH"
log_info "  INPUT_IS_RELEASE: $INPUT_IS_RELEASE"
echo ""

SCRIPT_NAME="${1:-}"

if [ -n "$SCRIPT_NAME" ]; then
  # Test specific script
  SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
  
  if [ ! -f "$SCRIPT_PATH" ]; then
    log_error "Script not found: $SCRIPT_PATH"
    exit 1
  fi
  
  log_info "Testing: $SCRIPT_NAME"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Run script with bash -x for debugging
  if bash -x "$SCRIPT_PATH"; then
    log_success "Script executed successfully"
    EXIT_CODE=0
  else
    EXIT_CODE=$?
    log_error "Script failed with exit code: $EXIT_CODE"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Display outputs
  log_info "GitHub Actions outputs:"
  
  if [ -s "$GITHUB_OUTPUT" ]; then
    echo ""
    echo "📤 GITHUB_OUTPUT:"
    cat "$GITHUB_OUTPUT"
  else
    log_warning "GITHUB_OUTPUT is empty"
  fi
  
  if [ -s "$GITHUB_ENV" ]; then
    echo ""
    echo "🌍 GITHUB_ENV:"
    cat "$GITHUB_ENV"
  else
    log_warning "GITHUB_ENV is empty"
  fi
  
  if [ -s "$GITHUB_STEP_SUMMARY" ]; then
    echo ""
    echo "📋 GITHUB_STEP_SUMMARY:"
    cat "$GITHUB_STEP_SUMMARY"
  else
    log_warning "GITHUB_STEP_SUMMARY is empty"
  fi
  
  if [ -s "$GITHUB_PATH" ]; then
    echo ""
    echo "🛤️  GITHUB_PATH additions:"
    cat "$GITHUB_PATH"
  fi
  
  echo ""
  log_info "Test workspace preserved at: $TEST_WORKSPACE"
  log_info "To clean up: rm -rf $TEST_WORKSPACE"
  
  exit "$EXIT_CODE"
else
  # List available scripts
  log_info "Available CI scripts to test:"
  echo ""
  
  # shellcheck disable=SC2312
  find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) ! -name "test_locally.sh" | sort | while read -r script; do
    basename "$script"
  done
  
  echo ""
  log_info "Usage: $0 <script_name>"
  echo ""
  log_info "Example:"
  echo "  $0 generate_and_verify_config.sh"
  echo ""
  log_info "Environment variables you can set:"
  echo "  ROSTOC_APP_VARIANT=staging    # production or staging"
  echo "  INPUT_PLATFORM=macos           # macos, windows, linux"
  echo "  INPUT_ARCH=aarch64             # aarch64, x86_64, i686"
  echo "  INPUT_IS_RELEASE=true          # true or false"
  echo "  TEST_WORKSPACE=/custom/path    # Custom workspace directory"
  echo ""
  log_info "Full example:"
  echo "  ROSTOC_APP_VARIANT=staging INPUT_PLATFORM=macos $0 generate_and_verify_config.sh"
  
  exit 0
fi
