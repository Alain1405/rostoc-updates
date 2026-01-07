---
name: ci-debugging
description: Debug GitHub Actions CI failures using local testing, validation tools, and investigation workflows
argument-hint: CI run URL, job link, or description of the failure
---

# CI Debugging Guide

Diagnose and fix GitHub Actions CI failures using Rostoc's local testing tools and investigation workflows.

## Context

### Primary Documentation
- **Testing guide**: `rostoc-updates/docs/LOCAL_CI_TESTING.md` (comprehensive)
- **Quick reference**: `rostoc-updates/docs/LOCAL_CI_TESTING_CHEATSHEET.md`
- **Environment testing**: `rostoc-updates/docs/ENV_VAR_TESTING_SUMMARY.md`
- **CI instructions**: `rostoc-updates/.github/copilot-instructions.md`

### Key Tools & Files
- **Rostoc Makefile**: `rostoc/Makefile` (test, lint, format, check targets)
- **Updates Makefile**: `rostoc-updates/Makefile` (format, lint, validate-paths, test-env)
- **Pre-commit config**: `rostoc/.pre-commit-config.yaml` (local hooks)
- **Build script**: `rostoc/scripts/build.py` (main build orchestration)
- **CI scripts**: `rostoc-updates/scripts/ci/*.sh` (execute_build.sh, stage_and_verify_runtime.sh, etc.)

### GitHub Actions Workflows
- **Main workflows**: `rostoc-updates/.github/workflows/`
  - `build-and-publish.yml` (reusable build workflow)
  - `ci-dispatch.yml` (push/PR trigger)
  - `release-dispatch.yml` (tag trigger)
- **Composite actions**: `rostoc-updates/.github/actions/`

## Investigation Workflow

### 1. Identify Failure Type

**From GitHub UI**:
```bash
# Get run details with GitHub CLI
gh run view <RUN_ID> --repo Alain1405/rostoc-updates

# Get failed job logs
gh run view <RUN_ID> --log-failed > failed_logs.txt

# Search for specific error
gh run view <RUN_ID> --log | grep -A 10 "ERROR\|Error\|error"
```

**From Grafana Loki** (if logs were shipped):
```logql
# Search by run ID
{run_id="20774299981"}

# Search by platform and failure status
{platform="macos", status="failure"}

# Full-text search for errors
{run_id="20774299981"} |= "ERROR" |= "failed"
```

**Grafana access**: https://rostocci.grafana.net/explore

### 2. Common Failure Patterns

#### Lint/Type Check Failures

**Symptoms**:
- Job: `lint-and-tests`
- Step: "Run lint suite"
- Errors: Pyright, mypy, ruff, or shellcheck violations

**Local validation** (run BEFORE pushing):
```bash
cd rostoc/

# Full validation suite
make format && make lint && make check

# Individual checks
make lint-python     # ruff + mypy + pyright
make lint-ts         # TypeScript typecheck
make lint-rust       # cargo fmt --check
make test            # All test suites
```

**Pre-commit hooks** (automatic on commit):
- Configured in `rostoc/.pre-commit-config.yaml`
- Runs: ruff, pyright, prettier, rustfmt, python-compile, typescript-check
- Install: `pre-commit install` (if not already active)

#### Build Failures

**Symptoms**:
- Job: `build-<platform>-<arch>`
- Step: "Execute Build"
- Exit code: 1 (even if artifacts created)

**Common causes**:
1. **Malformed Python code**: Missing/incorrect subprocess parameters
2. **Missing sys.exit(0)**: Script succeeds but returns non-zero
3. **Environment variables**: Incorrect use of `${VAR:?}` vs `${VAR?}`
4. **Script path issues**: Relative paths broken by `working-directory`

**Local testing**:
```bash
cd rostoc/

# Activate virtual environment
source .venv/bin/activate

# Test build script locally
python scripts/build.py --locked --mode development

# Verify exit code
echo $?  # Should be 0 on success

# Quick validation (no full build)
cargo check --target aarch64-apple-darwin  # macOS
pnpm tsc --noEmit  # TypeScript
make test  # Python tests
```

**Reading build.py for issues**:
- Check for `sys.exit(0)` at script end
- Verify all subprocess.run() calls have complete parameters
- Look for malformed code from incomplete refactoring
- Ensure error paths call `sys.exit(1)`

#### Script Path Failures

