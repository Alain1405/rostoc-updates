# rostoc-updates

Public workflow runner for Rostoc desktop builds. The private `alain1405/rostoc` repository dispatches CI and tagged release events to this repo so we can execute macOS/Windows builds on public runners and host updater artifacts via GitHub Pages.

## 🔐 Required secrets

| Secret | Scope | Purpose |
| --- | --- | --- |
| `PRIVATE_REPO_SSH_KEY` | Repository (rostoc-updates) | Deploy key with read access to the private `alain1405/rostoc` repo so the build workflow can clone sources. |
| `UPDATES_REPO_TOKEN` | Both repos | Personal access token with `repo` scope. In `rostoc-updates` it uploads release assets back to the private repo; in `alain1405/rostoc` it dispatches the workflows and polls for their results. |

## ⚙️ Workflow flow

1. **Push / PR in private repo** – `ci-build.yml` dispatches `trigger-ci` to this repo and waits for the `Dispatch CI Build` workflow to finish. Failures propagate back to the original commit/PR.
2. **Tag in private repo** – `trigger-public-build.yml` dispatches `trigger-release` and blocks until the `Dispatch Release Build` workflow succeeds. The release job builds signed artifacts, publishes `latest.json` to GitHub Pages, and re-uploads the tarball/signature to the private repo’s draft release.

If either side is missing the shared secrets, the dispatch/workflows will fail fast with actionable logs.