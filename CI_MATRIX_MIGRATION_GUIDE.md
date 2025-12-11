# CI Matrix Migration Guide

## Summary

The `build-and-publish.yml` workflow has been refactored from separate `build-macos` and `build-windows` jobs into a single `build-desktop` matrix job that runs 5 platform configurations in parallel:

- **Blocking (required for release):**
  - macOS ARM64 (M1) on `macos-15`
  - Windows x64 on `windows-2022`

- **Optional (experimental, don't block releases):**
  - macOS Intel (x86-64) on `macos-15-intel`
  - Windows x86 (32-bit) via cross-compile on `windows-2022`
  - Linux AppImage (x86-64) on `ubuntu-latest`

## What Changed

### Before
```yaml
jobs:
  build-macos:
    runs-on: macos-15
    # ... macOS-specific steps

  build-windows:
    runs-on: windows-2022
    # ... Windows-specific steps

  generate-releases-json:
    needs: [build-macos, build-windows]
```

### After
```yaml
jobs:
  build-desktop:
    strategy:
      matrix:
        include:
          - {os: macos-15, platform: macos, arch: aarch64, is_optional: false}
          - {os: windows-2022, platform: windows, arch: x86_64, is_optional: false}
          - {os: macos-15-intel, platform: macos, arch: x86_64, is_optional: true}
          - {os: windows-2022, platform: windows, arch: i686, is_optional: true}
          - {os: ubuntu-latest, platform: linux, arch: x86_64, is_optional: true}
    continue-on-error: ${{ matrix.is_optional }}
    # ... platform-aware steps

  generate-releases-json:
    needs: [build-desktop]
```

## Key Features

### 1. Matrix-Driven Configuration
Each build variant is defined in a single matrix entry with:
- `os`: The GitHub Actions runner
- `platform`: The target platform (macos, windows, linux)
- `arch`: The target architecture (aarch64, x86_64, i686)
- `is_optional`: Whether this job can fail without blocking release

### 2. Platform Detection Step
A new `Initialize platform-specific config` step runs early and outputs platform-specific variables:
```bash
platform_config.outputs.build_command     # e.g., "python scripts/build.py --locked"
platform_config.outputs.target            # e.g., "aarch64-apple-darwin"
platform_config.outputs.artifact_extension # e.g., "tar.gz" or "msi" or "AppImage"
```

### 3. Conditional Step Execution
Platform-specific steps are wrapped with conditions:
```yaml
- name: "[macOS] Install Apple signing certificate"
  if: matrix.platform == 'macos'
  # ...

- name: "[Windows x86] Verify cross-compile capability"
  if: matrix.arch == 'i686' && matrix.platform == 'windows'
  # ...

- name: "[Linux] Install system dependencies for AppImage"
  if: matrix.platform == 'linux'
  # ...
```

### 4. Unified Build Command
All platforms use a single build invocation with matrix-specific variables:
```bash
BUILD_CMD="${{ steps.platform_config.outputs.build_command }}"
$BUILD_CMD 2>&1 | tee "build-${{ matrix.platform }}-${{ matrix.arch }}.log"
```

### 5. Optional Job Behavior
```yaml
continue-on-error: ${{ matrix.is_optional }}
```

- **Blocking jobs** (`is_optional: false`): Fail fast; one failure stops the matrix
- **Optional jobs** (`is_optional: true`): Continue even if they fail; allows experimental platforms to be tested without blocking releases

## Testing the New Matrix

### 1. Quick Dry Run (All Optional)
```bash
gh workflow run build-and-publish.yml \
  -f is_release=false \
  -f ref=main
```

Expected: All 5 jobs run in parallel. If a new platform fails, it shows as a warning, not an error.

### 2. Block Experimental Platforms Temporarily
If you need to focus on blocking platforms only during development, you can run:

```bash
gh workflow run build-and-publish.yml \
  -f is_release=false \
  -f ref=mybranch
```

Then manually skip the optional jobs via GitHub Actions UI (or update matrix `include` list temporarily).

### 3. Full Release Build
```bash
git tag v0.2.95
git push origin v0.2.95
```

This triggers the dispatcher, which runs the full matrix:
- M1 and x64 Windows jobs must succeed → release proceeds
- New platform jobs can fail without blocking → warnings in summary

## Phase 2: Artifact Handling (TODO)

Currently, artifact staging is macOS-specific. Phase 2 will:

1. **Platform-aware artifact detection**: Detect .tar.gz (macOS), .msi (Windows), .AppImage (Linux) from build outputs
2. **Unified staging**: Copy artifacts to `updates/<platform>/` directory structure
3. **Spaces upload**: Upload all platform artifacts to DigitalOcean Spaces with versioned paths
4. **Manifest generation**: Update `releases.json` with multi-platform download URLs

## Phase 3: Windows x86 & Linux Testing (TODO)

1. **Windows x86 testing**:
   - Run built .exe on x64 Windows runner (cross-platform execution)
   - Validate 32-bit installer package

2. **Linux AppImage testing**:
   - Execute AppImage with `--help` to validate bundled Python
   - Smoke test GUI (with timeout)

## Known Limitations (Phase 1)

1. **Artifact outputs are macOS-only**: The job outputs include `version`, `platform`, `arch` but not artifact paths yet
   - Workaround: `generate-releases-json` job pulls artifacts from upload-artifact instead
   - Will be fixed in Phase 2

2. **Notarization only for macOS**: Stapler workflow only handles macOS DMGs
   - Windows MSI signing is built-in to Tauri (no post-build step needed)
   - Linux AppImage doesn't require notarization
   - Will document in future update

3. **Spaces upload is macOS-specific**: Only the macOS job uploads to Spaces
   - Windows/Linux artifacts must be staged by Phase 2 refactoring
   - Temporary: Artifacts are collected via upload-artifact and processed by `generate-releases-json`

## Troubleshooting

### "My platform job failed but isn't in the summary"
Check the Actions tab for the matrix job. Optional jobs (Intel, x86, Linux) show failures as warnings only. Look at individual job logs under "Matrix" section.

### "How do I skip optional jobs locally?"
Edit the matrix `include` list in `build-and-publish.yml` to comment out unwanted entries, or use GitHub's UI to select specific matrix combinations.

### "Build logs show platform name wrong"
Double-check that the matrix `name` field matches the `platform` and `arch` combination. The logs are named as `build-{platform}-{arch}.log`.

### "Windows x86 build never completes"
The `i686-pc-windows-msvc` target download can be slow. Check runner logs for "Verifying cross-compile capability" step. This is normal on first run.

## Summary of Files Changed

- **`.github/workflows/build-and-publish.yml`**: Refactored with matrix, platform detection, conditional steps
- **`CI_MATRIX_DESIGN.md`**: Design documentation (this repo)
- No changes to build scripts (`scripts/build.py`, `scripts/macos/`, `scripts/windows/`) needed for Phase 1

## Next Steps

1. **Test the matrix**: Trigger a CI run on main branch, verify all 5 jobs run in parallel
2. **Monitor build times**: Ensure total wall-clock time doesn't regress (parallel jobs should help)
3. **Plan Phase 2**: Artifact staging and platform-aware uploads
4. **Document new platforms**: Add platform-specific notes to README once they're stable
