# Local CI Testing Quick Reference

Fast commands for testing CI changes locally before pushing to GitHub.

## 🚀 Quick Start (5 seconds)

```bash
cd /Users/alainscialoja/code/new-coro/rostoc-updates

# Format + Lint (catches 80% of issues)
make format && make lint
```

## 📝 Test Individual Scripts (30 seconds)

```bash
# List available scripts
./scripts/ci/test_locally.sh

# Test specific script
./scripts/ci/test_locally.sh generate_and_verify_config.sh

# Test with staging variant
ROSTOC_APP_VARIANT=staging ./scripts/ci/test_locally.sh stage_and_verify_runtime.sh

# Test Python scripts
python scripts/ci/build_backend_payload.py
python scripts/ci/get_artifact_name.py macos aarch64 production
```

## 🔍 Validate Workflow Syntax (5 seconds)

```bash
# Comprehensive linting
make lint

# Detailed actionlint output
actionlint -verbose

# Check specific workflow
actionlint .github/workflows/build.yml
```

## 🐳 Test with Act (5-10 minutes) - ⚠️ LIMITED USE

**Note**: Act cannot test your build workflow (requires macOS/Windows runners). Only useful for platform-agnostic jobs.

```bash
# Install (one-time)
brew install act

# ✅ Test setup workflow (platform-agnostic)
act -W .github/workflows/setup.yml --input is_release=false -n

# ❌ Cannot test build workflow (needs macOS/Windows)
# act -W .github/workflows/build.yml  # Will fail

# ✅ Test Pages deployment
act -j deploy -W .github/workflows/deploy-pages.yml -n
```

**Recommendation**: Skip Act for this repo—use direct script testing + native builds instead.

## 🏗️ Test Native macOS Build (20-30 minutes)

```bash
cd /Users/alainscialoja/code/new-coro/rostoc

# Activate environment
. .venv/bin/activate

# Quick validation (no full build)
cargo check --target aarch64-apple-darwin
pnpm tsc --noEmit
make test

# Full build (matches CI)
export ROSTOC_APP_VARIANT="staging"
python scripts/build.py --locked --mode development --features devtools
```

## 🔧 Common Test Scenarios

### Test Workflow Changes
```bash
vim .github/workflows/build.yml
make format && make lint
git commit -am "test: Workflow change"
```

### Test Shell Script
```bash
vim scripts/ci/new_script.sh
chmod +x scripts/ci/new_script.sh
shellcheck scripts/ci/new_script.sh
./scripts/ci/test_locally.sh new_script.sh
```

### Test Python Script
```bash
vim scripts/ci/new_script.py
python scripts/ci/new_script.py --help
ruff check scripts/ci/new_script.py
```

### Debug Failed GitHub Workflow
```bash
# Get logs
gh run view 12345 --log-failed > logs.txt

# Extract error context
grep -B 5 -A 10 "Error" logs.txt

# Download artifacts
gh run download 12345 -D /tmp/artifacts

# Re-run specific step locally
export $(grep "^export" logs.txt)
bash -x scripts/ci/failing_script.sh
```

## 🎯 Recommended Workflow

```bash
# 1. Make changes (1 min)
vim scripts/ci/my_script.sh

# 2. Quick validation (30 sec)
make format && make lint
./scripts/ci/test_locally.sh my_script.sh

# 3. Push to test branch (avoid main)
git checkout -b test/my-change
git commit -am "test: CI change"
git push origin test/my-change

# 4. Monitor GitHub (only if local tests pass)
gh run watch
```

**Result**: 1-2 minute feedback instead of 30-50 minutes! 🎉

## 🔑 Setup Secrets for Act

```bash
# Create .secrets file (gitignored)
cat > .secrets <<EOF
PRIVATE_REPO_SSH_KEY=fake-key
UPDATES_REPO_TOKEN=ghp_fake_token
APPLE_SIGNING_IDENTITY=Developer ID Application: Test
SENTRY_DSN=https://fake@sentry.io/123
EOF

# Use with act
act -W .github/workflows/setup.yml --secret-file .secrets
```

## 📊 Validate Before Pushing

```bash
# The golden trio (run before EVERY push)
make format          # Prettier YAML formatting
make lint            # actionlint + shellcheck
make validate-paths  # Check script paths (prevents CI path issues)

# All in one command
make format && make lint && make validate-paths
```

**💡 Pro Tip**: The `validate-paths` check catches the common issue of script paths breaking when workflows use `working-directory`. This exact issue caused a full CI failure on 2025-12-31.

## 🐛 Debugging Tools

```bash
# Check workflow syntax
actionlint -verbose

# Validate shell scripts
shellcheck scripts/ci/*.sh

# Test Python imports
python -c "from scripts.ci.build_backend_payload import *"

# Check environment setup
env | grep GITHUB
env | grep ROSTOC

# Verify GitHub CLI auth
gh auth status

# Check Docker (for act)
docker ps
```

## 📚 Full Documentation

See [LOCAL_CI_TESTING.md](./LOCAL_CI_TESTING.md) for comprehensive guide.

## 💡 Pro Tips

1. **Always test locally first** - Don't waste 30 minutes waiting for GitHub CI to fail
2. **Use test branches** - Keep main clean, test risky changes in feature branches
3. **Incremental testing** - Test scripts individually before full workflow
4. **Cache builds** - Don't clean `target/` or `.venv` unless necessary
5. **Parallel testing** - Test multiple scripts simultaneously when possible
6. **Monitor costs** - Self-hosted runners can save money for frequent testing

## 🆘 Troubleshooting

**act fails with "Docker not running"**
```bash
open /Applications/Docker.app  # Start Docker Desktop
```

**Script fails with "command not found"**
```bash
which jq python node  # Verify tools installed
brew install jq  # Install missing tools
```

**Secrets not loading in act**
```bash
cat .secrets  # Check format (no spaces around =)
act --secret MYVAR=value  # Pass inline if needed
```

**Workflow times out locally**
```bash
# Skip expensive operations
export SKIP_NOTARIZATION=true
export SKIP_CODESIGN_VERIFY=true
```
