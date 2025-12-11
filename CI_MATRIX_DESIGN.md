# CI Matrix Build Strategy

## Overview

The `build-and-publish.yml` workflow has been refactored to use a matrix build strategy that runs multiple platform builds in parallel, with optional new platforms that don't block releases.

## Matrix Configuration

```yaml
build-desktop:
  strategy:
    matrix:
      include:
        # BLOCKING platforms (required for release)
        - os: macos-15
          platform: macos
          arch: aarch64
          name: "macOS ARM64 (M1)"
          is_optional: false

        - os: windows-2022
          platform: windows
          arch: x86_64
          name: "Windows x64"
          is_optional: false

        # OPTIONAL platforms (experimental, don't block releases)
        - os: macos-15-intel
          platform: macos
          arch: x86_64
          name: "macOS Intel x86-64"
          is_optional: true

        - os: windows-2022
          platform: windows
          arch: i686
          name: "Windows x86 (32-bit)"
          is_optional: true

        - os: ubuntu-latest
          platform: linux
          arch: x86_64
          name: "Linux AppImage x86-64"
          is_optional: true
```

### Platform Job Characteristics

| Platform | Runner | Arch | Blocking | Status | Notes |
|----------|--------|------|----------|--------|-------|
| macOS M1 | `macos-15` (free) | ARM64 | ✅ | ✅ Stable | Notarization + codesigning |
| Windows x64 | `windows-2022` (free) | x86-64 | ✅ | ✅ Stable | MSI packaging, WiX |
| macOS Intel | `macos-15-intel` (free) | x86-64 | ❌ | 🧪 Optional | Same signing as M1 |
| Windows x86 | `windows-2022` (free) | x86 | ❌ | 🧪 Optional | Cross-compile via `i686-pc-windows-msvc` |
| Linux AppImage | `ubuntu-latest` (free) | x86-64 | ❌ | 🧪 Optional | New: AppImage bundler |

## Key Changes Made

### 1. Platform Configuration Step
A new `Initialize platform-specific config` step detects the matrix variables and outputs platform-specific build commands:

```bash
# Outputs set based on matrix.platform and matrix.arch:
# - build_command: e.g., "python scripts/build.py --locked" (macOS)
#                       "python scripts/build.py --locked --bundles msi" (Windows)
#                       "python scripts/build.py --locked --bundles appimage" (Linux)
# - artifact_extension: tar.gz | msi | AppImage
# - target: Rust target triple (e.g., aarch64-apple-darwin, i686-pc-windows-msvc)
# - py_url_fragment: Download URL fragment for Python runtime
```

### 2. Platform-Specific Initialization
Before the main build:

- **macOS Intel**: Confirm runner is actually x86-64 (logs runner uname output)
- **Windows x86**: Install `i686-pc-windows-msvc` Rust target for cross-compilation
- **Linux**: Install AppImage build dependencies (libssl-dev, libffi-dev, libx11-6, fuse3)

### 3. Conditional Steps
MacOS-specific steps now use `if: matrix.platform == 'macos'`:

- ✅ Apple signing certificate installation
- ✅ Keychain state debugging
- ✅ Python runtime staging and codesigning
- ✅ DMG signing and notarization prep
- ✅ App bundle verification and smoke tests

Windows-specific steps (hidden in existing job; will expand):

- ✅ Embedded Python DLL verification
- ✅ MSI installer generation
- ✅ x86 runtime staging (future)

Linux-specific steps (new):

- ✅ AppImage bundler invocation
- ✅ Runtime smoke test (xfail-friendly)

### 4. Build Command Execution
The unified "Build application" step uses platform-aware variables:

```bash
BUILD_CMD="${{ steps.platform_config.outputs.build_command }}"
LOG_FILE="build-${{ matrix.platform }}-${{ matrix.arch }}.log"
$BUILD_CMD 2>&1 | tee "$LOG_FILE"
```

### 5. Artifact Handling
Post-build steps will be refactored to:

1. Detect platform-specific artifact types (.tar.gz for macOS, .msi for Windows, .AppImage for Linux)
2. Store paths in job outputs (already added: `artifact_path`, `artifact_type`)
3. Upload to Spaces/Pages with platform-aware paths

## Workflow Behavior

### Release Builds (`is_release: true`)
- **Blocking jobs** (macOS M1, Windows x64): Must succeed to proceed
- **Optional jobs** (new platforms): Run in parallel but don't block
- If optional jobs fail, release is still published (with warnings in summary)

