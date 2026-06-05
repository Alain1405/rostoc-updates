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

## Script Placement

Prefer dedicated script files in `scripts/ci/` over inline shell in workflow YAML.

- Default: extract non-trivial workflow logic into a checked-in script and call it from YAML.
- Keep YAML `run:` blocks as thin wrappers, ideally a single `bash ../scripts/ci/script_name.sh ...` invocation.
- Inline shell is acceptable only for very short glue code where extraction would add no clarity.
- `make validate-paths` now also warns on long inline `run: |` blocks, not just broken script paths.
- After extraction, always run `make validate-paths` because `working-directory` changes how `../scripts/ci/...` resolves.

## Path Contracts

Treat workflow paths as explicit contracts between three roots:

| Path family | Owner | Typical use |
|-------------|-------|-------------|
| `scripts/ci/**`, `.github/**`, `updates/**` | Public repo root | Workflow entrypoints, staged release artifacts, smoke artifacts |
| `private-src/**` | Private repo checkout root | Product source checkout, build outputs, runtime staging |
| `../updates/**` inside helper scripts with `working-directory: private-src` | Public repo root | Script-relative writes back into the updates repo |

Rules:

1. `working-directory: private-src` only changes the shell's cwd for that step. It does **not** move later workflow steps out of the public repo root.
2. If a helper script running from `private-src` writes to `../updates/...`, downstream YAML steps must read `updates/...`, not `private-src/updates/...`.
3. Do not reconstruct artifact paths from memory. Prefer helper outputs (`steps.<id>.outputs.*`) or the actual staging directory contract.
4. Build bundles may live under `private-src/target/...` or `private-src/src-tauri/target/...`. Use helper discovery or dual-root globs when collecting diagnostics instead of hardcoding one root.
5. `updates/**` is the canonical repo-level staging area for smoke/update artifacts. `private-src/**` is for source and immediate build outputs.

## CI Retrospective Guardrails

Use these checks whenever CI path bugs recur:

1. Identify the producer path, staging path, and consumer path separately before editing YAML.
2. Check whether a script path is interpreted from repo root or from a step `working-directory`.
3. When logs show a concrete path, update the skill or workflow to match that observed contract instead of preserving stale assumptions.
4. If a workflow appears not to trigger, inspect `on.push.paths` / `paths-ignore` before blaming dispatch. Empty commits do not satisfy path filters; use `workflow_dispatch` when needed.

## Shell Script Rules

When writing shell scripts for CI, whether extracted to `scripts/ci/` or kept inline for trivial glue:

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
