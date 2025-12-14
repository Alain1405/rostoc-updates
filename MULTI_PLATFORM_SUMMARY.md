# Multi-Platform Backend Publishing

## What Changed

Extended backend submission to include **all successful builds** from the CI matrix, not just macOS ARM64 and Windows x64.

## Supported Platforms

The backend now accepts artifacts from:

- **macOS**: aarch64 (M1/M2/M3), x86_64 (Intel)
- **Windows**: x86_64 (64-bit), i686 (32-bit)  
- **Linux**: x86_64 (64-bit), aarch64 (ARM64)

## How It Works

### 1. Dynamic Discovery

`build_backend_payload.py` now iterates through all platform/architecture combinations:

```python
platform_configs = [
    ("macos", "aarch64", args.mac_root, mac_checksums),
    ("macos", "x86_64", args.mac_root, mac_checksums),
    ("windows", "x86_64", args.windows_root, windows_checksums),
    ("windows", "i686", args.windows_root, windows_checksums),
    ("linux", "x86_64", args.linux_root, linux_checksums),
    ("linux", "aarch64", args.linux_root, linux_checksums),
]
```

### 2. Graceful Skipping

If an artifact root doesn't exist or no artifacts are found for a platform/arch:
- Script prints a notice and continues
- Only platforms with actual built artifacts are included

### 3. Artifact Types

For each platform/arch combination found:
- **Updater archive** (.tar.gz): For in-app updates
- **Installer**: Platform-specific (DMG/MSI/AppImage)
- **Signatures** (.sig): When present

### 4. Workflow Integration

`publish.yml` now:
1. Creates `linux-artifacts/` directory alongside `macos-artifacts/` and `windows-artifacts/`
2. Consolidates Linux artifacts if present (non-fatal if missing)
3. Passes `--linux-root linux-artifacts` to backend payload script

## Benefits

✅ **Optional platforms auto-included** - If Linux or Intel Mac builds succeed, they're published  
✅ **No hardcoded platform list** - Add new platforms by updating the config list only  
✅ **Fail-safe** - Missing optional platforms don't break the pipeline  
✅ **Centralized naming** - Uses `ARTIFACT_NAMING` class for consistent artifact discovery  

## Backend Impact

The backend will now receive payloads with multiple platform/architecture combinations per release:

```json
{
  "channel": "stable",
  "version": "0.2.138",
  "assets": [
    {"platform": "macos", "architecture": "arm64", "kind": "archive", ...},
    {"platform": "macos", "architecture": "arm64", "kind": "installer", ...},
    {"platform": "macos", "architecture": "x64", "kind": "archive", ...},
    {"platform": "macos", "architecture": "x64", "kind": "installer", ...},
    {"platform": "windows", "architecture": "x64", "kind": "installer", ...},
    {"platform": "linux", "architecture": "x64", "kind": "installer", ...}
  ]
}
```

## Testing

To test with a specific subset:
1. Trigger release build with desired platform matrix
2. Only platforms that complete successfully will be submitted
3. Check backend for presence of new architecture entries
