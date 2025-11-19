# DigitalOcean Spaces Setup Guide

This guide walks through setting up DigitalOcean Spaces for hosting Rostoc release binaries.

## Overview

**Architecture:**
- **DO Spaces**: S3-compatible object storage for release binaries (.tar.gz, .dmg, .msi, .sig)
- **GitHub Pages**: Hosts JSON manifests (releases.json, latest.json)
- **GitHub Actions**: Uploads binaries to Spaces during build, downloads/replaces DMG during notarization

**Why Spaces?**
- Mutable storage: Can replace DMG after Apple notarization (GitHub Releases assets are immutable)
- S3-compatible API: Use AWS CLI for uploads/downloads
- Built-in CDN: Fast global distribution
- Cheap: $5/mo for 250GB storage + 1TB transfer

## 1. Create DigitalOcean Space

1. Log in to [DigitalOcean](https://cloud.digitalocean.com/)
2. Navigate to **Spaces** → **Create a Space**
3. Choose datacenter region (e.g., `sgp1` for Singapore)
4. **Space Name**: `rostoc-releases` (or your preferred name)
5. **Enable CDN**: Yes (provides `*.cdn.digitaloceanspaces.com` URL)
6. **File Listing**: Private (files are public-readable via ACL, but listing is disabled)
7. Create the Space

**Note the URLs:**
- Endpoint: `https://sgp1.digitaloceanspaces.com` (region-specific)
- CDN URL: `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com`

## 2. Generate API Keys

1. Navigate to **API** → **Spaces Keys**
2. Click **Generate New Key**
3. Name: `rostoc-ci` (or similar)
4. Save both:
   - **Access Key** (like `DO8XXXXXXXXXXXXX`)
   - **Secret Key** (like `xxxxxxxxxxx...`)

**Security:** Store these securely - the secret key is only shown once.

## 3. Configure GitHub Secrets

Add these secrets to **both** repositories:

### Private repo: `Alain1405/rostoc`
Not used directly, but good for local testing.

### Public repo: `Alain1405/rostoc-updates`

Go to **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Secret Name            | Value                            | Example                                                                |
| ---------------------- | -------------------------------- | ---------------------------------------------------------------------- |
| `DO_SPACES_ACCESS_KEY` | Your Spaces access key           | `DO8XXXXXXXXXXXXX`                                                     |
| `DO_SPACES_SECRET_KEY` | Your Spaces secret key           | `xxxxxxxxxxx...`                                                       |
| `DO_SPACES_BUCKET`     | Space name                       | `rostoc-releases`                                                      |
| `DO_SPACES_ENDPOINT`   | Endpoint URL (region-specific)   | `sgp1.digitaloceanspaces.com` OR `https://sgp1.digitaloceanspaces.com` |
| `DO_SPACES_CDN_URL`    | CDN base URL (no trailing slash) | `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com`              |

**Note:** `DO_SPACES_ENDPOINT` can be provided with or without `https://` prefix - the workflow will normalize it automatically.

## 4. Directory Structure in Spaces

Binaries are organized by version:

```
s3://rostoc-releases/
└── releases/
    ├── v0.2.95/
    │   ├── Rostoc-0.2.95-darwin-aarch64.app.tar.gz
    │   ├── Rostoc-0.2.95-darwin-aarch64.app.tar.gz.sig
    │   ├── Rostoc-0.2.95-darwin-aarch64.dmg (replaced after notarization)
    │   ├── Rostoc-0.2.95-windows-x86_64.msi
    │   └── Rostoc-0.2.95-windows-x86_64.msi.sig
    └── v0.2.96/
        └── ...
```

## 5. Testing with AWS CLI

Install AWS CLI locally:
```bash
brew install awscli  # macOS
```

Configure credentials:
```bash
export AWS_ACCESS_KEY_ID="DO8XXXXXXXXXXXXX"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxx..."
```

Test upload:
```bash
aws s3 cp test-file.txt s3://rostoc-releases/test/ \
  --endpoint-url https://sgp1.digitaloceanspaces.com \
  --region us-east-1 \
  --acl public-read
```

Test download:
```bash
aws s3 cp s3://rostoc-releases/test/test-file.txt downloaded.txt \
  --endpoint-url https://sgp1.digitaloceanspaces.com \
  --region us-east-1
```

Test public access via CDN:
```bash
curl -I https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com/test/test-file.txt
# Should return 200 OK
```

## 6. Workflow Integration

### Build Workflow (`build-and-publish.yml`)
- Uploads binaries to `s3://BUCKET/releases/vVERSION/` after build
- Sets `--acl public-read` for direct CDN access
- Generates `releases.json` and `latest.json` with Spaces CDN URLs
- Deploys manifests to GitHub Pages

### Stapler Workflow (`staple-notarized-dmg.yml`)
- Runs every 30 minutes via cron
- Checks `releases.json` on GitHub Pages for pending notarizations
- Downloads DMG from Spaces
- Submits to Apple notarytool (checks status)
- If accepted: Staples certificate, re-uploads DMG to Spaces (same path)
- Updates `releases.json` on GitHub Pages with `available: true`

## 7. URL Structure

Manifests (GitHub Pages):
- Latest release: `https://alain1405.github.io/rostoc-updates/latest.json`
- Version history: `https://alain1405.github.io/rostoc-updates/releases.json`

Binaries (DO Spaces CDN):
- macOS updater: `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com/releases/v0.2.95/Rostoc-0.2.95-darwin-aarch64.app.tar.gz`
- macOS installer: `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com/releases/v0.2.95/Rostoc-0.2.95-darwin-aarch64.dmg`
- Windows installer: `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com/releases/v0.2.95/Rostoc-0.2.95-windows-x86_64.msi`

## 8. Cost Estimate

DigitalOcean Spaces pricing (as of 2024):
- **Base plan**: $5/mo includes:
  - 250 GB storage
  - 1 TB outbound transfer
- **Overage**:
  - $0.02/GB storage
  - $0.01/GB transfer

**Estimated usage:**
- Per release: ~200 MB (macOS + Windows binaries)
- 10 releases stored: ~2 GB
- Monthly downloads: ~100 users × 200 MB = 20 GB

**Monthly cost**: $5 (well within limits)

## 9. Troubleshooting

### Upload fails with "Access Denied"
- Verify `DO_SPACES_ACCESS_KEY` and `DO_SPACES_SECRET_KEY` are correct
- Check API key permissions in DigitalOcean console

### CDN returns 404 but Spaces has the file
- CDN caching: Wait 5-10 minutes for cache to populate
- Check file ACL: Must be `public-read` (use `--acl public-read` flag)

### Stapler fails to download DMG
- Verify `DO_SPACES_CDN_URL` secret matches your Space's CDN URL
- Check version string matches exactly (case-sensitive)
- Verify DMG was uploaded during build step

### DMG not replaced after notarization
- Check `staple-notarized-dmg.yml` workflow logs
- Verify AWS CLI is installed in workflow
- Check Apple notarization status: `xcrun notarytool history --apple-id ... --team-id ...`

## 10. Migration Checklist

- [x] Create DO Space with CDN enabled
- [x] Generate API keys
- [ ] Add secrets to `rostoc-updates` repo
- [ ] Test upload/download with AWS CLI locally
- [ ] Create test release to verify workflow
- [ ] Monitor first notarization cycle (30min cron)
- [ ] Verify Tauri updater can fetch from new URLs
- [ ] Clean up old GitHub Releases (optional)

## 11. Rollback Plan

If Spaces integration fails, revert to previous GitHub Releases pattern:

1. Restore `.github/workflows/build-and-publish.yml` upload section:
   ```yaml
   - name: Upload release assets
     uses: softprops/action-gh-release@v2
     with:
       files: |
         artifacts/**/*.tar.gz
         artifacts/**/*.sig
   ```

2. Update `generate_releases_json.sh`:
   ```bash
   GITHUB_RELEASES_URL="https://github.com/Alain1405/rostoc-updates/releases/download"
   ```

3. Revert `staple_and_upload_dmg.sh` to download from GitHub artifacts
