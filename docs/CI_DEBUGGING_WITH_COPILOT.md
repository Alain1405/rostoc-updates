# CI Debugging with GitHub Copilot - Best Practices Guide

## 📋 Table of Contents

1. [Overview](#overview)
2. [Current Pain Points](#current-pain-points)
3. [Logging Best Practices](#logging-best-practices)
4. [Artifact Strategy](#artifact-strategy)
5. [Workflow Naming & Organization](#workflow-naming--organization)
6. [Using GitHub MCP Tools](#using-github-mcp-tools)
7. [Using gh CLI Effectively](#using-gh-cli-effectively)
8. [Debugging Workflow - Step by Step](#debugging-workflow---step-by-step)
9. [Quick Reference Commands](#quick-reference-commands)

---

## Overview

This guide addresses challenges when debugging multi-repo GitHub Actions workflows with Copilot, focusing on:
- **Multi-workflow architecture** (9 workflows in `rostoc-updates`, 3 in `rostoc`)
- **Multi-repo setup** (private `rostoc` dispatches to public `rostoc-updates`)
- **Logging gaps** (Unicode errors, missing artifacts, scattered logs)
- **Copilot integration** (GitHub MCP + gh CLI)

---

## Current Pain Points

### 1. **Unicode Logging Errors on Windows**

**Issue**: Windows builds fail with `UnicodeDecodeError` when Python subprocess output contains non-ASCII characters (see `build-windows-x86_64 2.log:190`):

```
UnicodeDecodeError: 'charmap' codec can't decode byte 0x8f in position 862853: character maps to <undefined>
```

**Root Cause**: Python subprocess on Windows defaults to `cp1252` encoding, but build tools output UTF-8.

**Fix**: Set UTF-8 encoding explicitly in build scripts:

```python
# In scripts/build.py or scripts/ci/execute_build.sh wrapper
import os
os.environ['PYTHONIOENCODING'] = 'utf-8'

# Or in subprocess calls
subprocess.run(cmd, encoding='utf-8', errors='replace')
```

**Workflow Integration**:
```yaml
- name: Set UTF-8 encoding (Windows)
  if: runner.os == 'Windows'
  shell: pwsh
  run: |
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    echo "PYTHONIOENCODING=utf-8" >> $env:GITHUB_ENV
```

### 2. **Build Logs Not Captured as Artifacts**

**Current State**: Your build workflow uploads logs only conditionally:

```yaml
# .github/workflows/build.yml:103
- name: Upload build logs (pre-tests)
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: build-logs-pre-tests-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}
    path: private-src/build-${{ matrix.platform }}-${{ matrix.arch }}.log
    retention-days: 7
    if-no-files-found: warn
```

**Problem**: If the build crashes before creating the log file, no artifact is uploaded.

**Best Practice**: Add multiple log capture points:

```yaml
# Add to build.yml after each major phase
- name: Capture logs (Phase 1 - Prep)
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: logs-prep-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}
    path: |
      private-src/*.log
      ~/.npm/_logs/*.log
      ~/Library/Logs/Rostoc/*.log  # macOS
      $env:APPDATA/Rostoc/logs/*.log  # Windows
    retention-days: 7
    if-no-files-found: ignore  # Don't fail if some paths missing
```

### 3. **Scattered Logs Across Multiple Jobs**

**Problem**: Logs are split across setup → build → publish → finalize jobs, making it hard to trace end-to-end failures.

**Solution**: Use `GITHUB_STEP_SUMMARY` for centralized logging:

```yaml
- name: Log build context
  shell: bash
  run: |
    cat >> "$GITHUB_STEP_SUMMARY" <<EOF
    ## 🏗️ Build Context
    - **Variant**: ${{ matrix.variant }}
    - **Platform**: ${{ matrix.platform }}-${{ matrix.arch }}
    - **Commit**: \`${{ inputs.commit_sha }}\`
    - **Release**: ${{ inputs.is_release }}
    - **Runner**: ${{ runner.os }}
    EOF
```

---

## Logging Best Practices

### 1. **Structured Logging Pattern**

Use consistent emoji prefixes and structured output:

```bash
# In CI scripts (scripts/ci/*.sh)
log_info() {
  echo "ℹ️  [INFO] $*"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] INFO: $*" >> "$LOG_FILE"
}

log_error() {
  echo "❌ [ERROR] $*" >&2
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >> "$LOG_FILE"
}

log_debug() {
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "🐛 [DEBUG] $*"
  fi
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DEBUG: $*" >> "$LOG_FILE"
}
```

### 2. **Capture Full Context on Failure**

```yaml
- name: Capture failure context
  if: failure()
  shell: bash
  run: |
    {
      echo "## ⚠️ Build Failed"
      echo "**Job**: ${{ github.job }}"
      echo "**Step**: ${{ github.action }}"
      echo "**Time**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo ""
      echo "### Environment"
      echo '```'
      env | grep -E 'ROSTOC|TAURI|GITHUB' | sort
      echo '```'
      echo ""
      echo "### Disk Space"
      df -h
      echo ""
      echo "### Recent Logs"
      echo '```'
      tail -n 100 private-src/build-*.log 2>/dev/null || echo "No build logs found"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
```

### 3. **Persistent Log Files**

Create timestamped log files that survive job restarts:

```bash
# scripts/ci/execute_build.sh
LOG_DIR="${GITHUB_WORKSPACE}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S)-$PLATFORM-$ARCH.log"

# Tee all output to log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Ensure log is uploaded even on crash
trap 'upload_logs' EXIT
```

---

## Artifact Strategy

### Current Gaps

Your workflows have incomplete artifact coverage:

| Phase | Artifacts Captured | Missing |
|-------|-------------------|---------|
| **Setup** | None | Lint/test results |
| **Build** | Pre-test logs only | Post-test logs, intermediate builds |
| **Publish** | JSON manifests | Upload logs, backend responses |
| **Finalize** | None | Status update logs |

### Recommended Artifact Matrix

```yaml
# Add to each workflow phase
artifacts:
  setup:
    - lint-results.json
    - test-results.xml
    - private-src-checkout.log
  
  build:
    - build-logs-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}.log
    - python-stage-manifest.json
    - cargo-build.log
    - codesign-verify.log  # macOS only
    - smoke-test-results.txt
  
  publish:
    - releases.json
    - latest.json
    - backend-publish-response.json
    - spaces-upload.log
  
  finalize:
    - status-update-response.json
    - summary.md
```

### Upload Pattern

```yaml
- name: Upload comprehensive artifacts
  if: always()  # CRITICAL - captures artifacts even on failure
  uses: actions/upload-artifact@v4
  with:
    name: ${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}-logs-and-artifacts
    path: |
      private-src/**/*.log
      private-src/build/**/*.json
      logs/
      !private-src/target/  # Exclude large build dirs
      !private-src/node_modules/
    retention-days: 30  # Increase for release builds
    compression-level: 6  # Balance speed vs size
```

---

## Workflow Naming & Organization

### Current Structure (Confusing)

```
rostoc-updates/
  .github/workflows/
    build.yml                    ❓ Reusable or dispatch?
    build-and-publish.yml        ❓ Entry point or orchestrator?
    ci-dispatch.yml              ❓ What triggers this?
    release-dispatch.yml         ❓ vs ci-dispatch?
    
rostoc/
  .github/workflows/
    trigger-public-build.yml     ❓ How does this relate to above?
    ci-build.yml                 ❓ Same as ci-dispatch?
```

### Recommended Naming Convention

```
rostoc-updates/ (PUBLIC REPO)
  .github/workflows/
    # ENTRY POINTS (workflow_dispatch + workflow_call)
    0-orchestrator-build-and-publish.yml  # Main entry
    
    # REUSABLE WORKFLOWS (workflow_call only)
    1-setup.yml
    2-build.yml
    3-publish.yml
    4-finalize.yml
    
    # DISPATCHERS (triggered by private repo)
    dispatch-ci.yml
    dispatch-release.yml
    
    # UTILITY WORKFLOWS
    util-staple-dmg.yml
    util-deploy-storybook.yml

rostoc/ (PRIVATE REPO)
  .github/workflows/
    # TRIGGERS (dispatch to public repo)
    trigger-ci-build.yml
    trigger-release-build.yml
```

**Naming Rules:**
- **Prefix numbers** indicate execution order
- **`orchestrator-`** = main entry point
- **`dispatch-`** = receives external trigger
- **`trigger-`** = sends dispatch to another repo
- **`util-`** = standalone utility workflow

### Add Workflow Descriptions

```yaml
# Add to EVERY workflow file
name: "2 - Build Desktop (Reusable)"

on:
  workflow_call:
    # ... inputs

# Add description in README
# This workflow is called by 0-orchestrator-build-and-publish.yml
# and handles matrix builds for all platforms
```

---

## Using GitHub MCP Tools

### Available Tools (from your setup)

```typescript
// Activate GitHub tools in Copilot
mcp_github_github_actions_list()      // List workflows, runs, jobs, artifacts
mcp_github_github_actions_get()       // Get workflow details
mcp_github_github_get_job_logs()      // Download job logs
mcp_github_github_search_issues()     // Search issues/PRs
```

### Example Queries for Copilot

**1. Find recent failed workflows:**
```
@workspace Can you find the last 5 failed workflow runs for rostoc-updates 
using the GitHub MCP tool?
```

**2. Get detailed logs from a specific run:**
```
@workspace Get the full job logs for run 12345 in rostoc-updates, 
focusing on the Windows x64 build job
```

**3. Download artifacts from failed run:**
```
@workspace Download all artifacts from workflow run 12345 and 
extract the build logs for Windows x64
```

### Automate with Scripts

```bash
# scripts/ci/debug_latest_failure.sh
#!/usr/bin/env bash
set -euo pipefail

REPO="Alain1405/rostoc-updates"

# Get latest failed run
RUN_ID=$(gh run list --repo "$REPO" --status failure --limit 1 --json databaseId --jq '.[0].databaseId')

if [[ -z "$RUN_ID" ]]; then
  echo "No failed runs found"
  exit 0
fi

echo "🔍 Analyzing failed run: $RUN_ID"

# Download all logs
gh run download "$RUN_ID" --repo "$REPO" --dir /tmp/debug-$RUN_ID

# Extract build logs
find /tmp/debug-$RUN_ID -name 'build-*.log' -exec echo "Found: {}" \;

# Search for common errors
echo ""
echo "❌ Errors found:"
grep -r "ERROR\|Error\|error" /tmp/debug-$RUN_ID --color=always | head -20
```

---

## Using gh CLI Effectively

### Essential Commands

```bash
# 1. Watch live workflow execution
gh run watch --repo Alain1405/rostoc-updates

# 2. Get logs from specific job (avoid downloading artifacts)
gh run view 12345 --repo Alain1405/rostoc-updates --log --job 67890

# 3. Filter logs for errors only
gh run view 12345 --log-failed | grep -A 5 "UnicodeDecodeError"

# 4. List recent runs with custom fields
gh run list --repo Alain1405/rostoc-updates --limit 10 \
  --json databaseId,event,status,conclusion,displayTitle,createdAt \
  --jq '.[] | "\(.databaseId)\t\(.status)\t\(.displayTitle)"'

# 5. Re-run failed jobs only (save time!)
gh run rerun 12345 --repo Alain1405/rostoc-updates --failed

# 6. Download specific artifact by name
gh run download 12345 --repo Alain1405/rostoc-updates \
  --name 'build-logs-pre-tests-production-windows-x86_64'
```

### Create Aliases

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Rostoc CI shortcuts
alias gh-rostoc-runs='gh run list --repo Alain1405/rostoc-updates'
alias gh-rostoc-latest='gh run view --repo Alain1405/rostoc-updates $(gh run list --repo Alain1405/rostoc-updates --limit 1 --json databaseId --jq ".[0].databaseId")'
alias gh-rostoc-logs='gh run view --repo Alain1405/rostoc-updates --log'
alias gh-rostoc-download='gh run download --repo Alain1405/rostoc-updates -D ~/Downloads/ci-artifacts'

# Usage:
# gh-rostoc-latest      -> View latest run
# gh-rostoc-logs 12345  -> View logs for run 12345
```

---

## Debugging Workflow - Step by Step

### Phase 1: Identify the Failure

```bash
# 1. List recent runs
gh run list --repo Alain1405/rostoc-updates --limit 10

# 2. Identify failed run (look for ❌ or conclusion: failure)
gh run view 12345 --repo Alain1405/rostoc-updates

# 3. Find specific failed job
gh run view 12345 --repo Alain1405/rostoc-updates --json jobs \
  --jq '.jobs[] | select(.conclusion == "failure") | .name'
```

### Phase 2: Gather Context

```bash
# 1. Download job logs
gh run view 12345 --job 67890 --log > /tmp/failed-job.log

# 2. Download all artifacts
gh run download 12345 --repo Alain1405/rostoc-updates

# 3. Extract relevant sections
# Search for error patterns
grep -n "Error\|Exception\|Failed\|UnicodeDecodeError" /tmp/failed-job.log

# Get context around first error
grep -B 10 -A 20 "Error" /tmp/failed-job.log | head -50
```

### Phase 3: Reproduce Locally

```bash
# Use your existing local testing infrastructure
cd /Users/alainscialoja/code/new-coro/rostoc-updates

# 1. Validate scripts first
make format && make lint && make validate-paths && make test-env

# 2. Test specific script from failed job
./scripts/ci/test_locally.sh execute_build.sh

# 3. Set same environment as CI
export ROSTOC_APP_VARIANT="production"
export PLATFORM="windows"
export ARCH="x86_64"

# 4. Run build script with debug output
DEBUG=true bash -x scripts/ci/execute_build.sh
```

### Phase 4: Ask Copilot for Help

**Template for Copilot Queries:**

```
@workspace I'm debugging a CI failure in rostoc-updates workflow run 12345.

**Context:**
- Workflow: build-and-publish.yml
- Job: build-desktop (Windows x64)
- Error: UnicodeDecodeError in Python subprocess output
- Log file: /Users/alainscialoja/Downloads/build-windows-x86_64 2.log:190

**Actions taken:**
1. Downloaded logs with gh CLI
2. Identified error at line 190
3. Found similar issue in [link to previous investigation]

**Questions:**
1. How should we handle UTF-8 encoding in Windows subprocess calls?
2. Where should we set PYTHONIOENCODING in our build scripts?
3. Can you update scripts/ci/execute_build.sh with the fix?
4. Should we add a pre-build validation step to check encoding settings?

Please search our docs/ folder for previous encoding fixes and apply the pattern consistently.
```

**Copilot can:**
- ✅ Search your codebase for similar issues (`semantic_search`)
- ✅ Read your documentation (`read_file` on docs/)
- ✅ Propose fixes with context (`multi_replace_string_in_file`)
- ✅ Query GitHub API via MCP tools
- ❌ Cannot directly test code (use local testing)
- ❌ Cannot access private workflow secrets

---

## Quick Reference Commands

### Investigation

```bash
# Latest failed run details
gh run list --repo Alain1405/rostoc-updates --status failure --limit 1

# Get run ID quickly
RUN_ID=$(gh run list --repo Alain1405/rostoc-updates --limit 1 --json databaseId --jq '.[0].databaseId')

# View full workflow tree
gh run view $RUN_ID --repo Alain1405/rostoc-updates

# Get specific job logs (find job ID first)
gh api repos/Alain1405/rostoc-updates/actions/runs/$RUN_ID/jobs \
  --jq '.jobs[] | "\(.id) \(.name) \(.conclusion)"'

# Download logs without artifacts (faster)
gh run view $RUN_ID --log > /tmp/full-run.log
```

### Debugging

```bash
# Search logs for patterns
gh run view $RUN_ID --log | grep -C 5 "ERROR\|Exception\|Failed"

# Find which step failed
gh run view $RUN_ID --json jobs \
  --jq '.jobs[].steps[] | select(.conclusion == "failure") | {name, conclusion}'

# Download specific artifact
gh api repos/Alain1405/rostoc-updates/actions/runs/$RUN_ID/artifacts \
  --jq '.artifacts[] | "\(.id) \(.name)"'

gh api repos/Alain1405/rostoc-updates/actions/artifacts/$ARTIFACT_ID/zip > artifact.zip
```

### Re-running

```bash
# Re-run all jobs
gh run rerun $RUN_ID --repo Alain1405/rostoc-updates

# Re-run only failed jobs (recommended)
gh run rerun $RUN_ID --repo Alain1405/rostoc-updates --failed

# Cancel in-progress run
gh run cancel $RUN_ID --repo Alain1405/rostoc-updates
```

### Status Checking

```bash
# Check commit status
gh api repos/alain1405/rostoc/commits/$COMMIT_SHA/status

# Watch workflow completion
gh run watch --repo Alain1405/rostoc-updates

# Get workflow duration
gh run view $RUN_ID --json jobs \
  --jq '.jobs[] | {name: .name, duration: (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)}'
```

---

## Recommendations Summary

### Immediate Actions (High Impact)

1. **Fix Unicode Logging** (affects all Windows builds)
   - Add `PYTHONIOENCODING=utf-8` to Windows jobs
   - Update `subprocess.run()` calls to specify `encoding='utf-8'`

2. **Add Comprehensive Log Uploads**
   - Upload logs at each phase (prep, compile, test, publish)
   - Use `if: always()` to capture artifacts on failure
   - Include `GITHUB_STEP_SUMMARY` for centralized context

3. **Rename Workflows** (improves Copilot understanding)
   - Use numbered prefixes: `0-orchestrator`, `1-setup`, `2-build`, etc.
   - Add clear descriptions in workflow files
   - Document workflow relationships in README

4. **Create Debug Automation Scripts**
   - `scripts/ci/debug_latest_failure.sh` - Auto-download and analyze
   - `scripts/ci/compare_runs.sh` - Compare successful vs failed runs
   - Aliases for common gh CLI commands

### Medium-Term Improvements

5. **Centralized Logging Service**
   - Consider external log aggregation (e.g., CloudWatch, Datadog)
   - Or upload all logs to DigitalOcean Spaces for long-term retention

6. **Better Artifact Organization**
   - Use consistent naming: `{phase}-{variant}-{platform}-{arch}-{type}`
   - Create artifact index in workflow summary
   - Auto-clean old artifacts (retention policies)

7. **Enhanced Monitoring**
   - Add workflow duration tracking
   - Set up alerts for repeated failures
   - Track success rate by platform/variant

### Long-Term Goals

8. **Unified Dashboard**
   - Build status page that aggregates both repos
   - Show real-time progress for matrix builds
   - Link to logs and artifacts from one place

9. **Improved Local Testing**
   - Expand `test_locally.sh` to simulate full build phases
   - Add Docker containers for Windows/Linux testing on Mac
   - Pre-commit hooks for workflow validation

10. **Documentation Improvements**
    - Update copilot-instructions.md with logging patterns
    - Add troubleshooting section with common errors
    - Maintain runbook for each workflow

---

## Related Documentation

- [LOCAL_CI_TESTING.md](./LOCAL_CI_TESTING.md) - Local testing strategies
- [WORKFLOW_DECOMPOSITION.md](../WORKFLOW_DECOMPOSITION.md) - Workflow architecture
- [CI_SCRIPT_PATH_FIX.md](./CI_SCRIPT_PATH_FIX.md) - Script path debugging
- [ENV_VAR_TESTING_SUMMARY.md](./ENV_VAR_TESTING_SUMMARY.md) - Environment variable patterns

---

## Support Resources

- **GitHub Actions Documentation**: https://docs.github.com/en/actions
- **gh CLI Manual**: https://cli.github.com/manual/
- **GitHub Actions Toolkit**: https://github.com/actions/toolkit
- **Act (Local Testing)**: https://github.com/nektos/act
- **actionlint**: https://github.com/rhysd/actionlint
