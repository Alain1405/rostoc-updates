# CI Logging & Artifact Improvements Proposal

## Problem Statement

Current CI failures (like https://github.com/Alain1405/rostoc-updates/actions/runs/20758186226) lack transparency:

1. **Build logs disappear** - When a build step fails, the log file may not be uploaded as an artifact
2. **No diagnostic context** - Missing environment info, disk space, installed tool versions
3. **Unclear failure points** - Hard to determine which exact step failed and why
4. **Lost partial artifacts** - If build fails mid-process, any generated files are lost
5. **No step summaries** - GitHub Actions STEP_SUMMARY feature not utilized for quick debugging

## Proposed Improvements

### 1. Always Upload Build Logs (Highest Priority)

**Problem**: Currently, `build-${PLATFORM}-${ARCH}.log` is only uploaded if the build succeeds.

**Solution**: Add `if: always()` to log upload steps.

**Implementation** - Add to [.github/workflows/build.yml](../.github/workflows/build.yml) after the compile step:

```yaml
      # --- Phase 2: Compile (Python, build, stage) ---
      - uses: ./.github/actions/build-compile
        id: compile
        with:
          platform: ${{ matrix.platform }}
          arch: ${{ matrix.arch }}
          # ... other inputs ...

      # --- Upload build logs IMMEDIATELY (even on failure) ---
      - name: Upload build logs (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-logs-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}-${{ github.run_number }}
          path: |
            private-src/build-*.log
            private-src/*.log
          retention-days: 14
          if-no-files-found: warn

      # --- Phase 3: Sign & Validate (macOS-specific) ---
      - uses: ./.github/actions/build-sign-validate
        # ...
```

**Benefits**:
- ✅ Logs captured even if build/sign/test steps fail
- ✅ Multiple log files captured (build logs, any error logs)
- ✅ Unique names prevent conflicts across matrix jobs
- ✅ 14-day retention for debugging

---

### 2. Add Step Summaries for Quick Debugging

**Problem**: Need to dig through logs to find key information.

**Solution**: Use `GITHUB_STEP_SUMMARY` to display critical info in workflow UI.

**Implementation** - Add to [scripts/ci/execute_build.sh](../scripts/ci/execute_build.sh):

```bash
#!/usr/bin/env bash
set -euo pipefail

# ... existing code ...

echo "[INFO] Starting build — output will be saved to ${LOG_FILE}"
${BUILD_COMMAND} 2>&1 | tee "${LOG_FILE}"
BUILD_EXIT_CODE=$?

# Generate step summary (visible in GitHub Actions UI)
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Build Summary: ${PLATFORM} ${ARCH}"
    echo ""
    echo "**Exit Code**: ${BUILD_EXIT_CODE}"
    echo "**Variant**: ${ROSTOC_APP_VARIANT}"
    echo "**Config**: ${TAURI_CONFIG_FLAG:-<base config>}"
    echo ""
    
    if [[ ${BUILD_EXIT_CODE} -eq 0 ]]; then
      echo "### ✅ Build Succeeded"
      echo ""
      echo "**Artifacts Created**:"
      
      # List created artifacts
      if [[ "${PLATFORM}" == "macos" ]]; then
        find src-tauri/target/release/bundle -name "*.dmg" -o -name "*.app.tar.gz" 2>/dev/null | while read -r artifact; do
          SIZE=$(stat -f%z "$artifact" 2>/dev/null || stat -c%s "$artifact" 2>/dev/null || echo "0")
          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "- \`$(basename "$artifact")\` (${SIZE_MB} MB)"
        done
      elif [[ "${PLATFORM}" == "windows" ]]; then
        find src-tauri/target -name "*.msi" -o -name "*.msi.zip" 2>/dev/null | while read -r artifact; do
          SIZE=$(stat -c%s "$artifact" 2>/dev/null || echo "0")
          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "- \`$(basename "$artifact")\` (${SIZE_MB} MB)"
        done
      elif [[ "${PLATFORM}" == "linux" ]]; then
        find src-tauri/target -name "*.AppImage" 2>/dev/null | while read -r artifact; do
          SIZE=$(stat -c%s "$artifact" 2>/dev/null || echo "0")
          SIZE_MB=$((SIZE / 1024 / 1024))
          echo "- \`$(basename "$artifact")\` (${SIZE_MB} MB)"
        done
      fi
    else
      echo "### ❌ Build Failed"
      echo ""
      echo "**Last 50 lines of build log**:"
      echo '```'
      tail -50 "${LOG_FILE}" || echo "(log file not found)"
      echo '```'
      echo ""
      echo "📎 Full build log available as artifact: \`build-logs-${PLATFORM}-${ARCH}\`"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "${BUILD_EXIT_CODE}"
```

**Benefits**:
- ✅ Quick visual indication of success/failure
- ✅ Artifact list visible without downloading logs
- ✅ Last 50 lines of error output inline
- ✅ Links to full logs for deep investigation

---

### 3. Capture Diagnostic Environment Info

**Problem**: When builds fail, we don't know system state (disk space, tool versions, env vars).

**Solution**: Add pre-build diagnostic step that captures environment.

**Implementation** - Add to [.github/actions/build-compile/action.yml](../.github/actions/build-compile/action.yml):

```yaml
    - name: Capture diagnostic environment info
      if: always()
      shell: bash
      working-directory: private-src
      run: |
        {
          echo "# Build Environment Diagnostics"
          echo ""
          echo "**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
          echo "**Runner**: ${{ runner.os }} ${{ runner.arch }}"
          echo "**Platform**: ${{ inputs.platform }}"
          echo "**Architecture**: ${{ inputs.arch }}"
          echo "**Variant**: ${ROSTOC_APP_VARIANT}"
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
          
          if [[ "${{ inputs.platform }}" == "macos" ]]; then
            echo "- codesign: $(codesign --version 2>&1 | head -1 || echo 'not available')"
            echo "- xcrun: $(xcrun --version 2>&1 || echo 'not available')"
          fi
          echo ""
          
          echo "## Environment Variables"
          echo '```'
          env | grep -E '^(ROSTOC|TAURI|SENTRY|GITHUB|RUNNER)' | sort || true
          echo '```'
          echo ""
          
          echo "## Available Tauri Configs"
          find src-tauri -maxdepth 1 -name "tauri*.json" -exec basename {} \; | sort
          echo ""
          
          echo "## Python Runtime Status"
          if [[ -d "build/runtime_staging" ]]; then
            echo "Runtime staged: YES"
            find build/runtime_staging -type f -name "python*" -o -name "*.dll" -o -name "*.dylib" | head -20
          else
            echo "Runtime staged: NO"
          fi
        } > diagnostics-${{ inputs.platform }}-${{ inputs.arch }}.md

    - name: Upload diagnostic info
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: diagnostics-${{ matrix.variant }}-${{ inputs.platform }}-${{ inputs.arch }}-${{ github.run_number }}
        path: private-src/diagnostics-*.md
        retention-days: 14
        if-no-files-found: warn
```

**Benefits**:
- ✅ Immediate access to environment state
- ✅ Compare successful vs failed builds
- ✅ Identify tool version mismatches
- ✅ Disk space issues visible upfront

---

### 4. Upload Partial Artifacts on Failure

**Problem**: If build fails after creating some artifacts (e.g., DMG created but signing fails), those artifacts are lost.

**Solution**: Upload partial artifacts with `if: always()`.

**Implementation** - Add to [.github/workflows/build.yml](../.github/workflows/build.yml):

```yaml
      # --- Phase 5: Artifacts (locate, prepare, upload) ---
      - uses: ./.github/actions/build-artifacts
        id: artifacts
        with:
          platform: ${{ matrix.platform }}
          arch: ${{ matrix.arch }}
          # ... other inputs ...

      # --- Upload partial artifacts on failure ---
      - name: Upload partial artifacts (if build failed)
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: partial-artifacts-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}-${{ github.run_number }}
          path: |
            private-src/src-tauri/target/release/bundle/**/*.dmg
            private-src/src-tauri/target/release/bundle/**/*.app
            private-src/src-tauri/target/release/bundle/**/*.msi
            private-src/src-tauri/target/release/bundle/**/*.msi.zip
            private-src/src-tauri/target/release/bundle/**/*.AppImage
            private-src/src-tauri/target/release/bundle/**/*.sig
            private-src/updates/**/*
          retention-days: 7
          if-no-files-found: ignore

      # --- Upload codesigning logs (macOS failures) ---
      - name: Upload codesign logs (macOS)
        if: failure() && matrix.platform == 'macos'
        uses: actions/upload-artifact@v4
        with:
          name: codesign-logs-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}-${{ github.run_number }}
          path: |
            private-src/codesign-*.log
            private-src/*.codesign
          retention-days: 7
          if-no-files-found: ignore
```

**Benefits**:
- ✅ Inspect partially built artifacts
- ✅ Debug signing/packaging issues
- ✅ Compare failed vs successful builds
- ✅ Don't lose work from long builds

---

### 5. Structured Error Capture

**Problem**: Errors are buried in logs; hard to extract root cause.

**Solution**: Capture specific error patterns and surface them.

**Implementation** - Add to [scripts/ci/execute_build.sh](../scripts/ci/execute_build.sh):

```bash
#!/usr/bin/env bash
set -euo pipefail

# ... existing code ...

echo "[INFO] Starting build — output will be saved to ${LOG_FILE}"
${BUILD_COMMAND} 2>&1 | tee "${LOG_FILE}"
BUILD_EXIT_CODE=$?

# Extract and highlight errors
if [[ ${BUILD_EXIT_CODE} -ne 0 ]]; then
  ERROR_LOG="errors-${PLATFORM}-${ARCH}.txt"
  {
    echo "=== ERRORS DETECTED IN BUILD ==="
    echo ""
    
    # Rust compilation errors
    grep -A 5 "^error\[E[0-9]\+\]:" "${LOG_FILE}" 2>/dev/null | head -100 || true
    
    # Rust panic messages
    grep -A 10 "thread '.*' panicked" "${LOG_FILE}" 2>/dev/null || true
    
    # Python errors
    grep -A 10 "Traceback (most recent call last):" "${LOG_FILE}" 2>/dev/null || true
    
    # Tauri errors
    grep -A 5 "Error:" "${LOG_FILE}" 2>/dev/null | grep -v "^--$" || true
    
    # Platform-specific
    if [[ "${PLATFORM}" == "macos" ]]; then
      grep -A 5 "codesign.*failed" "${LOG_FILE}" 2>/dev/null || true
      grep -A 5 "errSecInternalComponent" "${LOG_FILE}" 2>/dev/null || true
    elif [[ "${PLATFORM}" == "windows" ]]; then
      grep -A 5 "LINK : fatal error" "${LOG_FILE}" 2>/dev/null || true
      grep -A 5 "MSBuild.*failed" "${LOG_FILE}" 2>/dev/null || true
    fi
    
    echo ""
    echo "=== END ERRORS ==="
  } > "${ERROR_LOG}"
  
  # Add errors to step summary
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo ""
      echo "### 🔍 Extracted Errors"
      echo '```'
      cat "${ERROR_LOG}"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  
  # Output to console for quick reference
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "[ERROR] Build failed. Error summary saved to ${ERROR_LOG}"
  cat "${ERROR_LOG}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit "${BUILD_EXIT_CODE}"
```

**Benefits**:
- ✅ Errors extracted and highlighted
- ✅ Platform-specific error patterns captured
- ✅ Errors visible in step summary
- ✅ Separate error log for quick download

---

### 6. Build Comparison Tool

**Problem**: Hard to compare successful vs failed builds to identify what changed.

**Solution**: Create a build fingerprint for comparison.

**Implementation** - Add to [.github/actions/build-compile/action.yml](../.github/actions/build-compile/action.yml):

```yaml
    - name: Generate build fingerprint
      shell: bash
      working-directory: private-src
      run: |
        {
          echo "# Build Fingerprint"
          echo "timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
          echo "platform: ${{ inputs.platform }}"
          echo "arch: ${{ inputs.arch }}"
          echo "variant: ${ROSTOC_APP_VARIANT}"
          echo "runner_os: ${{ runner.os }}"
          echo "github_sha: ${{ github.sha }}"
          echo "github_run_number: ${{ github.run_number }}"
          echo ""
          echo "# Dependencies"
          echo "package_json_hash: $(shasum package.json | awk '{print $1}')"
          echo "cargo_lock_hash: $(shasum src-tauri/Cargo.lock | awk '{print $1}')"
          echo "pnpm_lock_hash: $(shasum pnpm-lock.yaml | awk '{print $1}')"
          echo ""
          echo "# Tool Versions"
          echo "node: $(node --version 2>/dev/null || echo 'unknown')"
          echo "rust: $(rustc --version 2>/dev/null || echo 'unknown')"
          echo "python: $(python3 --version 2>/dev/null || echo 'unknown')"
          echo ""
          echo "# Config Selection"
          echo "tauri_config: ${TAURI_CONFIG_FLAG:-<base>}"
          if [[ -n "${TAURI_CONFIG_FLAG}" && -f "${TAURI_CONFIG_FLAG}" ]]; then
            echo "config_hash: $(shasum "${TAURI_CONFIG_FLAG}" | awk '{print $1}')"
          fi
        } > build-fingerprint.txt

    - name: Upload build fingerprint
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: fingerprint-${{ matrix.variant }}-${{ inputs.platform }}-${{ inputs.arch }}-${{ github.run_number }}
        path: private-src/build-fingerprint.txt
        retention-days: 30
        if-no-files-found: warn
```

**Benefits**:
- ✅ Quickly identify what changed between builds
- ✅ Compare failed vs successful fingerprints
- ✅ Track dependency updates
- ✅ Debug "works on my machine" issues

---

## Implementation Priority

### Phase 1: Critical (Implement ASAP)
1. ✅ **Always upload build logs** - #1 above (5 minutes)
2. ✅ **Add step summaries** - #2 above (15 minutes)
3. ✅ **Upload partial artifacts** - #4 above (10 minutes)

### Phase 2: High Value (Next Sprint)
4. ✅ **Capture diagnostic info** - #3 above (20 minutes)
5. ✅ **Structured error capture** - #5 above (30 minutes)

### Phase 3: Nice to Have (Future)
6. ✅ **Build fingerprint tool** - #6 above (30 minutes)
7. ⏳ **Automated diff comparison** - Compare fingerprints across runs (2 hours)
8. ⏳ **Slack/Discord notifications** - Post failures to team chat (1 hour)

---

## Testing Plan

### 1. Test with Intentional Failure

```bash
# In rostoc private repo
# Add intentional compile error
echo 'fn broken() { undefined_function(); }' >> src-tauri/src/lib.rs

# Commit and push to trigger CI
git commit -am "test: Intentional build failure for CI logging test"
git push origin test/ci-logging

# Verify:
# 1. Build logs uploaded despite failure
# 2. Step summary shows error excerpt
# 3. Diagnostic info captured
# 4. Partial artifacts present (if any)
```

### 2. Compare Before/After

1. Run workflow with old code → check artifacts
2. Implement improvements
3. Run same failing build → verify new artifacts present
4. Compare time to debug: should be significantly faster

### 3. Metrics to Track

- **Time to identify root cause**: Before vs After
- **Number of log downloads needed**: Should decrease
- **CI investigation steps**: Document workflow improvement

---

## Example: Debugging with New System

**Old workflow** (workflow run 20758186226):
1. Go to Actions tab
2. Click failed run
3. Click failed job
4. Scroll through 10,000+ lines of logs
5. Search for "error"
6. Download build logs if available (often missing)
7. Repeat for each failed platform

**Time**: 20-30 minutes per failed build

**New workflow**:
1. Go to Actions tab
2. Click failed run
3. Read step summary (shows error excerpt + artifacts created)
4. Download `build-logs-*` artifact (always present)
5. Download `diagnostics-*` artifact (shows environment)
6. Download `errors-*` artifact (extracted error patterns)
7. Compare `fingerprint-*` with last successful build

**Time**: 5-10 minutes per failed build

**Improvement**: 2-3x faster debugging

---

## Related Documentation

- [LOCAL_CI_TESTING.md](./LOCAL_CI_TESTING.md) - Local testing strategies
- [CI_DEBUGGING_WITH_COPILOT.md](./CI_DEBUGGING_WITH_COPILOT.md) - Using Copilot to debug CI
- [ENV_VAR_TESTING_SUMMARY.md](./ENV_VAR_TESTING_SUMMARY.md) - Environment variable testing

---

## Open Questions

1. **Artifact retention**: Should we keep fingerprints longer than 30 days?
2. **Cost**: Will uploading more artifacts increase GitHub storage costs significantly?
3. **Notification strategy**: Where should failure alerts go? Slack? Email? GitHub Discussions?
4. **Automated analysis**: Should we build a tool to auto-compare fingerprints?

---

## Next Steps

1. Review this proposal with team
2. Implement Phase 1 changes (always upload logs + step summaries)
3. Test with intentional failure
4. Gather feedback from first real failure
5. Iterate and implement Phase 2
