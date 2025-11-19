# DigitalOcean Spaces Migration Summary

## What Changed

Migrated binary storage from GitHub Releases to DigitalOcean Spaces to solve a critical notarization workflow issue.

## Problem

**GitHub Releases assets are immutable** - once uploaded, they cannot be replaced. This breaks the macOS notarization workflow:

1. Build workflow uploads unsigned DMG to GitHub Releases
2. Submits DMG to Apple for notarization (async, takes hours/days)
3. Stapler workflow needs to replace DMG with stapled version after approval
4. ❌ **Can't replace asset on GitHub Releases** - URLs become stale

## Solution: DigitalOcean Spaces

**Mutable S3-compatible object storage** - files can be overwritten at the same path/URL:

1. Build workflow uploads unsigned DMG to Spaces: `s3://BUCKET/releases/v0.2.95/Rostoc-0.2.95-darwin-aarch64.dmg`
2. Submits to Apple notarization
3. Stapler workflow downloads from Spaces, staples, **re-uploads to same path**
4. ✅ **CDN URL stays the same** - `releases.json` update marks DMG as available

## Files Modified

### Workflows

**`build-and-publish.yml`**:
- Removed `softprops/action-gh-release` step
- Added AWS CLI upload to DO Spaces for both macOS and Windows binaries
- Passes `DO_SPACES_CDN_URL` to manifest generation script
- (2024-05) Added backend publish hook that POSTs `/api/updates/publish/` with release+asset metadata whenever `ROSTOC_BACKEND_TOKEN` is configured

**`staple-notarized-dmg.yml`**:
- Added DO Spaces environment variables
- Installs AWS CLI in workflow runner
- No longer downloads from GitHub artifacts

### Scripts

**`scripts/ci/generate_releases_json.sh`**:
- Changed `GITHUB_RELEASES_URL` to `DO_SPACES_CDN_URL`
- All binary URLs now point to Spaces CDN instead of GitHub Releases

**`scripts/macos/staple_and_upload_dmg.sh`**:
- Replaced `download_pending_dmg()` - downloads from Spaces instead of GitHub artifacts
- Added `upload_stapled_dmg_to_spaces()` - uploads using AWS CLI
- Removed GitHub Pages repo file copy (DMG no longer stored in git)
- Updates `releases.json` with Spaces CDN URL

**`scripts/ci/build_backend_payload.py`** (2024-05): new helper that assembles release + asset metadata for the `/api/updates/publish/` workflow step.

### Documentation

**`README.md`**:
- Updated architecture section to describe Spaces + Pages hybrid
- Added DO Spaces secrets to required secrets table
- Documented notarization pipeline flow
- Linked to setup guide

**New files**:
- `DIGITALOCEAN_SPACES_SETUP.md` - Complete setup guide with testing steps
- `MIGRATION_SUMMARY.md` - This file

## Architecture Comparison

### Before (GitHub Releases)
```
[Build] → Upload to GitHub Releases (immutable)
          ↓
        latest.json (GitHub Pages)
          ↓
        [Tauri updater fetches from GitHub Releases]
```

**Problem**: Can't replace DMG after notarization

### After (DigitalOcean Spaces)
```
[Build] → Upload to DO Spaces (mutable)
          ↓
        Stapler replaces DMG on Spaces (same URL)
          ↓
        latest.json (GitHub Pages) → Points to Spaces CDN
          ↓
        [Tauri updater fetches from Spaces CDN]
```

**Benefit**: DMG URL never changes, stapling works seamlessly

## URL Changes

**Old pattern (GitHub Releases)**:
```
https://github.com/Alain1405/rostoc-updates/releases/download/v0.2.95/Rostoc-0.2.95-darwin-aarch64.app.tar.gz
```

**New pattern (DO Spaces CDN)**:
```
https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com/releases/v0.2.95/Rostoc-0.2.95-darwin-aarch64.app.tar.gz
```

**Manifests (unchanged)**:
```
https://alain1405.github.io/rostoc-updates/latest.json
https://alain1405.github.io/rostoc-updates/releases.json
```

## Required Secrets (New)

Add to `rostoc-updates` repository:

| Secret                 | Example                                                   |
| ---------------------- | --------------------------------------------------------- |
| `DO_SPACES_ACCESS_KEY` | `DO8XXXXXXXXXXXXX`                                        |
| `DO_SPACES_SECRET_KEY` | `xxxxxxxxxxx...`                                          |
| `DO_SPACES_BUCKET`     | `rostoc-releases`                                         |
| `DO_SPACES_ENDPOINT`   | `sgp1.digitaloceanspaces.com`                             |
| `DO_SPACES_CDN_URL`    | `https://rostoc-releases.sgp1.cdn.digitaloceanspaces.com` |
| `ROSTOC_BACKEND_TOKEN` | `service-token-from-backend`                              |

See [DIGITALOCEAN_SPACES_SETUP.md](./DIGITALOCEAN_SPACES_SETUP.md) for detailed instructions.

## Testing Checklist

Before first production release:

- [ ] Create DO Space with CDN enabled
- [ ] Generate API keys and add secrets to GitHub
- [ ] Test AWS CLI upload/download locally
- [ ] Create test release tag (e.g., `v0.2.95-test`)
- [ ] Verify binaries appear in Spaces under `releases/v0.2.95-test/`
- [ ] Check `releases.json` and `latest.json` have Spaces CDN URLs
- [ ] Verify Tauri updater can fetch from new URLs
- [ ] Wait 30min for stapler workflow to process notarization
- [ ] Check DMG is replaced in Spaces (download and verify staple)
- [ ] Confirm `releases.json` shows `available: true` for DMG

## Cost Impact

**DigitalOcean Spaces**: $5/mo for 250GB storage + 1TB transfer

**Estimated usage**:
- 10 releases × 200MB = 2GB storage
- 100 downloads/month × 200MB = 20GB transfer

**Well within free tier limits.**

## Rollback Plan

If migration fails, revert commits:

```bash
git revert <commit-sha>  # Revert DO Spaces changes
git push
```

Then restore GitHub Releases pattern:
1. Update `build-and-publish.yml` to use `softprops/action-gh-release`
2. Update `generate_releases_json.sh` to use `GITHUB_RELEASES_URL`
3. Revert `staple_and_upload_dmg.sh` to download from artifacts

See `DIGITALOCEAN_SPACES_SETUP.md` section 11 for detailed rollback steps.

## Migration Benefits

✅ **Solves notarization problem** - DMG can be replaced after stapling  
✅ **Simpler workflows** - No more binary preservation logic in GitHub Pages deployment  
✅ **Faster downloads** - CDN distribution vs GitHub Releases  
✅ **More control** - Direct S3 API access for debugging  
✅ **Cheap** - $5/mo vs potential GitHub Actions minutes

## Next Steps

1. **Setup**: Follow [DIGITALOCEAN_SPACES_SETUP.md](./DIGITALOCEAN_SPACES_SETUP.md)
2. **Test**: Create test release and verify complete workflow
3. **Wire backend token**: Store `ROSTOC_BACKEND_TOKEN` in repo secrets so release builds notify the backend
4. **Monitor**: Watch first notarization cycle to ensure stapling works
5. **Document**: Update any user-facing docs with new download URLs (if needed)
6. **Cleanup**: (Optional) Delete old releases from GitHub Releases once migration is stable
