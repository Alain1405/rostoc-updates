# Local CI Testing Guide

## Overview

This guide provides strategies for testing GitHub Actions workflows locally on Apple Silicon to get fast feedback before pushing to GitHub. The full build process takes 30-50 minutes on GitHub runners, so local validation is crucial for productivity.

## Platform Support Matrix

| Workflow Component | Can Test Locally on M1/M2 | Notes |
|-------------------|---------------------------|-------|
| Shell scripts (`scripts/ci/*.sh`) | ✅ Yes | Direct execution with bash |
| Python scripts (`scripts/ci/*.py`) | ✅ Yes | Direct execution with Python |
| macOS ARM64 build | ✅ Yes | Native platform match |
| macOS Intel build | ⚠️ Partial | Requires Rosetta 2 + cross-compile setup |
| Windows builds | ❌ No | Requires Windows runner or VM |
| Linux builds | ⚠️ Partial | Can test with Docker Linux containers |
| Workflow YAML syntax | ✅ Yes | Using `actionlint` (already in Makefile) |
| Composite actions | ✅ Yes | Can be tested with `act` |
| Secrets/environment | ⚠️ Partial | Must mock or provide via `.secrets` |

## Strategy 1: Direct Script Testing (Fastest - Recommended)

**Best for**: Quick validation of script logic, error handling, and shell correctness.

### Setup
```bash
cd /Users/alainscialoja/code/new-coro/rostoc-updates

# Ensure scripts are executable
chmod +x scripts/ci/*.sh

# Set up minimal environment
export GITHUB_WORKSPACE="$(pwd)"
export RUNNER_TEMP="/tmp/ci-test"
export RUNNER_OS="macOS"
mkdir -p "$RUNNER_TEMP"
```

### Test Individual Scripts
```bash
# Test script with dry-run or validation mode
bash -x scripts/ci/generate_and_verify_config.sh

# Test with actual environment variables
export ROSTOC_APP_VARIANT="staging"
export TAURI_CONFIG_FLAG="src-tauri/tauri.staging.conf.json"
bash -x scripts/ci/stage_and_verify_runtime.sh

# Validate Python scripts
python scripts/ci/build_backend_payload.py --help
python scripts/ci/get_artifact_name.py macos aarch64 production
```

### Create Test Harness Script

Create `scripts/ci/test_locally.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Test harness for local CI script validation
# Usage: ./scripts/ci/test_locally.sh [script_name]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_WORKSPACE="/tmp/ci-test-workspace"

echo "🧪 Setting up test environment..."
mkdir -p "$TEST_WORKSPACE"
export GITHUB_WORKSPACE="$TEST_WORKSPACE"
export RUNNER_TEMP="$TEST_WORKSPACE/tmp"
export RUNNER_OS="macOS"
mkdir -p "$RUNNER_TEMP"

# Mock GitHub Actions environment
export GITHUB_OUTPUT="$RUNNER_TEMP/github_output.txt"
export GITHUB_ENV="$RUNNER_TEMP/github_env.txt"
export GITHUB_STEP_SUMMARY="$RUNNER_TEMP/step_summary.md"
touch "$GITHUB_OUTPUT" "$GITHUB_ENV" "$GITHUB_STEP_SUMMARY"

# Set test inputs
export ROSTOC_APP_VARIANT="${ROSTOC_APP_VARIANT:-production}"
export INPUT_PLATFORM="${INPUT_PLATFORM:-macos}"
export INPUT_ARCH="${INPUT_ARCH:-aarch64}"
export INPUT_IS_RELEASE="${INPUT_IS_RELEASE:-false}"

SCRIPT_NAME="${1:-}"

if [ -n "$SCRIPT_NAME" ]; then
  echo "▶️  Testing: $SCRIPT_NAME"
  bash -x "$SCRIPT_DIR/$SCRIPT_NAME"
else
  echo "📋 Available scripts:"
  ls -1 "$SCRIPT_DIR"/*.sh | xargs -n1 basename
  echo ""
  echo "Usage: $0 <script_name.sh>"
fi

echo ""
echo "📊 Outputs:"
echo "GITHUB_OUTPUT:"
cat "$GITHUB_OUTPUT"
echo ""
echo "GITHUB_ENV:"
cat "$GITHUB_ENV"
echo ""
echo "STEP_SUMMARY:"
cat "$GITHUB_STEP_SUMMARY"
```

