---
name: rostoc-updates-tmate
description: Interactive CI debugging for Rostoc builds using tmate SSH sessions. Use when CI builds fail and need live debugging on the GitHub Actions runner, testing fixes without re-running the full 30-50 minute pipeline, or debugging platform-specific issues like codesigning.
---

# Interactive Debugging with tmate

SSH into a failed CI runner to debug interactively, test fixes, and inspect filesystem state.

## When to Use

- Complex build failures that need live investigation
- Testing fixes without re-running entire 30-50 minute CI pipeline
- Inspecting environment state, filesystem, or installed tools
- Debugging platform-specific issues (codesigning, notarization)

## How to Trigger

### Step 1: Add `[debug]` to commit message

```bash
git commit -m "fix: Debug build failure [debug]"
git push origin your-branch
```

### Step 2: Wait for build to fail

- The workflow must fail for tmate to activate
- Go to: https://github.com/Alain1405/rostoc-updates/actions
- Find your workflow run

### Step 3: Get SSH connection string

- Open the failed job (e.g., "macOS ARM64 (M1)")
- Expand the "Setup tmate session (debug mode)" step
- Copy the SSH command: `ssh <random-id>@nyc1.tmate.io`

### Step 4: Connect and debug

```bash
# Connect via SSH
ssh <random-id>@nyc1.tmate.io

# Navigate to the build directory
cd private-src

# Inspect failed build state
ls -la src-tauri/target/release/bundle/

# Check logs
cat build-*.log

# Re-run build commands manually
pnpm tauri build

# Test fixes
vim src-tauri/Cargo.toml
cargo build --release

# Exit when done
exit
```

## Security

- `limit-access-to-actor: true` ensures only YOU can connect
- 30-minute timeout automatically disconnects after inactivity
- `detached: true` keeps session alive if you disconnect temporarily

## Tips

- Runner has all dependencies installed (Node, Rust, Python, etc.)
- SSH session starts in workspace root
- Private repo is checked out in `private-src/`
- GitHub Actions env vars available: `echo $GITHUB_*`

## Example: Debugging Codesign Failure

```bash
# 1. Trigger debug session
git commit -m "test: Debug codesign failure [debug]"
git push

# 2. Wait for failure, then connect
ssh abc123@nyc1.tmate.io

# 3. In the session
cd private-src
cat codesign-*.log
security find-identity -v

# 4. Test the fix
security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db
pnpm tauri build

# 5. If it works, exit and apply fix to CI scripts
exit
```

## Limitations

- Only triggers on failure (not on success)
- Only on builds where commit message contains `[debug]`
- Costs GitHub Actions minutes (30 min max)
- Runner destroyed after session ends

## Removing Debug Mode

After fixing the issue, push without `[debug]`:

```bash
git commit -m "fix: Apply codesign unlock fix"
git push  # No [debug] tag - runs normally
```
