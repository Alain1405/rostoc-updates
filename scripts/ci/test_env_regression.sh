#!/usr/bin/env bash
# Regression test: Verify the fix for "parameter null or not set" bug
# This test documents the bug that occurred on 2026-01-01 in CI
# https://github.com/Alain1405/rostoc-updates/actions/runs/20633195252/job/59254550486

set -euo pipefail

echo "🧪 Regression Test: TAURI_CONFIG_FLAG empty value handling"
echo ""

# Test Case 1: The bug that broke CI (using :?)
echo "Test 1: Simulating the BUG (should fail)"
echo "----------------------------------------"
cat > /tmp/test_bug.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# This is the buggy pattern that failed in CI
TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG:?TAURI_CONFIG_FLAG is required}
echo "Config flag: '$TAURI_CONFIG_FLAG'"
EOF

chmod +x /tmp/test_bug.sh

# This should fail when TAURI_CONFIG_FLAG is empty
export TAURI_CONFIG_FLAG=""
if /tmp/test_bug.sh 2>/tmp/bug_output.txt; then
  echo "❌ Expected failure with empty value but script passed"
  cat /tmp/bug_output.txt
  exit 1
elif grep -qE "(parameter null or not set|TAURI_CONFIG_FLAG is required)" /tmp/bug_output.txt; then
  echo "✅ Bug correctly detected - script fails with empty value"
  echo "   Error: $(cat /tmp/bug_output.txt | head -1)"
else
  echo "❌ Script failed but not with expected error"
  cat /tmp/bug_output.txt
  exit 1
fi
echo ""

# Test Case 2: The fix (using ? without colon)
echo "Test 2: Testing the FIX (should pass)"
echo "--------------------------------------"
cat > /tmp/test_fix.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# This is the fixed pattern that allows empty values
TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG?TAURI_CONFIG_FLAG must be set}
echo "Config flag: '$TAURI_CONFIG_FLAG'"
EOF

chmod +x /tmp/test_fix.sh

# This should succeed with empty value
export TAURI_CONFIG_FLAG=""
if output=$(/tmp/test_fix.sh 2>&1) && echo "$output" | grep -q "Config flag: ''"; then
  echo "✅ Fix works - script accepts empty value"
  echo "   Output: $output"
else
  echo "❌ Fix failed - script should accept empty value"
  echo "   Output: $output"
  exit 1
fi
echo ""

# Test Case 3: Both should fail when variable is unset
echo "Test 3: Both patterns should fail when UNSET"
echo "---------------------------------------------"
unset TAURI_CONFIG_FLAG

if /tmp/test_bug.sh 2>/tmp/bug_unset.txt; then
  echo "❌ Bug pattern should fail when unset"
  exit 1
elif grep -qE "(parameter null or not set|TAURI_CONFIG_FLAG is required)" /tmp/bug_unset.txt; then
  echo "✅ Bug pattern correctly fails when unset"
else
  echo "❌ Unexpected error when unset"
  cat /tmp/bug_unset.txt
  exit 1
fi

if /tmp/test_fix.sh 2>/tmp/fix_unset.txt; then
  echo "❌ Fix pattern should fail when unset"
  exit 1
elif grep -qE "(parameter null or not set|TAURI_CONFIG_FLAG must be set)" /tmp/fix_unset.txt; then
  echo "✅ Fix pattern correctly fails when unset"
else
  echo "❌ Unexpected error when unset"
  cat /tmp/fix_unset.txt
  exit 1
fi
echo ""

# Test Case 4: Verify execute_build.sh uses the fixed pattern
echo "Test 4: Verify execute_build.sh has the fix"
echo "--------------------------------------------"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if grep -q 'TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG:?' "$SCRIPT_DIR/execute_build.sh"; then
  echo "❌ execute_build.sh still has the bug (uses :?)"
  exit 1
else
  echo "✅ execute_build.sh uses correct pattern"
fi
echo ""

# Test Case 5: Verify platform-specific TAURI config selection
echo "Test 5: Verify set-tauri-config-flag platform selection"
echo "--------------------------------------------------------"
TEST_GITHUB_ENV=/tmp/test_github_env.txt

