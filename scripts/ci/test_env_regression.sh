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

# Cleanup
rm -f /tmp/test_bug.sh /tmp/test_fix.sh /tmp/bug_output.txt /tmp/fix_unset.txt /tmp/bug_unset.txt

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All regression tests passed!"
echo ""
echo "Summary of fix:"
echo "  WRONG: \${TAURI_CONFIG_FLAG:?msg}  # Fails on empty (what we had)"
echo "  RIGHT: \${TAURI_CONFIG_FLAG?msg}   # Allows empty (what we have now)"
echo ""
echo "Production builds set TAURI_CONFIG_FLAG='' (no overlay), which is valid."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