**Symptoms**:
- Error: `script.sh: No such file or directory`
- Cause: `working-directory` changes relative path resolution

**Validation** (run BEFORE pushing):
```bash
cd rostoc-updates/

# Validate all script paths in workflows
make validate-paths

# Check specific workflow
scripts/ci/validate_workflow_paths.sh .github/workflows/build.yml
```

**Pattern to watch**:
```yaml
# ❌ WRONG: Path breaks with working-directory
working-directory: private-src
run: scripts/ci/my_script.sh

# ✅ CORRECT: Go up one level first
working-directory: private-src
run: ../scripts/ci/my_script.sh
```

#### Environment Variable Failures

**Symptoms**:
- Error: `TAURI_CONFIG_FLAG: parameter null or not set`
- Cause: Using `${VAR:?}` for variables that can be empty

**Validation** (run BEFORE pushing):
```bash
cd rostoc-updates/

# Test environment variable handling
make test-env

# Check specific script
scripts/ci/test_env_handling.sh scripts/ci/execute_build.sh
```

**Pattern to watch**:
```bash
# ❌ WRONG: Fails on empty values (production needs empty)
TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG:?TAURI_CONFIG_FLAG is required}

# ✅ CORRECT: Allows empty, fails only on unset
TAURI_CONFIG_FLAG=${TAURI_CONFIG_FLAG?TAURI_CONFIG_FLAG must be set}
```

**Variables that can be empty**:
- `TAURI_CONFIG_FLAG` (empty for production)
- `DEV_VERSION_SUFFIX` (empty for releases)
- `DEBUG_FLAG` (empty for production)

### 3. Pre-Push Validation Checklist

**Complete validation** (recommended workflow):
```bash
# In rostoc/ repo
cd rostoc/
make format && make lint && make check && make test

# In rostoc-updates/ repo (if modifying workflows/scripts)
cd ../rostoc-updates/
make format && make lint && make validate-paths && make test-env
```

**Quick validation** (faster iteration):
```bash
# Rostoc: Format + lint only
cd rostoc/
make format && make lint

# Updates: Workflow validation only
cd ../rostoc-updates/
make lint && make validate-paths
```

### 4. Local Testing Strategies

#### Direct Script Testing (Fastest - 30 seconds)

```bash
cd rostoc-updates/

# Set up mock CI environment
export GITHUB_WORKSPACE="$(pwd)"
export RUNNER_TEMP="/tmp/ci-test"
export RUNNER_OS="macOS"
export ROSTOC_APP_VARIANT="staging"

# Test script directly
bash -x scripts/ci/my_script.sh

# Or use test harness
./scripts/ci/test_locally.sh my_script.sh
```

#### Native Build Testing (20-30 minutes)

```bash
cd rostoc/

# Full build (matches CI)
source .venv/bin/activate
export ROSTOC_APP_VARIANT="production"
python scripts/build.py --locked
```

#### Interactive Debugging with tmate (CI runner access)

**Trigger debug session**:
```bash
# Add [debug] to commit message
git commit -m "fix: Debug CI issue [debug]"
git push origin your-branch
```

**Wait for failure**, then:
1. Go to https://github.com/Alain1405/rostoc-updates/actions
2. Open failed job
3. Find "Setup tmate session (debug mode)" step
4. Copy SSH command: `ssh <id>@nyc1.tmate.io`

**Debug in session**:
```bash
# Connect
ssh <id>@nyc1.tmate.io

# Navigate to build directory
cd private-src

# Inspect state
ls -lh src-tauri/target/release/bundle/
cat build-*.log

# Re-run commands
pnpm tauri build

# Test fixes
vim scripts/build.py
python scripts/build.py

# Exit when done
exit
```

**Remove [debug]** after fixing issue.

## Common Issues & Solutions

### Issue: Build Succeeds but Exit Code 1

**Common Cause**: Subprocess calls using `subprocess.run()` without `check=True` that exit with non-zero codes but don't raise exceptions.

**Diagnosis**:
```bash
# Search for subprocess calls without check=True
grep -n "subprocess.run" scripts/build.py

# Check error handling after each subprocess.run()
grep -B 5 -A 15 "subprocess.run" scripts/build.py

# Look for conditional error handling
grep -A 20 "result.returncode != 0" scripts/build.py
```