## Strategy 2: Static Analysis & Linting (Already Implemented)

**Best for**: Catching syntax errors, shellcheck issues, and workflow schema problems.

```bash
cd /Users/alainscialoja/code/new-coro/rostoc-updates

# Format YAML workflows
make format

# Lint workflows + shell scripts embedded in YAML
make lint

# Manually run actionlint for detailed output
actionlint -verbose
```

**Key checks performed:**
- YAML syntax validation
- Workflow schema compliance
- Shell script linting (via shellcheck integration)
- Deprecated action usage
- Missing required inputs/outputs

## Strategy 3: Act (Docker-based Workflow Runner) - ⚠️ LIMITED VALUE FOR THIS REPO

**Best for**: Testing platform-agnostic workflows only.

**⚠️ IMPORTANT LIMITATION**: Your CI pipeline requires `macos-15` and `windows-2022` runners for building the desktop app. **Act cannot simulate these runners** because it only supports Linux containers via Docker. This means **you cannot test your main build workflow with Act**.

### What Act CAN Test ✅

- Setup/validation workflows (e.g., `setup.yml`)
- Dispatcher workflows (trigger logic)
- GitHub Pages deployment
- Status reporting jobs
- Platform-agnostic scripts

### What Act CANNOT Test ❌

- **Build workflow** (`build.yml`) - Requires native macOS/Windows runners
- **Composite actions** with platform-specific steps (code signing, DMG/MSI creation)
- **Notarization workflows** - macOS-specific
- **Architecture-specific builds** - Needs actual hardware

### Installation (Optional)
```bash
brew install act

# Install Docker Desktop for Mac (required)
# https://www.docker.com/products/docker-desktop/
```

### Basic Usage - Platform-Agnostic Workflows Only

```bash
cd /Users/alainscialoja/code/new-coro/rostoc-updates

# ✅ Test setup workflow (no platform-specific code)
act workflow_call -W .github/workflows/setup.yml \
  --input ref=main \
  --input is_release=false \
  --secret-file .secrets

# ✅ Test dispatcher (just checks trigger logic)
act workflow_dispatch -W .github/workflows/ci-dispatch.yml -n

# ❌ Build workflow will fail (needs macOS/Windows)
# act -W .github/workflows/build.yml  # Don't bother - will fail immediately
```

### Why Act Is Not Recommended for This Repo

Your workflow matrix from `build.yml`:
```yaml
runs-on: ${{ matrix.os }}
# Uses: macos-15, macos-15-intel, windows-2022, ubuntu-latest
```

**Act limitation**: Can only simulate `ubuntu-latest`. The macOS and Windows jobs that comprise your primary build targets cannot be tested.

**Better alternatives**:
1. **Direct script testing** (30 sec) - Test CI scripts without Docker
2. **Native macOS builds** (20 min) - Test actual ARM64 builds on your M1/M2
3. **Static linting** (5 sec) - Catch YAML/shell errors immediately

### Recommendation

**Skip Act for this repository.** The overhead of installing and configuring Act provides minimal value since 80% of your CI (the actual builds) cannot be tested with it. Focus on:

```bash
# Fastest iteration cycle for this repo:
make format && make lint              # 5 seconds
./scripts/ci/test_locally.sh <script> # 30 seconds
python scripts/build.py --locked       # 20 min (native build)
```

### Recommended Act Configuration

Create `.actrc` in repo root:

```bash
# Use medium-sized runner image
-P ubuntu-latest=catthehacker/ubuntu:act-latest

# Bind mount your code (faster than checkout)
--bind

# Reuse containers between runs
--reuse

# Enable verbose output for debugging
--verbose

# Set artifact server port (if testing artifact upload/download)
--artifact-server-path /tmp/act-artifacts
```

### Testing Specific Components with Act

```bash
# Test setup/validation workflow (platform-agnostic)
act workflow_call \
  -W .github/workflows/setup.yml \
  --input ref=main \
  --input is_release=false \
  --secret-file .secrets

# Test dispatcher logic (without building)
act workflow_dispatch \
  -W .github/workflows/ci-dispatch.yml \
  --secret-file .secrets

# Test scripts inside composite actions
act -j build-desktop \
  -W .github/workflows/build.yml \
  --input ref=main \
  --input is_release=false \
  --dryrun
```

