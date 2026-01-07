#!/usr/bin/env bash
# Analyze build errors and suggest solutions based on known patterns
set -euo pipefail

ERROR_LOG="${1:?Error log file required}"

if [[ ! -f "$ERROR_LOG" ]]; then
  echo "❌ Error log not found: ${ERROR_LOG}"
  exit 1
fi

# Define error patterns and solutions
declare -A ERROR_PATTERNS=(
  ["codesign.*errSecInternalComponent"]="🔐 **Keychain Access Issue**

**Solution**: Unlock keychain with \`security unlock-keychain\`

**Common Causes**:
- Keychain locked after timeout
- Certificate not properly imported
- Wrong keychain being used

**Docs**: See macOS signing documentation"
  
  ["LINK : fatal error LNK1120|LINK : fatal error LNK"]="🔗 **Windows Linker Error**

**Solution**: Missing DLL or library dependency

**Check**:
- Visual Studio installation complete
- Windows SDK version matches requirements
- PATH includes required libraries

**Common Fix**: Reinstall Visual Studio Build Tools"
  
  ["UnicodeDecodeError.*cp1252"]="📝 **Windows Encoding Error**

**Solution**: Add \`PYTHONIOENCODING=utf-8\` to environment

**Why**: Windows uses cp1252 by default, but build logs contain UTF-8

**Status**: This should already be fixed in CI config - if seeing this, config wasn't applied"
  
  ["No space left on device"]="💾 **Disk Space Issue**

**Solution**: Clean up before build or use larger runner

**Commands**:
\`\`\`bash
df -h                    # Check available space
rm -rf target/           # Clean Rust builds
rm -rf node_modules/     # Clean Node packages
\`\`\`

**Required**: Minimum 20GB free space"
  
  ["thread.*panicked.*unwrap.*on.*None"]="🦀 **Rust Panic (Option::unwrap)**

**Solution**: Check for None values in Rust code

**Likely Causes**:
- Missing configuration file
- Environment variable not set
- File path doesn't exist

**Debug**: Look for \`.unwrap()\` calls in stack trace"
  
  ["error\[E0277\].*trait bound"]="🦀 **Rust Trait Bound Error**

**Solution**: Type doesn't implement required trait

**Check**:
- Generic constraints
- Trait implementations
- \`use\` statements for trait imports

**Common Fix**: Add trait implementation or derive macro"
  
  ["ModuleNotFoundError.*rostoc"]="🐍 **Python Import Error**

**Solution**: Virtual environment not activated or package not installed

**Fix**:
\`\`\`bash
source .venv/bin/activate
pip install -e .
pip install -e shared-python
\`\`\`

**CI Context**: Build script should handle this automatically"
  
  ["Tauri.*process.*failed|tauri_build.*failed"]="⚡ **Tauri Build Failure**

**Common Causes**:
- Rust compilation errors (check above)
- Missing system dependencies
- Invalid Tauri config

**Debug Steps**:
1. Check Rust errors first
2. Verify \`tauri.conf.json\` syntax
3. Ensure all features are available

**Logs**: Check both Rust and Node logs"
  
  ["pnpm.*ERR|npm.*ERR"]="📦 **Node Package Error**

**Solution**: Dependency installation or resolution issue

**Fix**:
\`\`\`bash
rm -rf node_modules pnpm-lock.yaml
pnpm install
\`\`\`

**Check**: Node version matches requirements (check .nvmrc)"
  
  ["xcrun.*error|xcode-select.*error"]="🍎 **Xcode Tools Missing (macOS)**

**Solution**: Install or configure Xcode Command Line Tools

**Fix**:
\`\`\`bash
xcode-select --install
sudo xcode-select --switch /Applications/Xcode.app
\`\`\`

**Verify**: \`xcrun --show-sdk-path\` should show valid path"
  
  ["certificate.*not found|signing identity.*not found"]="🔏 **Code Signing Certificate Missing**

**Solution**: Certificate not imported or expired

**Check**:
1. Certificate exists: \`security find-identity -v -p codesigning\`
2. Not expired: Check validity dates
3. Correct keychain: Import to login keychain

**CI Context**: Check \`APPLE_CERTIFICATE\` secret is set"
  
  ["cannot find.*in.*scope|cannot find.*in this scope"]="🦀 **Rust Scope Error**

**Solution**: Missing import or typo in identifier

**Fix**:
- Add \`use\` statement
- Check for typos
- Verify module structure

**Hint**: Error shows what was being looked for"
  
  ["failed to run custom build command"]="🔨 **Custom Build Script Error**

**Solution**: Check \`build.rs\` script

**Common Issues**:
- Missing system libraries
- Invalid build script logic
- Environment setup

**Debug**: Look for build script output above this error"
)

echo "🔍 Analyzing error log: ${ERROR_LOG}"
echo ""

FOUND_PATTERNS=()
for pattern in "${!ERROR_PATTERNS[@]}"; do
  if grep -qE "$pattern" "$ERROR_LOG" 2>/dev/null; then
    FOUND_PATTERNS+=("$pattern")
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Known Error Pattern Detected"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${ERROR_PATTERNS[$pattern]}"
    echo ""
  fi
done

if [[ ${#FOUND_PATTERNS[@]} -eq 0 ]]; then
  echo "❓ No known error patterns detected"
  echo ""
  echo "**This may be a new type of failure**"
  echo ""
  echo "🔍 **Top error lines**:"
  echo '```'
  grep -iE "(error|failed|panic|fatal)" "$ERROR_LOG" 2>/dev/null | head -10 || echo "No obvious errors found in pattern search"
  echo '```'
  echo ""
  echo "💡 **Debugging Tips**:"
  echo "- Check full build log for context"
  echo "- Look for the first error (subsequent errors may be cascading)"
  echo "- Search GitHub issues for similar errors"
  echo "- Consider adding this pattern to the knowledge base"
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✨ Found ${#FOUND_PATTERNS[@]} known error pattern(s)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