**Common Pattern**: Scripts with conditional error handling that swallows errors:
```python
result = subprocess.run(cmd, ...)
if result.returncode != 0:
    if os.environ.get("CI"):
        raise RuntimeError(...)  # Only raises in CI
    else:
        print("[WARN] ...")  # Local: just warns, doesn't raise!
```

**Solution** - Ensure subprocess errors always propagate:
```python
if result.returncode != 0:
    bundler = RuntimeBundler(target=self.target)
    exe_path = bundler._find_rostoc_exe()
    
    if os.environ.get("CI"):
        # CI: Always fail on non-zero
        raise RuntimeError(f"Build failed with exit code {result.returncode}")
    elif exe_path and exe_path.exists():
        # Local: Warn but continue (signing errors expected)
        print(f"[WARN] Process exited with code {result.returncode} but artifacts exist")
    else:
        # Local: No artifacts means real failure
        raise RuntimeError(f"Build failed with exit code {result.returncode}")
```

**Key Insight**: Wrapper scripts (like `execute_build.sh`) capture subprocess exit codes separately from Python's sys.exit(). Even if Python exits with 0, the wrapper propagates the actual subprocess exit code.

### Issue: Type Errors Not Caught Locally

**Diagnosis**:
```bash
# Check what's in pre-commit config
cat .pre-commit-config.yaml

# Test pre-commit hooks
pre-commit run --all-files

# Manually run type checker
pyright src-tauri/src-python/
mypy scripts/
```

**Solution**: Add type checking to pre-commit hooks:
```yaml
- id: python-pyright
  name: pyright (strict type checking)
  entry: bash -c 'npx --yes pyright@latest'
  language: system
  files: ^(src-tauri/src-python/.*\.py|scripts/.*\.py)$
  pass_filenames: false
```

**Install and test**:
```bash
pre-commit install
pre-commit run --all-files
```

### Issue: Subprocess Exit Code Not Propagated

**Symptoms**:
- Build completes successfully with all artifacts created
- Script prints "[INFO] Build complete"
- CI reports exit code 1 (failure)

**Diagnosis**:
```bash
# Check subprocess.run() calls for missing check=True
cd rostoc/
grep -n "subprocess.run" scripts/build.py

# Check error handling after subprocess.run()
grep -B 5 -A 20 "if result.returncode" scripts/build.py

# Verify error handling in _build_tauri method
sed -n '520,630p' scripts/build.py
```

**Root Cause**: `_build_tauri()` method (lines 593-622) has conditional error handling:
1. Always raises in CI mode when `CI` env var is set ✅
2. In local mode with artifacts present, prints warning **without raising** ❌
3. Subprocess exit code gets swallowed, but `sys.exit(0)` still runs

**Solution Options**:

**Option A** (Simplest - Always raise on error):
```python
result = subprocess.run(cmd, env=env, cwd=ROOT, encoding='utf-8', errors='replace')
if result.returncode != 0:
    raise RuntimeError(f"Tauri build failed with exit code {result.returncode}")
```

**Option B** (Keep local build behavior, but explicit):
```python
if result.returncode != 0:
    bundler = RuntimeBundler(target=self.target)
    exe_path = bundler._find_rostoc_exe()
    
    if os.environ.get("CI") or not (exe_path and exe_path.exists()):
        # Always fail in CI, or if no artifacts created
        raise RuntimeError(f"Tauri build failed with exit code {result.returncode}")
    else:
        # Local build with artifacts: likely signing issue (non-fatal)
        print(f"[WARN] Tauri exited with code {result.returncode} but bundles exist")
        print("[WARN] This is expected for local builds without signing keys")
```

**Verification After Fix**:
```bash
# Test locally
cd rostoc/
python scripts/build.py --debug
echo $?  # Should be 0 on success

# Test error propagation (introduce intentional failure)
python scripts/build.py --target invalid-target
echo $?  # Should be 1 (non-zero)

# Test in CI-like environment
CI=true python scripts/build.py
```

### Issue: Workflow YAML Syntax Error

**Diagnosis**:
```bash
cd rostoc-updates/
make lint  # Runs actionlint + shellcheck
```

**Solution**:
- Fix YAML indentation (2 spaces)
- Quote shell variables: `"$VAR"` not `$VAR`
- Quote redirects: `>> "$GITHUB_OUTPUT"`
- Use `./*.tar.gz` not `*.tar.gz`

### Issue: Script Path Not Found

**Diagnosis**:
```bash
cd rostoc-updates/
make validate-paths
```

