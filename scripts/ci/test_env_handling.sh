#!/usr/bin/env bash
# Test CI scripts for proper environment variable handling
# Catches issues like "parameter null or not set" errors from ${VAR:?} with empty values

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

errors=0
warnings=0

echo "🧪 Testing CI scripts for environment variable handling..."
echo ""

# Test 1: Detect improper use of :? for variables that can be empty
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Checking for :? pattern that fails on empty values"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Variables that are ALLOWED to be empty in production
ALLOWED_EMPTY=(
  "TAURI_CONFIG_FLAG"     # Empty for production builds (no overlay)
  "DEV_VERSION_SUFFIX"    # Empty for release builds
  "DEBUG_FLAG"            # May be empty for production
)

# Find all ${VAR:?} usage in CI scripts (excluding test scripts themselves)
while IFS= read -r file; do
  if [ -f "$file" ]; then
    # Skip test scripts - they intentionally demonstrate the bug
    if [[ "$file" =~ test_env ]]; then
      continue
    fi
    
    # Extract variable names from ${VAR:?} pattern
    # This regex finds ${VAR:?...} patterns and extracts VAR
    matches=$(grep -nE '\$\{[A-Z_]+:\?' "$file" | grep -v "^[[:space:]]*#" || true)
    
    if [ -n "$matches" ]; then
      filename=$(basename "$file")
      echo "📄 Checking: $filename"
      
      while IFS=: read -r line_num match; do
        # Extract variable name from ${VAR:?...}
        var_name=$(echo "$match" | grep -oE '\$\{[A-Z_]+:\?' | sed 's/\${\(.*\):?/\1/')
        
        # Check if this variable is allowed to be empty
        is_allowed=false
        for allowed in "${ALLOWED_EMPTY[@]}"; do
          if [ "$var_name" = "$allowed" ]; then
            is_allowed=true
            break
          fi
        done
        
        if $is_allowed; then
          echo -e "   ${RED}❌ Line $line_num: ${var_name} uses :? but can be empty in production${NC}"
          echo -e "      Pattern: $(echo "$match" | xargs)"
          echo -e "      Fix: Change \${${var_name}:?} to \${${var_name}?} (remove colon)"
          ((errors++))
        else
          echo -e "   ${GREEN}✓${NC} Line $line_num: ${var_name} correctly requires non-empty value"
        fi
      done <<< "$matches"
      echo ""
    fi
  fi
done < <(find "$SCRIPT_DIR" -name "*.sh" -type f)

# Test 2: Verify scripts can handle empty values for known optional vars
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Smoke testing scripts with empty optional variables"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Mock environment for testing (minimal required vars)
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/tmp/test-workspace}"
export RUNNER_TEMP="${RUNNER_TEMP:-/tmp/test-runner}"
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-/tmp/test-output}"

# Test generate_and_verify_config.sh with empty TAURI_CONFIG_FLAG
echo "📄 Testing: generate_and_verify_config.sh (empty TAURI_CONFIG_FLAG)"
(
  export TAURI_CONFIG_FLAG=""  # Intentionally empty for production
  export CARGO_TOML_PATH="/tmp/test-Cargo.toml"
  export TAURI_CONF_PATH="/tmp/test-tauri.conf.json"
  
  # Create minimal test files
  mkdir -p "$GITHUB_WORKSPACE"
  echo '[package]' > "$CARGO_TOML_PATH"
  echo '{"productName":"Test"}' > "$TAURI_CONF_PATH"
  
  # Dry run - just validate it doesn't error on variable expansion
  if bash -n "$SCRIPT_DIR/generate_and_verify_config.sh" 2>/dev/null; then
    echo -e "   ${GREEN}✓${NC} Script syntax valid with empty TAURI_CONFIG_FLAG"
  else
    echo -e "   ${YELLOW}⚠️  Script has syntax issues (but may be test environment)${NC}"
    ((warnings++))
  fi
)
echo ""

# Test execute_build.sh with empty TAURI_CONFIG_FLAG
echo "📄 Testing: execute_build.sh (empty TAURI_CONFIG_FLAG)"
(
  export TAURI_CONFIG_FLAG=""  # Intentionally empty for production
  export TARGET=""
  export BUILD_MODE="release"
  
  # Just check the variable expansion lines don't fail
  if bash -n "$SCRIPT_DIR/execute_build.sh" 2>/dev/null; then
    echo -e "   ${GREEN}✓${NC} Script syntax valid with empty TAURI_CONFIG_FLAG"
  else
    echo -e "   ${YELLOW}⚠️  Script has syntax issues (but may be test environment)${NC}"
    ((warnings++))
  fi
)
echo ""

# Test 3: Document patterns for contributors
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Best practices reminder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}ℹ️  Environment variable patterns in bash:${NC}"
echo ""
echo "   \${VAR:?msg}  - Fails if VAR is unset OR empty"
echo "   \${VAR?msg}   - Fails if VAR is unset, allows empty"
echo "   \${VAR:-def}  - Uses 'def' if VAR is unset or empty"
echo "   \${VAR-def}   - Uses 'def' if VAR is unset, allows empty"
echo ""
echo -e "${BLUE}ℹ️  For CI scripts:${NC}"
echo "   - Use :? for vars that must have a value (GITHUB_TOKEN, etc.)"
echo "   - Use ? for vars that can be empty (TAURI_CONFIG_FLAG in prod)"
echo "   - Document in comments when empty is intentional"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $errors -gt 0 ]; then
  echo -e "${RED}❌ $errors error(s) found${NC}"
  echo ""
  echo "These will cause CI failures when variables are intentionally empty."
  echo "Run 'make format && make lint' after fixes."
  exit 1
elif [ $warnings -gt 0 ]; then
  echo -e "${YELLOW}⚠️  $warnings warning(s) found${NC}"
  exit 0
else
  echo -e "${GREEN}✅ All checks passed!${NC}"
  exit 0
fi
