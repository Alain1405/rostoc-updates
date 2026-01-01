# Environment Variable Testing - Implementation Summary

## Problem Statement

On **2026-01-01**, CI failed with this error:
```
../scripts/ci/execute_build.sh: line 7: TAURI_CONFIG_FLAG: parameter null or not set
```

**Root Cause**: Used `${VAR:?}` which fails on empty values, but `TAURI_CONFIG_FLAG` is intentionally empty for production builds (no config overlay needed).

**Fix**: Changed to `${VAR?}` which allows empty values but still fails if unset.

## Prevention Tools Created

### 1. Static Analysis Test (`test_env_handling.sh`)

**Purpose**: Proactively catch incorrect use of `:?` pattern before CI runs.

**What it checks:**
- Scans all CI scripts for `${VAR:?}` patterns
- Validates against known variables that can be empty
- Tests scripts with empty values to ensure they don't fail
- Provides best practices documentation

**Usage:**
```bash
make test-env
```

**Output:**
```
📄 Checking: execute_build.sh
   ❌ Line 7: TAURI_CONFIG_FLAG uses :? but can be empty in production
      Fix: Change ${TAURI_CONFIG_FLAG:?} to ${TAURI_CONFIG_FLAG?}
   ✓ Line 6: ROSTOC_APP_VARIANT correctly requires non-empty value
```

### 2. Regression Test (`test_env_regression.sh`)

**Purpose**: Document the specific bug and verify the fix works correctly.

**What it tests:**
1. **Bug simulation**: Confirms `${VAR:?}` fails with empty values
2. **Fix validation**: Confirms `${VAR?}` accepts empty values
3. **Unset behavior**: Both patterns correctly fail when variable is unset
4. **Script verification**: Checks `execute_build.sh` has the fix applied

**Usage:**
```bash
make test-env-regression
```

**Output:**
```
✅ Bug correctly detected - script fails with empty value
✅ Fix works - script accepts empty value
✅ Both patterns correctly fail when unset
✅ execute_build.sh uses correct pattern
```

## Bash Environment Variable Patterns

| Pattern | Unset | Empty String | Usage |
|---------|-------|--------------|-------|
| `${VAR:?msg}` | ❌ Fails | ❌ Fails | Use when value MUST be non-empty |
| `${VAR?msg}` | ❌ Fails | ✅ Allows | Use when empty is valid |
| `${VAR:-default}` | Uses default | Uses default | Provide fallback |
| `${VAR-default}` | Uses default | ✅ Allows empty | Fallback for unset only |

## Variables That Can Be Empty

Document here when adding new variables:

| Variable | Context | Why Empty is Valid |
|----------|---------|-------------------|
| `TAURI_CONFIG_FLAG` | Production builds | No config overlay needed |
| `DEV_VERSION_SUFFIX` | Release builds | Not a dev build |
| `DEBUG_FLAG` | Production | Debug disabled |

## Integration

### Pre-Push Checklist

Add to your workflow:
```bash
make validate-paths     # Catch path bugs
make test-env           # Catch env var bugs
make lint               # Catch syntax errors
```

### Makefile Targets

- `make test-env` - Run static analysis on all scripts
- `make test-env-regression` - Run specific regression test
- `make help` - Shows complete testing guide

### Documentation Updated

- [LOCAL_CI_TESTING.md](LOCAL_CI_TESTING.md) - Added "Environment Variable Handling Tests" section
- [LOCAL_CI_TESTING_CHEATSHEET.md](LOCAL_CI_TESTING_CHEATSHEET.md) - Added to pre-push checklist
- [Makefile](../../Makefile) - Added `test-env` and `test-env-regression` targets

## Impact

**Before:**
- ❌ No validation for env var handling
- ❌ CI failures caught only after 30-50 min build
- ❌ Easy to introduce regressions

**After:**
- ✅ Catches bugs in <5 seconds locally
- ✅ Prevents specific regression from 2026-01-01
- ✅ Documents best practices for contributors
- ✅ Integrated into pre-push workflow

## Future Enhancements

1. **Auto-detect more variables**: Scan workflow files to find all env vars and suggest which should allow empty values
2. **GitHub Actions integration**: Run `test-env` as part of CI workflow
3. **Pre-commit hook**: Automatically run before git commit
4. **Variable registry**: Maintain central list of all env vars with their empty-value policies

## References

- **CI Failure**: https://github.com/Alain1405/rostoc-updates/actions/runs/20633195252/job/59254550486
- **Fix Commit**: "fix(ci): Allow empty TAURI_CONFIG_FLAG for production builds"
- **Bash Parameter Expansion**: https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
