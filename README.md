# rostoc-updates

[![Dispatch CI Build](https://github.com/Alain1405/rostoc-updates/actions/workflows/ci-dispatch.yml/badge.svg)](https://github.com/Alain1405/rostoc-updates/actions/workflows/ci-dispatch.yml)

[![Dispatch Release Build](https://github.com/Alain1405/rostoc-updates/actions/workflows/release-dispatch.yml/badge.svg)](https://github.com/Alain1405/rostoc-updates/actions/workflows/release-dispatch.yml)

Public workflow runner for Rostoc desktop builds. The private `alain1405/rostoc` repository dispatches CI and tagged release events to this repo so we can execute macOS/Windows builds on public runners and host updater artifacts.

## 📦 Architecture

**Binary Storage**: DigitalOcean Spaces (S3-compatible object storage with CDN)  
**Metadata Hosting**: GitHub Pages (`latest.json`, `releases.json`)  
**Update Endpoint**: `https://alain1405.github.io/rostoc-updates/latest.json`

### Why DigitalOcean Spaces?

- **Mutable storage**: Can replace DMG after Apple notarization (GitHub Releases assets are immutable)
- **S3-compatible API**: Use AWS CLI for uploads/downloads in workflows
- **Built-in CDN**: Fast global distribution of binaries
- **Cheap**: $5/mo for 250GB storage + 1TB transfer
- **Simple integration**: Works with existing CI/CD patterns

### File Structure

```
DigitalOcean Spaces (s3://rostoc-releases/releases/):
  └── v0.2.x/
      ├── Rostoc-0.2.x-darwin-aarch64.app.tar.gz
      ├── Rostoc-0.2.x-darwin-aarch64.app.tar.gz.sig
      ├── Rostoc-0.2.x-darwin-aarch64.dmg          # Replaced after notarization
      ├── Rostoc-0.2.x-windows-x86_64.msi
      └── Rostoc-0.2.x-windows-x86_64.msi.sig

GitHub Pages (alain1405.github.io/rostoc-updates/):
  ├── latest.json          # Tauri updater manifest (points to Spaces CDN URLs)
  ├── releases.json        # Version history (includes notarization status)
  └── storybook/          # Documentation
```

### Notarization Pipeline

1. **Build workflow** submits DMG to Apple notarization (async), uploads unsigned DMG to Spaces
2. **Stapler workflow** (cron: every 30min):
   - Checks `releases.json` for pending notarizations
   - Queries Apple notarytool for status
   - If accepted: Downloads DMG from Spaces, staples certificate, re-uploads to same path
   - Updates `releases.json` with `available: true`
   - Auto-disables cron when queue is empty
3. **Release workflow** re-enables stapler cron after successful release

## 🔐 Required secrets

| Secret                        | Scope                       | Purpose                                                                                                |
| ----------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------ |
| `PRIVATE_REPO_SSH_KEY`        | Repository (rostoc-updates) | Deploy key with read access to the private `alain1405/rostoc` repo so workflows can clone sources.     |
| `UPDATES_REPO_TOKEN`          | Both repos                  | Personal access token with `repo` scope for dispatching workflows and updating manifests.              |
| `DO_SPACES_ACCESS_KEY`        | Repository (rostoc-updates) | DigitalOcean Spaces API access key for uploading/downloading binaries.                                 |
| `DO_SPACES_SECRET_KEY`        | Repository (rostoc-updates) | DigitalOcean Spaces API secret key.                                                                    |
| `DO_SPACES_BUCKET`            | Repository (rostoc-updates) | Space name (e.g., `rostoc-releases`).                                                                  |
| `DO_SPACES_ENDPOINT`          | Repository (rostoc-updates) | Spaces endpoint hostname (e.g., `sgp1.digitaloceanspaces.com`).                                        |
| `DO_SPACES_CDN_URL`           | Repository (rostoc-updates) | CDN base URL without trailing slash (e.g., `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com`). |
| `APPLE_CERTIFICATE`           | Repository (rostoc-updates) | Base64-encoded macOS signing certificate.                                                              |
| `APPLE_CERTIFICATE_PASSWORD`  | Repository (rostoc-updates) | Certificate password.                                                                                  |
| `APPLE_SIGNING_IDENTITY`      | Repository (rostoc-updates) | Code signing identity name.                                                                            |
| `APPLE_TEAM_ID`               | Repository (rostoc-updates) | Apple Developer Team ID.                                                                               |
| `APPLE_ID`                    | Repository (rostoc-updates) | Apple ID for notarization.                                                                             |
| `APPLE_APP_SPECIFIC_PASSWORD` | Repository (rostoc-updates) | App-specific password for notarytool.                                                                  |
| `TAURI_SIGNING_PRIVATE_KEY`   | Repository (rostoc-updates) | Tauri updater signing key.                                                                             |
| `ROSTOC_BACKEND_TOKEN`        | Repository (rostoc-updates) | Service token for POSTing release metadata to `/api/updates/publish/` on the Rostoc backend.           |

See [DIGITALOCEAN_SPACES_SETUP.md](./DIGITALOCEAN_SPACES_SETUP.md) for detailed setup instructions.

## ⚙️ Workflow flow

1. **Push / PR in private repo** – `ci-build.yml` fires a `trigger-ci` dispatch and exits immediately. The public `Dispatch CI Build` workflow reports its result back to the private repo via the status context `rostoc-updates/ci`.
2. **Tag in private repo** – `trigger-public-build.yml` fires `trigger-release` and exits. The public release workflow:
   - Builds signed macOS and Windows binaries
   - Uploads binaries to DigitalOcean Spaces (via AWS CLI with S3-compatible endpoint)
   - Submits macOS DMG to Apple notarization (async)
   - Generates `latest.json` and `releases.json` with Spaces CDN URLs
   - Publishes release metadata to the Rostoc backend via `/api/updates/publish/` (runs when `ROSTOC_BACKEND_TOKEN` is configured)
   - Deploys manifests to GitHub Pages
   - Enables stapler workflow cron
   - Reports success via status context `rostoc-updates/release`
3. **Stapler workflow** (cron: every 30min) – Checks `releases.json` for pending notarizations:
   - Queries Apple notarytool for submission status
   - If accepted: Downloads DMG from Spaces, staples certificate, re-uploads to same path
   - Updates `releases.json` on GitHub Pages with `available: true`
   - Auto-disables cron when no pending notarizations remain

If either side is missing the shared secrets, the dispatch/workflows will fail fast with actionable logs.

### Backend publish hook

When `ROSTOC_BACKEND_TOKEN` is present the release workflow sends a signed POST request to the Rostoc backend's `/api/updates/publish/` endpoint. The payload bundles:

- Release metadata (`channel`, `version`, `build_sha`, manifest payload)
- Asset inventory (Spaces key, size, checksum, CDN URL, Ed25519 signature when available)
- The generated `releases.json` entry so the backend can persist notarization status

You can override the defaults per-run via the reusable workflow inputs:

| Input (`workflow_dispatch` / callers) | Default                                      | Description                                      |
| ------------------------------------- | -------------------------------------------- | ------------------------------------------------ |
| `release_channel`                     | `stable`                                     | Channel name recorded in backend releases        |
| `backend_publish_url`                 | `https://api.rostoc.co/api/updates/publish/` | Alternate backend endpoint (e.g., staging stack) |

If the token is missing the workflow simply records a summary note and skips the API call, keeping preview builds unaffected.

## ✅ Branch protection checklist

- Require commit status **`rostoc-updates/ci`** on the main branch (and any long-lived release branches) so merges only pass after the public CI workflow succeeds.
- Optionally require **`rostoc-updates/release`** for tag protection to ensure signed builds finish before the release is published.
- (Optional) Add a README badge pointing at the public workflow if you want a visible signal; the protected status already does the heavy lifting.

## 🛠 Local tooling

### Quick Start

```bash
# Install dependencies (one-time setup)
brew install actionlint  # Workflow linting

# Basic workflow - PRIMARY STRATEGY
make format              # Format workflow YAML
make lint                # Lint workflows + shell scripts
make test-script SCRIPT=<name>  # Test CI scripts directly
```

### Local CI Testing

**Before pushing to GitHub**, test your CI changes locally to get instant feedback:

```bash
# Test individual scripts (30 seconds) - PRIMARY METHOD
make test-local          # List available scripts
make test-script SCRIPT=generate_and_verify_config.sh

# Test with different environments
ROSTOC_APP_VARIANT=staging make test-script SCRIPT=stage_and_verify_runtime.sh

# Validate workflow syntax (5 seconds)
make format && make lint

# ⚡ NEW: Validate script paths (catches common CI bug)
make validate-paths
```

**🐛 Common CI Bug Prevented**: The `validate-paths` check catches script path issues that break when workflows use `working-directory`. This exact issue caused a full CI failure on 2025-12-31 - now preventable with one command!

**Example**:
```yaml
# ❌ Breaks if working-directory: private-src
run: scripts/ci/my_script.sh

# ✅ Works correctly
run: ../scripts/ci/my_script.sh
```

**⚠️ Note on Act**: Act cannot test the build workflow because it requires `macos-15` and `windows-2022` runners, which Act doesn't support (it only simulates Linux). For this repo, **direct script testing + native builds** provide faster and more accurate validation than Act.

**Full documentation**: See [docs/LOCAL_CI_TESTING.md](./docs/LOCAL_CI_TESTING.md) and [docs/LOCAL_CI_TESTING_CHEATSHEET.md](./docs/LOCAL_CI_TESTING_CHEATSHEET.md)

**Why local testing?** GitHub CI takes 30-50 minutes per run. Local testing gives feedback in 30 seconds to 5 minutes—that's **6-100x faster iteration**! 🚀