**Solution**:
- Check if workflow uses `working-directory`
- Use `../scripts/ci/` for cross-repo scripts
- Use `scripts/ci/` for repo-relative scripts

## Verification Steps

### After Pushing Fix

1. **Monitor CI**:
```bash
# Watch latest run
gh run watch --repo Alain1405/rostoc-updates

# List recent runs
gh run list --repo Alain1405/rostoc-updates --limit 5

# View specific run
gh run view <RUN_ID> --repo Alain1405/rostoc-updates
```

2. **Check Grafana logs** (if available):
- Go to: https://rostocci.grafana.net/explore
- Query: `{run_id="YOUR_RUN_ID"}`
- Look for errors or warnings

3. **Download artifacts** (if build partially completed):
```bash
gh run download <RUN_ID> --repo Alain1405/rostoc-updates -D /tmp/artifacts
```

## Repository Architecture Context

**Important**: Two-repo structure affects CI debugging

- **rostoc-updates** (public): Contains workflows, triggers CI
- **rostoc** (private): Contains source code
- **CI behavior**: Workflows triggered from rostoc-updates check out latest rostoc code
- **Head SHA**: Refers to rostoc-updates commit, NOT the rostoc code being built

**Verifying which code was tested**:
```bash
# Get workflow run details
gh run view <RUN_ID> --repo Alain1405/rostoc-updates --json headSha,createdAt

# Get latest rostoc commits
gh api repos/Alain1405/rostoc/commits?per_page=5 --jq '.[] | {sha: .sha, message: .commit.message, date: .commit.author.date}'

# Workflow checks out rostoc at time of trigger
# Compare createdAt timestamp with rostoc commit dates
```

## Anti-Patterns

❌ **Don't push without local validation**:
```bash
git push  # ❌ No pre-checks
```
✅ **Do run validation suite first**:
```bash
make format && make lint && make test && git push  # ✅
```

❌ **Don't guess at fixes**:
- Read the actual error logs
- Use grep/search to find error context
- Check recent commits for related changes

✅ **Do investigate systematically**:
- Get full error logs
- Check recent code changes
- Verify fix locally before pushing

❌ **Don't test in CI repeatedly**:
- Each CI run takes 30-50 minutes
- Costs GitHub Actions minutes
- Slows down iteration

✅ **Do test locally first**:
- Direct script testing: 30 seconds
- Local builds: 20 minutes
- Only push when local tests pass

## Quick Commands Reference

```bash
# Rostoc validation (before pushing code changes)
cd rostoc/
make format && make lint && make check && make test

# Updates validation (before pushing workflow changes)
cd rostoc-updates/
make format && make lint && make validate-paths && make test-env

# View CI status
gh run list --repo Alain1405/rostoc-updates --limit 5
gh run view <RUN_ID> --log-failed

# Download artifacts
gh run download <RUN_ID> -D /tmp/artifacts

# Test script locally
cd rostoc-updates/
./scripts/ci/test_locally.sh <script.sh>

# Debug with tmate (add [debug] to commit message)
git commit -m "fix: Debug issue [debug]"
git push
# Wait for failure, then SSH to runner

# Check Grafana logs
# https://rostocci.grafana.net/explore
# Query: {run_id="YOUR_RUN_ID"}
```

## Makefile Targets Summary

**Rostoc** (`rostoc/Makefile`):
- `make test` - Run all test suites (smoke, Python, TypeScript)
- `make check` - Run smoke tests + typecheck + cargo check
- `make lint` - Run all linters (Python, TS, Rust)
- `make format` - Run all formatters
- `make lint-python` - ruff + mypy + pyright
- `make gen_types` - Regenerate PyTauri TypeScript client

**Rostoc-Updates** (`rostoc-updates/Makefile`):
- `make format` - Format YAML with Prettier
- `make lint` - actionlint + shellcheck
- `make validate-paths` - Check script paths in workflows
- `make test-env` - Validate env var handling in scripts

## Resources

- Full testing guide: `rostoc-updates/docs/LOCAL_CI_TESTING.md`
- Quick reference: `rostoc-updates/docs/LOCAL_CI_TESTING_CHEATSHEET.md`
- Env var guide: `rostoc-updates/docs/ENV_VAR_TESTING_SUMMARY.md`
- Grafana Loki: https://rostocci.grafana.net/explore
- GitHub Actions: https://github.com/Alain1405/rostoc-updates/actions
