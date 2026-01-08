# Python Architecture Mismatch Fix

## Problem

Windows x64 builds were failing with:
```
error: your Rust target architecture (64-bit) does not match your python interpreter (32-bit)
```

## Root Cause

The `actions/setup-python@v5` action **defaults to x86 (32-bit) Python on Windows** when the `architecture` parameter is not explicitly specified.

From the [setup-python documentation](https://github.com/actions/setup-python#architecture):
> If `architecture` is not provided, it will default to `x86` on Windows and the platform default on other platforms.

## Solution

Explicitly specify the Python architecture for all Windows builds:

```yaml
- name: Setup Python 3.11 (Windows x64)
  if: ${{ inputs.platform == 'windows' && inputs.arch == 'x86_64' }}
  uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    architecture: 'x64'  # CRITICAL: Must specify for Windows

- name: Setup Python 3.11 (Windows x86)
  if: ${{ inputs.platform == 'windows' && inputs.arch == 'i686' }}
  uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    architecture: 'x86'  # Explicit for 32-bit builds
```

## Why This Matters

PyO3 (the Rust-Python binding library) requires the Python interpreter architecture to match the Rust target architecture:

- **Windows x64 build** (target: `x86_64-pc-windows-msvc`) → needs **64-bit Python**
- **Windows x86 build** (target: `i686-pc-windows-msvc`) → needs **32-bit Python**

Without explicit architecture specification, Windows x64 builds would get 32-bit Python, causing PyO3 to fail during compilation.

## Verification

Use the verification script to check Python architecture in CI:

```bash
# In build-prep step
- name: Verify Python architecture
  shell: bash
  run: |
    if [[ "${{ inputs.platform }}" == "windows" && "${{ inputs.arch }}" == "x86_64" ]]; then
      scripts/ci/verify_python_arch.sh x64
    elif [[ "${{ inputs.platform }}" == "windows" && "${{ inputs.arch }}" == "i686" ]]; then
      scripts/ci/verify_python_arch.sh x86
    fi
```

## Related Issues

- [PyO3 Issue #857](https://github.com/PyO3/pyo3/issues/857) - Architecture mismatch errors
- [actions/setup-python#114](https://github.com/actions/setup-python/issues/114) - Windows architecture defaults

## Commit

Fixed in commit: `e5cb5d0` - "fix(ci): Explicitly set x64 architecture for Windows x64 Python setup"
