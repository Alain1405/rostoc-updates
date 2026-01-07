# Rostoc Updates Repository Instructions

## Repository Purpose

This is the **public workflow runner** for Rostoc desktop builds. The private `alain1405/rostoc` repository dispatches CI and tagged release events to this repo so we can execute macOS/Windows builds on public GitHub runners and host updater artifacts via GitHub Pages.

## Workspace Structure

- **Multi-root workspace**: Open `rostoc/rostoc-multi-root.code-workspace` to load both `rostoc` (private source) and `rostoc-updates` (this public repo) in one VS Code window
- **Primary product code**: Lives in `../rostoc/`
- **CI/build workflows**: Live in this repo (`.github/workflows/`)
- **Shared scripts**: Located in `../rostoc/scripts/` - workflows check out the private repo to access these

## Workflow Architecture

### Dispatcher Pattern
1. **`ci-dispatch.yml`**: Triggered by push/PR events in private repo → calls `build-and-publish.yml` with `is_release: false`
2. **`release-dispatch.yml`**: Triggered by tag creation in private repo → calls `build-and-publish.yml` with `is_release: true`
3. **`build-and-publish.yml`**: Reusable workflow that builds both platforms, runs tests, and publishes artifacts

### Notarization & Stapling Pipeline
- **Build workflow** (`build-and-publish.yml`): Submits DMG to Apple notarization (async), saves `submission_id` in `releases.json`
- **Stapler workflow** (`staple-notarized-dmg.yml`): Scheduled cron job that:
  - Reads pending notarizations from `releases.json` (served via GitHub Pages)
  - Queries Apple's notarytool for status
  - Downloads DMG from artifacts, staples ticket, uploads to Pages
  - Updates `releases.json` with stapled DMG URL
  - Auto-disables schedule when queue is empty

### Workflow Lifecycle
- **Release workflow**: Enables stapler schedule after successful release
- **Stapler workflow**: Self-disables when no pending notarizations remain
- **Legacy releases**: Pending releases without `submission_id` are marked as invalid on first stapler run

### Interactive Debugging with tmate

**Purpose**: SSH into a failed CI runner to debug interactively, test fixes, and inspect filesystem state.

**When to use**:
- Complex build failures that need live investigation
- Testing fixes without re-running entire 30-50 minute CI pipeline
- Inspecting environment state, filesystem, or installed tools
- Debugging platform-specific issues on actual runner hardware

**How to trigger**:

1. **Add `[debug]` to commit message**:
   ```bash
   git commit -m "fix: Debug build failure [debug]"
   git push origin your-branch
   ```

2. **Wait for build to fail**:
   - The workflow must fail for tmate to activate
   - Go to: https://github.com/Alain1405/rostoc-updates/actions
   - Find your workflow run

3. **Get SSH connection string**:
   - Open the failed job (e.g., "macOS ARM64 (M1)")
   - Expand the "Setup tmate session (debug mode)" step
   - Copy the SSH command shown in logs:
     ```
     ssh <random-id>@nyc1.tmate.io
     ```

4. **Connect and debug**:
   ```bash
   # Connect via SSH (from your terminal)
   ssh <random-id>@nyc1.tmate.io
   
   # Now you're on the GitHub Actions runner!
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

**Security**:
- `limit-access-to-actor: true` ensures only YOU can connect (GitHub actor who triggered the workflow)
- 30-minute timeout automatically disconnects after inactivity
- `detached: true` keeps session alive even if you disconnect temporarily

**Tips**:
- The runner has all dependencies already installed (Node, Rust, Python, etc.)
- Your SSH session starts in the workspace root
- Private repo is checked out in `private-src/`
- You can modify files, re-run commands, and test fixes live
- GitHub Actions environment variables are available (`echo $GITHUB_*`)
- When you're done debugging, just type `exit` or wait for 30-min timeout

**Debugging with Copilot assistance**:
When connected to tmate session, you can:
1. Copy error messages and ask Copilot for solutions
2. Get Copilot to generate commands to run in the SSH session
3. Paste Copilot-suggested fixes directly into files
4. Verify fixes work before committing

**Example workflow**:
```bash
# 1. Trigger debug session
git commit -m "test: Debug codesign failure [debug]"
git push