## Strategy 4: Partial Native Builds

**Best for**: Testing the actual build process for macOS ARM64.

### Prerequisites
```bash
cd /Users/alainscialoja/code/new-coro/rostoc

# Activate Python environment
. .venv/bin/activate

# Install dependencies (if not already done)
pnpm install
pip install -e shared-python
```

### Simulate CI Build Steps

```bash
# Set environment variables to match CI
export ROSTOC_APP_VARIANT="staging"
export ROSTOC_UPDATE_CHANNEL="staging"
export TAURI_CONFIG_FLAG="src-tauri/tauri.staging.conf.json"
export SENTRY_ENVIRONMENT="ci"

# Test Python config generation (CI script)
cd /Users/alainscialoja/code/new-coro/rostoc-updates
python scripts/ci/generate_and_verify_config.sh

# Back to main repo for build
cd /Users/alainscialoja/code/new-coro/rostoc

# Run build script (mimics CI)
python scripts/build.py --locked --mode development --features devtools

# Or use pnpm scripts
pnpm tauri build --target aarch64-apple-darwin

# Test artifact extraction
cd src-tauri/target/aarch64-apple-darwin/release/bundle/macos
ls -lh *.app
```

### Quick Build Validation (Skip Full Build)

```bash
# Just validate Rust compilation
cargo check --target aarch64-apple-darwin

# Just validate TypeScript
pnpm tsc --noEmit

# Run Python tests (backend validation)
make test

# Run frontend tests
pnpm test
```

## Strategy 5: GitHub Actions Local Runner (Advanced)

**Best for**: Testing workflows that require exact GitHub runner environment.

### Setup Self-Hosted Runner

```bash
# Install GitHub Actions runner
mkdir ~/actions-runner && cd ~/actions-runner

# Download latest runner for macOS ARM64
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-osx-arm64-2.311.0.tar.gz

# Extract and configure
tar xzf ./actions-runner-osx-arm64.tar.gz
./config.sh --url https://github.com/Alain1405/rostoc-updates \
  --token YOUR_RUNNER_TOKEN \
  --name local-m1 \
  --labels self-hosted,macOS,ARM64,local

# Run in foreground (for testing)
./run.sh

# Or install as service
./svc.sh install
./svc.sh start
```

Then update workflow to use:
```yaml
runs-on: [self-hosted, local]
```

**Warning**: Only use for private testing; don't commit workflow changes with self-hosted runner tags.

## Strategy 6: Component Testing in Private Repo

**Best for**: Testing build logic before dispatching to public repo.

```bash
cd /Users/alainscialoja/code/new-coro/rostoc

# Test the dispatcher workflow locally (triggers public CI)
# Use --dryrun to prevent actual dispatch
act workflow_dispatch \
  -W .github/workflows/trigger-public-build.yml \
  --dryrun

# Or test build logic directly in private repo
pnpm tauri dev  # Fast iteration with hot reload
pnpm tauri build  # Full build test
```

## Recommended Workflow for Fast Iteration

### Phase 1: Script Development (Fastest - 5-30 seconds)

```bash
# Edit script
vim scripts/ci/new_script.sh

# Test directly
bash -x scripts/ci/new_script.sh

# Lint
make lint
```

### Phase 2: Local Validation (Fast - 1-2 minutes)

```bash
# Format and lint entire workflow
make format && make lint

# Test script in mock CI environment
./scripts/ci/test_locally.sh new_script.sh

# Validate Python scripts
python scripts/ci/build_backend_payload.py --test-mode
```

### Phase 3: Act Testing (Medium - 5-10 minutes)

```bash
# Test workflow with act (platform-agnostic parts)
act -W .github/workflows/setup.yml \
  --input is_release=false \
  --secret-file .secrets
```

### Phase 4: Partial Native Build (Slow - 20-30 minutes)

```bash
# Build just your platform
cd /Users/alainscialoja/code/new-coro/rostoc
export ROSTOC_APP_VARIANT="staging"
python scripts/build.py --locked --mode development --features devtools
```

### Phase 5: Push to GitHub (Slowest - 30-50 minutes)

```bash
# Only after local validation passes
git push origin feature-branch

# Monitor CI at:
# https://github.com/Alain1405/rostoc-updates/actions
```

## Tools Reference

