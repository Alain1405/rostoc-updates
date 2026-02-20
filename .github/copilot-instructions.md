---
applyTo: '**'
---

# Rostoc Updates Repository Instructions

> Public workflow runner for Rostoc desktop builds. The private `Rostoc/rostoc`
> repo dispatches CI and release events here to execute macOS/Windows builds on
> public GitHub runners and host updater artifacts via GitHub Pages.

## Workspace Structure

- **Multi-root workspace**: Open `rostoc/rostoc-multi-root.code-workspace`
- `rostoc/` — product code (private)
- `rostoc-updates/` — CI pipelines, workflows (this repo)
- `rostoc-backend/` — Django backend for updates API and download analytics
- **Shared scripts**: Located in `../rostoc/scripts/` — workflows check out private repo

## Skills Reference

Detailed procedural knowledge lives in modular skills under `.github/skills/`.
These trigger automatically based on task context:

| Task | Skill |
|------|-------|
| tmate SSH debugging | `rostoc-updates-tmate` |
| Grafana Loki logs | `rostoc-updates-loki` |
| Shell linting, YAML validation | `rostoc-updates-linting` |
| Build context, version lookup | `rostoc-updates-version` |
| Fix failing CI checks | `gh-fix-ci` (in rostoc repo) |

## Workflow Architecture

### Dispatcher Pattern

1. **`ci-dispatch.yml`**: Push/PR in private repo → `build-and-publish.yml` with `is_release: false`
2. **`release-dispatch.yml`**: Tag creation → `build-and-publish.yml` with `is_release: true`
3. **`build-and-publish.yml`**: Reusable workflow for both platforms, tests, and artifacts

### Notarization Pipeline

- **Build workflow**: Submits DMG to Apple notarization, saves `submission_id` in `releases.json`
- **Stapler workflow** (`staple-notarized-dmg.yml`): Cron job that queries notarytool, staples ticket, uploads to Pages
- **Lifecycle**: Release enables stapler schedule; stapler self-disables when queue is empty

## Required Secrets

| Secret | Purpose |
|--------|---------|
| `PRIVATE_REPO_SSH_KEY` | Deploy key for `Rostoc/rostoc` |
| `UPDATES_REPO_TOKEN` | PAT for artifact uploads and workflow dispatch |
| `APPLE_CERTIFICATE` | Base64-encoded signing certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Certificate password |
| `APPLE_SIGNING_IDENTITY` | Signing identity name |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarytool |
| `TAURI_SIGNING_PRIVATE_KEY` | Tauri updater signing key |
| `SLACK_WEBHOOK_URL` | Build failure notifications |
| `LOKI_URL`, `LOKI_USERNAME`, `LOKI_PASSWORD` | Grafana Cloud Loki |

## Key Files

- `updates/releases.json`: Release manifest with download URLs, notarization status
- `updates/latest.json`: Current stable release metadata
- `scripts/ci/generate_releases_json.sh`: Builds release manifest entries
- `scripts/macos/staple_and_upload_dmg.sh`: Stapler script for scheduled workflow

## Workflow Permissions

All dispatcher workflows must declare:

```yaml
permissions:
  contents: write   # Push to this repo
  pages: write      # Deploy Pages
  id-token: write   # OIDC for Pages
  actions: write    # Enable/disable stapler workflow
```

## Validation

Always run before committing:

```bash
make format && make lint && make validate-paths && make test-env
```

See `rostoc-updates-linting` skill for detailed shell script rules.

## Common Pitfalls

1. **Missing `actions: write`** — Required for enabling/disabling workflows
2. **Stale Pages cache** — Clone git repo instead of querying Pages URL
3. **Unquoted variables** — Always quote: `"$VAR"`, `>> "$GITHUB_OUTPUT"`
4. **Script path bugs** — `working-directory` changes path resolution
5. **Empty env vars** — Use `${VAR?}` not `${VAR:?}` for optional values

## Documentation

- [docs/LOCAL_CI_TESTING.md](docs/LOCAL_CI_TESTING.md) — Testing guide
- [docs/LOCAL_CI_TESTING_CHEATSHEET.md](docs/LOCAL_CI_TESTING_CHEATSHEET.md) — Quick reference
- [docs/ENV_VAR_TESTING_SUMMARY.md](docs/ENV_VAR_TESTING_SUMMARY.md) — Env var patterns

## Branch Protection

- Main branch requires passing `rostoc-updates/ci` status check
- Optional: Protect tags with `rostoc-updates/release` check
