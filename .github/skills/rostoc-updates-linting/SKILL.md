---
name: rostoc-updates-linting
description: Code quality and linting rules for Rostoc CI workflows. Use when writing shell scripts in workflows, fixing shellcheck errors, validating YAML syntax, or debugging script path issues in GitHub Actions.
---

# Code Quality & Linting

## Pre-Commit Validation

**Always run before committing changes:**

```bash
# Complete validation suite (recommended)
make format && make lint && make validate-paths && make test-env

# Individual commands
make format          # Format YAML with Prettier
make lint            # Validate workflows with actionlint + shellcheck
make validate-paths  # Catch script path bugs (working-directory issues)
make test-env        # Catch env var bugs (empty value handling)
```

## What Each Test Prevents

| Command | Prevents |
|---------|----------|
| `format` & `lint` | Syntax errors, shellcheck issues |
| `validate-paths` | Script paths broken by `working-directory` (Dec 31, 2025 bug) |
| `test-env` | Incorrect `${VAR:?}` usage for empty-allowed vars (Jan 1, 2026 bug) |

## Shell Script Rules

When writing shell scripts in workflow `run:` blocks:

### Variable Quoting

```bash
# ✅ Correct
echo "$VAR"
>> "$GITHUB_OUTPUT"

# ❌ Wrong
echo $VAR
>> $GITHUB_OUTPUT
```

### Grouped Redirects

```bash
# ✅ Correct
{ echo "line1"; echo "line2"; } >> file

# ❌ Wrong (multiple redirects)
echo "line1" >> file
echo "line2" >> file
```

### Glob Prefixing

```bash
# ✅ Correct (prefix with ./)
./*.tar.gz

# ❌ Wrong (dash confusion)
*.tar.gz
```

### Shellcheck Disables

```bash
# Use when intentional (e.g., literal backticks in Markdown)
# shellcheck disable=SCxxxx
```

## Environment Variable Patterns

| Pattern | Unset | Empty | Use When |
|---------|-------|-------|----------|
| `${VAR:?msg}` | ❌ Fails | ❌ Fails | Value MUST be non-empty |
| `${VAR?msg}` | ❌ Fails | ✅ Allows | Empty is valid (e.g., `TAURI_CONFIG_FLAG` in prod) |

**Known variables that can be empty:**
- `TAURI_CONFIG_FLAG` - Empty for production builds (no config overlay)
- `DEV_VERSION_SUFFIX` - Empty for release builds
- `DEBUG_FLAG` - Empty for production builds

## YAML Formatting

- 2-space indentation
- Consistent string quoting (Prettier handles this)
- Avoid `<<EOF` heredocs; use grouped echo statements

## Validation Tools

```bash
# Install
brew install actionlint  # Includes shellcheck dependency

# Manual validation
actionlint -verbose
shellcheck scripts/ci/*.sh
```

## Common Pitfalls

1. **Unquoted variables** → Fails shellcheck; always quote
2. **Heredocs in YAML** → Avoid `<<EOF`; use grouped echo with braces
3. **Script path bugs** → `working-directory` changes path resolution
4. **Empty env vars** → Use `${VAR?}` not `${VAR:?}` for optional values
