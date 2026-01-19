---
name: rostoc-updates-version
description: Retrieve build context, GitHub SHA, and Rostoc version from CI runs. Use when correlating CI runs to product versions, finding commit SHA for a workflow run, or debugging which version was built.
---

# Retrieving Build Context

Correlate GitHub Actions runs with Rostoc versions and commits.

## From GitHub UI

1. Go to workflow run: `https://github.com/Alain1405/rostoc-updates/actions/runs/<RUN_ID>`
2. Look for "triggered by commit" link in header
3. Check "Summary" section for commit SHA and message

**Commit SHA:** First 7 characters (e.g., `7f0b205`) with full SHA in URL

## Using GitHub CLI

```bash
# Get workflow run details including commit SHA
gh run view <RUN_ID> --repo Alain1405/rostoc-updates \
  --json headSha,headBranch,workflowName,conclusion,createdAt

# Get commit details from SHA
gh api repos/Alain1405/rostoc-updates/commits/<SHA> --jq '.commit.message'

# Get rostoc version from private repo commit
gh api repos/Alain1405/rostoc/contents/package.json?ref=<SHA> \
  --jq '.content' | base64 -d | jq -r '.version'
```

## Using GitHub MCP Tools

```python
# Get workflow run with commit SHA
mcp_github_github_actions_get(
    method='get_workflow_run',
    owner='Alain1405',
    repo='rostoc-updates',
    resource_id='20758186226'
)
# Returns: head_sha, head_branch, workflow_name, conclusion

# Get commit message and author
mcp_github_github_get_commit(
    owner='Alain1405',
    repo='rostoc-updates',
    ref='7f0b2054a6346563be8bce2462fac0df5e331a67'
)

# Get rostoc version from package.json
mcp_github_github_get_file_contents(
    owner='Alain1405',
    repo='rostoc',
    path='package.json',
    ref='main'  # or specific commit SHA
)
# Parse JSON to extract: .version
```

## Rostoc Version Sources

**Primary source:** `package.json` in private `rostoc` repo

```bash
# Local
cat /path/to/rostoc/package.json | jq -r '.version'

# From GitHub
gh api repos/Alain1405/rostoc/contents/package.json \
  --jq '.content' | base64 -d | jq -r '.version'
```

**Also available in:**
- `src-tauri/tauri.conf.json` → `.version`
- `src-tauri/Cargo.toml` → `[package] version`
- Build artifacts: DMG/MSI filename includes version

## Correlating CI Run → Version

### For Release Builds

```bash
# Git tag = rostoc version
git tag --points-at <COMMIT_SHA>
# Tag format: v0.2.183 → rostoc version 0.2.183
```

### For Dev/CI Builds

```bash
# Get commit SHA from workflow run
SHA=$(gh run view <RUN_ID> --json headSha --jq '.headSha')

# Check out private repo at that SHA
cd rostoc && git checkout $SHA

# Read version
jq -r '.version' package.json
```

### From Build Logs

```bash
# Search for version stamp
gh run view <RUN_ID> --log | grep -i "version"
gh run view <RUN_ID> --log | grep -i "Building Rostoc"

# Look for lines like:
# "Building Rostoc v0.2.183"
# "Version: 0.2.183-dev.123"
```

## Quick Reference Commands

```bash
# Get everything about a workflow run
gh run view 20758186226 --repo Alain1405/rostoc-updates

# Get commit that triggered it
gh run view 20758186226 --json headSha --jq '.headSha'

# Get rostoc version from that commit
SHA=$(gh run view 20758186226 --json headSha --jq '.headSha')
gh api repos/Alain1405/rostoc/contents/package.json?ref=$SHA \
  --jq '.content' | base64 -d | jq -r '.version'

# Get commit message
gh api repos/Alain1405/rostoc-updates/commits/$SHA --jq '.commit.message'
```