### Installed Tools
- ✅ `actionlint` (via `brew install actionlint`)
- ✅ `shellcheck` (bundled with actionlint)
- ✅ `prettier` (via pnpm, for YAML formatting)

### Tools to Install
```bash
# Act for workflow testing
brew install act

# Docker Desktop (required for act)
brew install --cask docker

# Alternative: Colima (lightweight Docker alternative)
brew install colima
colima start --arch aarch64 --cpu 4 --memory 8

# jq for JSON processing (if not installed)
brew install jq

# GitHub CLI (for testing API interactions)
brew install gh
gh auth login
```

### Useful GitHub CLI Commands

```bash
# Test GitHub API authentication
gh auth status

# List workflow runs
gh run list --repo Alain1405/rostoc-updates

# View specific run logs
gh run view 12345 --log

# Cancel running workflow
gh run cancel 12345

# Re-run failed jobs
gh run rerun 12345 --failed

# Download artifacts locally
gh run download 12345
```

## Common Testing Scenarios

### Scenario 1: Testing New Shell Script

```bash
# 1. Write script with proper error handling
vim scripts/ci/my_new_script.sh

# 2. Make executable
chmod +x scripts/ci/my_new_script.sh

# 3. Test with mock environment
export GITHUB_WORKSPACE="/tmp/test"
export GITHUB_OUTPUT="/tmp/test/output.txt"
bash -x scripts/ci/my_new_script.sh

# 4. Lint
shellcheck scripts/ci/my_new_script.sh

# 5. Format workflow that uses it
make format

# 6. Full lint check
make lint
```

### Scenario 2: Testing Workflow Modification

```bash
# 1. Edit workflow
vim .github/workflows/build.yml

# 2. Format
make format

# 3. Lint (catches many errors)
make lint

# 4. Test with act (if possible)
act -W .github/workflows/build.yml -n --input ref=main

# 5. Commit and push (or create test branch)
git checkout -b test/workflow-change
git commit -am "test: Modify build workflow"
git push -u origin test/workflow-change

# 6. Monitor on GitHub
gh run watch
```

### Scenario 3: Testing Python Config Generation

```bash
cd /Users/alainscialoja/code/new-coro/rostoc

# Activate environment
. .venv/bin/activate

# Set test variables
export ROSTOC_APP_VARIANT="staging"
export TAURI_CONFIG_FLAG="src-tauri/tauri.staging.conf.json"

# Run generation script
python scripts/generate_python_config.py

# Verify output
cat src-tauri/src-python/rostoc/runtime_config/generated_config.py

# Test import
python -c "from rostoc.runtime_config import generated_config; print(generated_config.BACKEND_MODE)"
```

### Scenario 4: Testing macOS Build End-to-End

```bash
cd /Users/alainscialoja/code/new-coro/rostoc

# Full clean build (matches CI closely)
rm -rf src-tauri/target
export ROSTOC_APP_VARIANT="production"
export ROSTOC_UPDATE_CHANNEL="stable"

# Build (this will take 20-30 minutes)
python scripts/build.py --locked

# Verify artifacts
ls -lh src-tauri/target/release/bundle/dmg/
ls -lh src-tauri/target/release/bundle/macos/

# Test the built app
open src-tauri/target/release/bundle/macos/Rostoc.app
```

## Secrets Management for Local Testing

Create `.secrets` file (gitignored):

```bash
# Minimal secrets for local testing
PRIVATE_REPO_SSH_KEY=not-needed-for-local
UPDATES_REPO_TOKEN=ghp_fake_token_for_testing
APPLE_CERTIFICATE=fake-cert-base64
APPLE_CERTIFICATE_PASSWORD=fake-password
APPLE_SIGNING_IDENTITY=Developer ID Application: Test
APPLE_TEAM_ID=XXXXXXXXXX
APPLE_ID=test@example.com
APPLE_APP_SPECIFIC_PASSWORD=fake-app-password
TAURI_SIGNING_PRIVATE_KEY=fake-signing-key
SENTRY_DSN=https://fake@sentry.io/123456
VITE_SENTRY_DSN=https://fake@sentry.io/654321
```

**Never commit `.secrets` to git!** Add to `.gitignore`:

```bash
echo ".secrets" >> .gitignore
echo ".actrc" >> .gitignore
```

## Debugging Failed Workflows