assert_config_flag() {
  local variant platform expected actual
  variant=${1:?variant is required}
  platform=${2:?platform is required}
  if [[ $# -lt 3 ]]; then
    echo "❌ expected value argument is required"
    exit 1
  fi
  expected=$3

  : > "$TEST_GITHUB_ENV"
  if ! output=$(GITHUB_ENV="$TEST_GITHUB_ENV" ROSTOC_APP_VARIANT="$variant" \
    bash "$SCRIPT_DIR/run_build_compile.sh" set-tauri-config-flag "$platform" 2>&1); then
    echo "❌ set-tauri-config-flag failed for variant=$variant platform=$platform"
    echo "$output"
    exit 1
  fi

  actual=$(grep '^TAURI_CONFIG_FLAG=' "$TEST_GITHUB_ENV" | tail -1 | cut -d'=' -f2-)
  if [[ "$actual" != "$expected" ]]; then
    echo "❌ Unexpected config flag for variant=$variant platform=$platform"
    echo "   Expected: '$expected'"
    echo "   Actual:   '$actual'"
    exit 1
  fi

  echo "✅ variant=$variant platform=$platform -> ${actual:-<empty>}"
}

assert_config_flag production windows src-tauri/tauri.windows.production.conf.json
assert_config_flag production macos ""
assert_config_flag staging windows src-tauri/tauri.staging.conf.json
assert_config_flag dev windows src-tauri/tauri.dev.conf.json
echo ""

# Test Case 6: Verify bundle target selection for compile commands
echo "Test 6: Verify init-platform-config bundle target selection"
echo "-----------------------------------------------------------"
TEST_GITHUB_OUTPUT=/tmp/test_github_output.txt

capture_build_command() {
  local platform arch bundle_target output command
  platform=${1:?platform is required}
  arch=${2:?arch is required}
  bundle_target=${3:-all}

  : > "$TEST_GITHUB_OUTPUT"
  if ! output=$(GITHUB_OUTPUT="$TEST_GITHUB_OUTPUT" ROSTOC_APP_VARIANT=production \
    bash "$SCRIPT_DIR/run_build_compile.sh" init-platform-config "$platform" "$arch" "$bundle_target" 2>&1); then
    echo "❌ init-platform-config failed for platform=$platform arch=$arch bundle_target=$bundle_target"
    echo "$output"
    exit 1
  fi

  command=$(grep '^build_command=' "$TEST_GITHUB_OUTPUT" | tail -1 | cut -d'=' -f2-)
  if [[ -z "$command" ]]; then
    echo "❌ build_command output missing for platform=$platform arch=$arch bundle_target=$bundle_target"
    cat "$TEST_GITHUB_OUTPUT"
    exit 1
  fi

  echo "$command"
}

assert_build_command_contains() {
  local platform arch bundle_target expected command
  platform=${1:?platform is required}
  arch=${2:?arch is required}
  bundle_target=${3:?bundle_target is required}
  expected=${4:?expected fragment is required}

  command=$(capture_build_command "$platform" "$arch" "$bundle_target")
  if [[ "$command" != *"$expected"* ]]; then
    echo "❌ Expected build command to contain '$expected'"
    echo "   Command: $command"
    exit 1
  fi

  echo "✅ platform=$platform arch=$arch bundle_target=$bundle_target -> $expected"
}

assert_build_command_not_contains() {
  local platform arch bundle_target unexpected command
  platform=${1:?platform is required}
  arch=${2:?arch is required}
  bundle_target=${3:?bundle_target is required}
  unexpected=${4:?unexpected fragment is required}

  command=$(capture_build_command "$platform" "$arch" "$bundle_target")
  if [[ "$command" == *"$unexpected"* ]]; then
    echo "❌ Build command should not contain '$unexpected'"
    echo "   Command: $command"
    exit 1
  fi

  echo "✅ platform=$platform arch=$arch bundle_target=$bundle_target omits $unexpected"
}

assert_build_command_not_contains macos aarch64 all "--bundles"
assert_build_command_contains macos x86_64 app "--bundles app"
assert_build_command_contains windows x86_64 all "--bundles msi"
echo ""

# Cleanup
rm -f /tmp/test_bug.sh /tmp/test_fix.sh /tmp/bug_output.txt /tmp/fix_unset.txt /tmp/bug_unset.txt "$TEST_GITHUB_ENV" "$TEST_GITHUB_OUTPUT"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All regression tests passed!"
echo ""
echo "Summary of fix:"
echo "  WRONG: \${TAURI_CONFIG_FLAG:?msg}  # Fails on empty (what we had)"
echo "  RIGHT: \${TAURI_CONFIG_FLAG?msg}   # Allows empty (what we have now)"
echo ""
echo "Production non-Windows builds keep TAURI_CONFIG_FLAG='' (no overlay), which is valid."
echo "Production Windows builds now set the embedBootstrapper overlay explicitly."
echo "Non-release macOS CI can request --bundles app to avoid DMG-only flakiness."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