# 2. Wait for failure, then connect
ssh abc123@nyc1.tmate.io

# 3. In the session
cd private-src
cat codesign-*.log  # Inspect logs
security find-identity -v  # Check certificates

# 4. Ask Copilot: "I'm in a tmate session and codesign failed with errSecInternalComponent"
# Copilot suggests: security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db

# 5. Test the fix
security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db
pnpm tauri build  # Re-run build

# 6. If it works, exit and apply fix to CI scripts
exit
```

**Limitations**:
- Only triggers on failure (not on success)
- Only on builds where commit message contains `[debug]`
- Costs GitHub Actions minutes while session is active (30 min max)
- Runner will be destroyed after session ends

**Removing `[debug]` mode**:
Once you've identified and fixed the issue, push without `[debug]`:
```bash
git commit -m "fix: Apply codesign unlock fix"
git push  # No [debug] tag - runs normally without tmate
```

## Code Quality & Linting

### Before Committing Any Changes

**Always run the complete test suite** after editing workflows, scripts, or CI files:

```bash
# Complete validation suite (recommended)
make format && make lint && make validate-paths && make test-env

# Or run individually if debugging
make format          # Format YAML with Prettier
make lint            # Validate workflows with actionlint + shellcheck
make validate-paths  # Catch script path bugs (working-directory issues)
make test-env        # Catch env var bugs (empty value handling)
```

**What each test prevents:**
- `format` & `lint` - Syntax errors, shellcheck issues
- `validate-paths` - Script paths broken by `working-directory` (Dec 31, 2025 bug)
- `test-env` - Incorrect `${VAR:?}` usage for empty-allowed vars (Jan 1, 2026 bug)

### Linting Rules

1. **Shell scripts in workflow `run:` blocks**:
   - Quote all variable expansions: `"$VAR"` not `$VAR`
   - Quote GitHub env file redirects: `>> "$GITHUB_OUTPUT"` not `>> $GITHUB_OUTPUT`
   - Group repeated redirects: `{ echo "line1"; echo "line2"; } >> file` instead of multiple `>>`
   - Prefix globs with `./` to avoid dash confusion: `./*.tar.gz` not `*.tar.gz`
   - Use `# shellcheck disable=SCxxxx` comments when intentional (e.g., literal backticks in Markdown)

2. **YAML formatting**:
   - 2-space indentation
   - Consistent string quoting (Prettier handles this)

3. **Validation tools**:
   - `actionlint`: Workflow syntax + shellcheck integration
   - `prettier@3`: YAML formatting

### Installation

```bash
brew install actionlint  # Includes shellcheck dependency
```

## Required Secrets

| Secret | Scope | Purpose |
|--------|-------|---------|
| `PRIVATE_REPO_SSH_KEY` | rostoc-updates | Deploy key (read-only) for `alain1405/rostoc` |
| `UPDATES_REPO_TOKEN` | Both repos | PAT with `repo` scope for artifact uploads and workflow dispatch |
| `APPLE_CERTIFICATE` | rostoc-updates | Base64-encoded signing certificate |
| `APPLE_CERTIFICATE_PASSWORD` | rostoc-updates | Certificate password |
| `APPLE_SIGNING_IDENTITY` | rostoc-updates | Signing identity name |
| `APPLE_TEAM_ID` | rostoc-updates | Apple Developer Team ID |
| `APPLE_ID` | rostoc-updates | Apple ID for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | rostoc-updates | App-specific password for notarytool |
| `TAURI_SIGNING_PRIVATE_KEY` | rostoc-updates | Tauri updater signing key |
| `SLACK_WEBHOOK_URL` | rostoc-updates | Slack webhook for build failure notifications |
| `LOKI_URL` | rostoc-updates | Grafana Cloud Loki push endpoint |
| `LOKI_USERNAME` | rostoc-updates | Grafana Cloud user ID for Loki |
| `LOKI_PASSWORD` | rostoc-updates | Grafana Cloud API token for Loki |

## Key Files

- `updates/releases.json`: Manifest of all releases with platform-specific download URLs, notarization status
- `updates/latest.json`: Current stable release metadata (auto-generated from `releases.json`)
- `scripts/ci/generate_releases_json.sh`: Builds release manifest entries during publish
- `scripts/macos/staple_and_upload_dmg.sh`: Stapler script executed by scheduled workflow

## Workflow Permissions

All dispatcher workflows (`ci-dispatch.yml`, `release-dispatch.yml`) must declare:

```yaml
permissions:
  contents: write   # Push to this repo
  pages: write      # Deploy Pages
  id-token: write   # OIDC for Pages
  actions: write    # Enable/disable stapler workflow
```

The `build-and-publish.yml` reusable workflow inherits these and uses `actions: write` to re-enable the stapler schedule after releasing.

## CI Logging and Monitoring

### Grafana Loki Log Aggregation

All CI builds automatically ship logs to Grafana Cloud for centralized search and analysis.

**Grafana Cloud Access:**
- Stack URL: https://rostocci.grafana.net/
- **Explore View (Recommended)**: https://rostocci.grafana.net/explore
  - Best for line-by-line log viewing
  - Update query: `{run_id="YOUR_RUN_ID"}`
- Logs App: https://rostocci.grafana.net/a/grafana-lokiexplore-app/explore
  - Overview and dashboards (logs show as single line)
- Loki datasource: `grafanacloud-logs` (pre-configured)
- Log retention: 14 days

**Required Secrets:**
- `LOKI_URL`: `https://logs-prod-032.grafana.net/loki/api/v1/push`
- `LOKI_USERNAME`: `1445820`
- `LOKI_PASSWORD`: API token created via Access Policies → Create Access Policy → select Loki write scope

**Log Labels (use for filtering):**
```logql
# Search by platform
{platform="macos"}

# Search by failure status
{status="failure"}

# Combine multiple labels
{platform="windows", variant="staging", status="failure"}

# Search by commit or run
{commit="abc123"}
{run_id="12345"}

# Full-text search within logs
{platform="macos"} |= "error" |= "codesign"
```

**Common Queries:**
```logql
# All failed builds
{job="build", status="failure"}

# macOS failures only
{platform="macos", status="failure"}

# Staging variant issues
{variant="staging"}

# Logs from specific run
{run_id="20758186226"}

# Pattern match errors
{job="build"} |~ "(error|failed|panic)"
```

**Workflow Integration:**
- Logs ship via direct Loki Push API (https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki)
- Runs with `if: always()` - ships on success AND failure
- Uses `continue-on-error: true` to not break builds if Loki is down
- Source file: `build-<platform>-<arch>.log` from execute_build.sh
- 11 labels attached as JSON: platform, arch, variant, version, job, status, run_id, run_number, actor, branch, commit
- Authentication via HTTP Basic Auth (username:password)

### Slack Notifications

Build failures automatically post to Slack with error context and quick access links.

**Required Secret:**
- `SLACK_WEBHOOK_URL`: Slack incoming webhook URL

**Notification includes:**
- Platform/architecture/variant details
- Error log excerpt (first 500 chars)
- Direct link to GitHub run
- Artifact download links (build logs, partial artifacts)
- tmate debug instructions if `[debug]` was in commit message

## Retrieving Build Context (GitHub SHA and Rostoc Version)

### From GitHub UI

**Workflow Run → Commit:**
1. Go to workflow run: `https://github.com/Alain1405/rostoc-updates/actions/runs/<RUN_ID>`
2. Look for "triggered by commit" link in the header
3. Or check the "Summary" section for commit SHA and message

**Commit SHA:** Displayed as first 7 characters (e.g., `7f0b205`) with full SHA in URL

### Using GitHub CLI

```bash
# Get workflow run details including commit SHA
gh run view <RUN_ID> --repo Alain1405/rostoc-updates --json headSha,headBranch,workflowName,conclusion,createdAt

# Example output shows:
# "headSha": "7f0b2054a6346563be8bce2462fac0df5e331a67"
# "headBranch": "main"

# Get commit details from SHA
gh api repos/Alain1405/rostoc-updates/commits/7f0b2054a6346563be8bce2462fac0df5e331a67 --jq '.commit.message'

# Get the rostoc version that was built (from the private repo commit)
gh api repos/Alain1405/rostoc/commits/<SHA>/contents/package.json --jq '.content' | base64 -d | jq -r '.version'
```

### Using GitHub MCP Tools

```python
# Get workflow run with commit SHA
mcp_github_github_actions_get(
    method='get_workflow_run',
    owner='Alain1405',
    repo='rostoc-updates',
    resource_id='20758186226'
)
# Returns: head_sha, head_branch, workflow_name, conclusion

# Get commit message and author
mcp_github_github_get_commit(
    owner='Alain1405',
    repo='rostoc-updates',
    ref='7f0b2054a6346563be8bce2462fac0df5e331a67'
)

# Get rostoc version from package.json in private repo
mcp_github_github_get_file_contents(
    owner='Alain1405',
    repo='rostoc',
    path='package.json',
    ref='main'  # or specific commit SHA
)
# Parse JSON to extract: .version
```

### Rostoc Version Sources

**Primary source:** `package.json` in private `rostoc` repo
```bash
# Local
cat /path/to/rostoc/package.json | jq -r '.version'

# From GitHub
gh api repos/Alain1405/rostoc/contents/package.json --jq '.content' | base64 -d | jq -r '.version'
```

**Also available in:**
- `src-tauri/tauri.conf.json` → `.version`
- `src-tauri/Cargo.toml` → `[package] version`
- Build artifacts (stamped during CI): DMG/MSI filename includes version

### Correlating CI Run → Rostoc Version

**For Release Builds:**
1. Git tag = rostoc version: `git tag --points-at <COMMIT_SHA>`
2. Tag format: `v0.2.183` → rostoc version `0.2.183`

**For Dev/CI Builds:**
1. Get commit SHA from workflow run (see above)
2. Check out private repo at that SHA: `cd rostoc && git checkout <SHA>`
3. Read version: `jq -r '.version' package.json`

**From Build Logs:**
```bash
# Search for version stamp in logs
gh run view <RUN_ID> --log | grep -i "version"
gh run view <RUN_ID> --log | grep -i "Building Rostoc"

# Look for lines like:
# "Building Rostoc v0.2.183"
# "Version: 0.2.183-dev.123"
```

### Quick Reference Commands

```bash
# Get everything about a workflow run
gh run view 20758186226 --repo Alain1405/rostoc-updates

# Get commit that triggered it
gh run view 20758186226 --json headSha --jq '.headSha'

# Get rostoc version from that commit
SHA=$(gh run view 20758186226 --json headSha --jq '.headSha')
gh api repos/Alain1405/rostoc/contents/package.json?ref=$SHA --jq '.content' | base64 -d | jq -r '.version'

# Get commit message
gh api repos/Alain1405/rostoc-updates/commits/$SHA --jq '.commit.message'
```

## Common Pitfalls

1. **Missing `actions: write`**: If you add a step that calls the GitHub Actions API (enable/disable workflows), ensure the calling workflow grants `actions: write`
2. **Stale Pages cache**: The disable step in `staple-notarized-dmg.yml` clones the git repo instead of querying Pages URL to avoid caching lag
3. **Unquoted variables in shell**: Will fail shellcheck; always quote expansions and redirects
4. **Heredocs in YAML**: Avoid `<<EOF` syntax; use grouped echo statements with braces instead
5. **Script path bugs**: Using `working-directory` changes script path resolution - always run `make validate-paths` before committing
6. **Empty env vars**: Use `${VAR?}` not `${VAR:?}` for vars that can be empty (e.g., `TAURI_CONFIG_FLAG` in production) - caught by `make test-env`

## Testing & Documentation

- **Testing guide**: [docs/LOCAL_CI_TESTING.md](../docs/LOCAL_CI_TESTING.md)
- **Quick reference**: [docs/LOCAL_CI_TESTING_CHEATSHEET.md](../docs/LOCAL_CI_TESTING_CHEATSHEET.md)
- **Env var testing**: [docs/ENV_VAR_TESTING_SUMMARY.md](../docs/ENV_VAR_TESTING_SUMMARY.md)

## Branch Protection

- Main branch requires passing `rostoc-updates/ci` status check
- Optional: Protect tags with `rostoc-updates/release` check to ensure signed builds complete before publishing
