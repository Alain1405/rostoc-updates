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