### Preview/CI Builds (`is_release: false`)
- All jobs run with `continue-on-error: true` (non-fatal failures)
- Useful for validating new platform support incrementally

### Job Status Rules
```yaml
build-desktop:
  continue-on-error: ${{ matrix.is_optional }}
```

- Blocking jobs: `continue-on-error: false` → fail fast for release
- Optional jobs: `continue-on-error: true` → keep going even if they fail

## Incremental Implementation Plan

Since the workflow is large, implementation is incremental:

### Phase 1 (✅ COMPLETED)
- [x] Add matrix definition with 5 platform configs
- [x] Add platform initialization step with conditional detection
- [x] Wrap macOS certificate + signing steps with `if: matrix.platform == 'macos'`
- [x] Add platform-specific Python download (bash for macOS, pwsh for Windows, none for Linux)
- [x] Add platform-specific initialization (Intel confirmation, x86 rustup, Linux deps)
- [x] Update "Build application" to use matrix-aware build command
- [x] Update timeout (30min for Linux, 50min for others)
- [x] Wrap all macOS-specific verification and smoke test steps
- [x] Update job dependencies: generate-releases-json, publish-to-pages, finalize-status → depend on `build-desktop`
- [x] Disable legacy `build-windows` job (set `if: false`)
- [x] Run actionlint validation and fix all shellcheck issues
- [x] Update summary steps to work with matrix outputs

### Phase 2 (TODO)
- [ ] Wrap all remaining macOS-specific steps (app bundle verification, smoke tests)
- [ ] Refactor artifact detection to be platform-agnostic
- [ ] Add platform-specific artifact staging (handle .tar.gz, .msi, .AppImage)
- [ ] Update upload-to-Spaces to be platform-aware
- [ ] Test macOS Intel build locally with matrix (or use a dry-run workflow)

### Phase 3 (TODO)
- [ ] Add Windows x86 cross-compile handling in post-build steps
- [ ] Implement x86 .exe testing on x64 Windows runner
- [ ] Add Linux AppImage test harness (execute AppImage with --help)
- [ ] Wire up optional job failures to summary annotations

### Phase 4 (TODO)
- [ ] Enable stapler schedule for all macOS variants (Intel too)
- [ ] Add experimental badge to optional platform artifacts in releases.json
- [ ] Document known limitations and testing matrix in README.md

## Build Command Variations

```bash
# macOS (ARM64 M1)
python scripts/build.py --locked

# macOS (Intel x86-64)
python scripts/build.py --locked

# Windows (x64)
python scripts/build.py --locked --bundles msi

# Windows (x86 via cross-compile)
RUST_TARGET=i686-pc-windows-msvc python scripts/build.py --locked --bundles msi

# Linux (AppImage)
python scripts/build.py --locked --bundles appimage
```

## Artifact Paths (Post-Build)

- **macOS (arm64)**: `target/release/bundle/dmg/*.dmg`, `target/release/bundle/macos/*.tar.gz`
- **macOS (x86)**: Same as above (same bundle layout)
- **Windows (x64)**: `target/release/bundle/msi/*.msi`
- **Windows (x86)**: `target/i686-pc-windows-msvc/release/bundle/msi/*.msi` (cross-compile variant)
- **Linux**: `target/release/bundle/appimage/*.AppImage`

## Testing & Validation

### Quick CI Run (Preview Mode)
```bash
gh workflow run build-and-publish.yml \
  -f is_release=false \
  -f ref=main
```

All jobs will run with `continue-on-error: true`. Expected outcome: see which new platforms pass/fail.

### Full Release Build
Only triggered on tag push (existing dispatch). Release will only block if M1 or x64 Windows jobs fail.

### Manual Optional-Job Testing
```bash
gh workflow run build-and-publish.yml \
  -f is_release=false \
  -f ref=mybranch
# Watch Actions tab → expect optional jobs to show warnings if they fail
```

## Future Enhancements

1. **Dynamic runner selection**: Use larger runners for compile-heavy jobs (if needed)
2. **Artifact caching across platforms**: Share compiled Rust/Node artifacts where possible
3. **Parallel notarization**: All macOS variants queue notarization simultaneously
4. **Conditional release publication**: Publish only once, with multi-platform artifacts
5. **GitHub Packages**: Store intermediate artifacts (wheels, node_modules) for faster re-runs
