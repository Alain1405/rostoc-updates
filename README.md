# rostoc-updates

[![Dispatch CI Build](https://github.com/Alain1405/rostoc-updates/actions/workflows/ci-dispatch.yml/badge.svg)](https://github.com/Alain1405/rostoc-updates/actions/workflows/ci-dispatch.yml)

[![Dispatch Release Build](https://github.com/Alain1405/rostoc-updates/actions/workflows/release-dispatch.yml/badge.svg)](https://github.com/Alain1405/rostoc-updates/actions/workflows/release-dispatch.yml)

Public workflow runner for Rostoc desktop builds. The private `alain1405/rostoc` repository dispatches CI and tagged release events to this repo so we can execute macOS/Windows builds on public runners and host updater artifacts.

## 📦 Architecture

**Binary Storage**: GitHub Releases (tied to git tags, never orphaned)  
**Metadata Hosting**: GitHub Pages (`latest.json`, `releases.json`)  
**Update Endpoint**: `https://alain1405.github.io/rostoc-updates/latest.json`

### Why GitHub Releases?

- **Zero maintenance**: Binaries persist automatically, no preservation logic needed
- **Standard pattern**: Industry-standard approach for desktop app distribution
- **Free hosting**: Included with GitHub
- **Tauri-native**: The updater already supports GitHub release URLs

### File Structure

```
GitHub Releases (per tag v0.2.x):
  ├── Rostoc-0.2.x-darwin-aarch64.app.tar.gz
  ├── Rostoc-0.2.x-darwin-aarch64.app.tar.gz.sig
  ├── Rostoc-0.2.x-windows-x86_64.msi
  ├── Rostoc-0.2.x-windows-x86_64.msi.sig
  └── Rostoc_0.2.x_aarch64.dmg (after notarization)

GitHub Pages (alain1405.github.io/rostoc-updates/):
  ├── latest.json          # Tauri updater manifest
  ├── releases.json        # Version history
  └── storybook/          # Documentation
```

## 🔐 Required secrets

| Secret                 | Scope                       | Purpose                                                                                                                                                                                         |
| ---------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PRIVATE_REPO_SSH_KEY` | Repository (rostoc-updates) | Deploy key with read access to the private `alain1405/rostoc` repo so the build workflow can clone sources.                                                                                     |
| `UPDATES_REPO_TOKEN`   | Both repos                  | Personal access token with `repo` scope. In `rostoc-updates` it uploads release assets back to the private repo; in `alain1405/rostoc` it dispatches the workflows and polls for their results. |

## ⚙️ Workflow flow

1. **Push / PR in private repo** – `ci-build.yml` fires a `trigger-ci` dispatch and exits immediately. The public `Dispatch CI Build` workflow reports its result back to the private repo via the status context `rostoc-updates/ci`.
2. **Tag in private repo** – `trigger-public-build.yml` fires `trigger-release` and exits. The public release workflow:
   - Builds signed macOS and Windows binaries
   - Uploads binaries as GitHub Release assets (to this repo, tagged with version)
   - Generates `latest.json` and `releases.json` with URLs pointing to GitHub Releases
   - Deploys manifests to GitHub Pages
   - Reports success via status context `rostoc-updates/release`

If either side is missing the shared secrets, the dispatch/workflows will fail fast with actionable logs.

## ✅ Branch protection checklist

- Require commit status **`rostoc-updates/ci`** on the main branch (and any long-lived release branches) so merges only pass after the public CI workflow succeeds.
- Optionally require **`rostoc-updates/release`** for tag protection to ensure signed builds finish before the release is published.
- (Optional) Add a README badge pointing at the public workflow if you want a visible signal; the protected status already does the heavy lifting.

## 🛠 Local tooling

- Install workflow linters: `brew install actionlint`
- Format workflow YAML: `make format`
- Lint workflow logic: `make lint`