### Quick Debugging with GitHub CLI

```bash
# Get logs from failed run
gh run view 12345 --log-failed > failed_logs.txt

# Search for specific error
gh run view 12345 --log | grep -A 10 "ERROR"

# Download artifacts for inspection
gh run download 12345 -D /tmp/artifacts
```

### Re-running Specific Steps Locally

```bash
# Extract commands from workflow logs
gh run view 12345 --log > full_logs.txt

# Find failing step
grep -B 5 -A 10 "Error" full_logs.txt

# Extract and run command locally
export $(grep "^export" full_logs.txt)
bash -x /path/to/failing/command.sh
```

## Performance Optimization Tips

1. **Use caching aggressively**:
   - Rust compilation cache: `~/.cargo`
   - pnpm cache: `~/.local/share/pnpm/store`
   - Python packages: `.venv`

2. **Incremental builds**:
   ```bash
   # Don't clean target/ unless necessary
   cargo build --target aarch64-apple-darwin
   
   # Use --locked to skip dependency resolution
   pnpm install --frozen-lockfile
   ```

3. **Parallel testing**:
   ```bash
   # Test multiple scripts simultaneously
   (bash -x scripts/ci/script1.sh) &
   (bash -x scripts/ci/script2.sh) &
   wait
   ```

4. **Skip expensive operations**:
   ```bash
   # Skip notarization for local builds
   export SKIP_NOTARIZATION=true
   
   # Skip code signing verification
   export SKIP_CODESIGN_VERIFY=true
   ```

## Troubleshooting

### Act Issues

**Problem**: `act` fails with "Docker daemon not running"
```bash
# Start Docker Desktop
open /Applications/Docker.app

# Or use Colima
colima start
```

**Problem**: `act` uses wrong platform
```bash
# Force Linux emulation for tests
act -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

**Problem**: Secrets not loading
```bash
# Verify secrets file format (no spaces around =)
cat .secrets

# Pass secrets explicitly
act --secret PRIVATE_REPO_SSH_KEY=fake-key
```

### Script Testing Issues

**Problem**: Script fails with "command not found"
```bash
# Ensure required tools are installed
brew install jq python@3.11 node

# Check PATH
echo $PATH

# Use full paths in scripts
command -v jq || echo "jq not found"
```

**Problem**: Environment variables not set
```bash
# Source a test environment file
cat > test.env <<EOF
export ROSTOC_APP_VARIANT=staging
export GITHUB_WORKSPACE=$(pwd)
export RUNNER_OS=macOS
EOF

source test.env
bash -x scripts/ci/my_script.sh
```

## Summary: Recommended Fast Iteration Workflow

**For this repository (platform-specific builds), skip Act and use:**

```bash
# 1. Edit script/workflow (1 min)
vim scripts/ci/my_script.sh

# 2. Quick format + lint (5-30 sec)
make format && make lint

# 3. Direct script test (30 sec)
make test-script SCRIPT=my_script.sh

# 4. SKIP Act - It cannot test build workflows (requires macOS/Windows)

# 5. Optional: Native build test in rostoc repo (20 min)
cd /Users/alainscialoja/code/new-coro/rostoc
. .venv/bin/activate
python scripts/build.py --locked --mode development

# 6. Push to feature branch (avoid main)
git checkout -b test/my-change
git commit -am "test: CI script change"
git push origin test/my-change

# 7. Monitor on GitHub (30-50 min for full build) - final validation only
gh run watch

# 8. Iterate on failures by going back to step 1
```

This workflow reduces iteration time from 30-50 minutes (full GitHub CI) to **1-5 minutes** for most changes, giving you 6-10x faster feedback cycles.

## Next Steps

1. **Create test harness**: Implement `scripts/ci/test_locally.sh` as described above
2. **Set up act**: Install and configure for workflow testing
3. **Document platform-specific limitations**: Add notes as you discover edge cases
4. **CI feedback loop metrics**: Track how much time local testing saves

## Additional Resources

- [Act documentation](https://github.com/nektos/act)
- [GitHub Actions local testing (StackOverflow)](https://stackoverflow.com/questions/59241249/how-can-i-run-github-actions-workflows-locally)
- [actionlint documentation](https://github.com/rhysd/actionlint)
- [GitHub CLI manual](https://cli.github.com/manual/)
- [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
