#!/usr/bin/env bash
# Validate script paths in workflow YAML files
# Catches issues like relative paths that break when working-directory changes
#
# Usage: ./scripts/ci/validate_workflow_paths.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRIVATE_REPO_PATH="/Users/alainscialoja/code/new-coro/rostoc"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

errors=0
warnings=0

echo "🔍 Validating script paths in GitHub Actions workflows..."
echo -e "${BLUE}ℹ️  Checking scripts in both public repo and private repo (if available)${NC}"
echo ""

# Find all workflow and action files
workflow_files=$(find "$REPO_ROOT/.github" -name "*.yml" -o -name "*.yaml" 2>/dev/null || true)

if [ -z "$workflow_files" ]; then
  echo -e "${RED}❌ No workflow files found in .github/${NC}"
  exit 1
fi

# Check each workflow for script references
while IFS= read -r workflow_file; do
  rel_path="${workflow_file#$REPO_ROOT/}"
  
  # Extract script paths from shell commands
  # Look for patterns like: bash scripts/ci/something.sh, ./scripts/ci/something.sh, ../scripts/ci/something.sh
  script_refs=$(grep -n "scripts/ci/[a-zA-Z0-9_-]*\.sh" "$workflow_file" 2>/dev/null || true)
  
  if [ -n "$script_refs" ]; then
    echo "📄 Checking: $rel_path"
    
    while IFS=: read -r line_num line_content; do
      # Extract the script path
      script_path=$(echo "$line_content" | grep -o "[.]*scripts/ci/[a-zA-Z0-9_-]*\.sh" | head -1)
      
      if [ -z "$script_path" ]; then
        continue
      fi
      
      # Check if workflow has working-directory set
      has_working_dir=$(grep -B 50 "^$line_num:" "$workflow_file" | grep "working-directory:" || true)
      is_private_src=$(echo "$has_working_dir" | grep "private-src" || true)
      
      # Determine expected path based on context
      if [[ "$script_path" == ../scripts/ci/* ]]; then
        # Parent-relative path - good for working-directory contexts
        actual_path="$REPO_ROOT/${script_path#../}"
        if [ ! -f "$actual_path" ]; then
          echo -e "   ${RED}❌ Line $line_num: Script not found: $script_path${NC}"
          echo -e "      Expected: $actual_path"
          ((errors++))
        else
          echo -e "   ${GREEN}✓${NC} Line $line_num: $script_path (parent-relative, found)"
        fi
      elif [[ "$script_path" == ./scripts/ci/* ]] || [[ "$script_path" == scripts/ci/* ]]; then
        # Repo-relative path
        actual_path_public="$REPO_ROOT/${script_path#./}"
        actual_path_private="$PRIVATE_REPO_PATH/${script_path#./}"
        
        found_in_public=false
        found_in_private=false
        
        if [ -f "$actual_path_public" ]; then
          found_in_public=true
        fi
        
        if [ -d "$PRIVATE_REPO_PATH" ] && [ -f "$actual_path_private" ]; then
          found_in_private=true
        fi
        
        if ! $found_in_public && ! $found_in_private; then
          echo -e "   ${RED}❌ Line $line_num: Script not found: $script_path${NC}"
          echo -e "      Expected in public repo: $actual_path_public"
          if [ -d "$PRIVATE_REPO_PATH" ]; then
            echo -e "      Or in private repo: $actual_path_private"
          fi
          ((errors++))
        elif [ -n "$is_private_src" ]; then
          # Using working-directory: private-src - script should be in private repo
          if $found_in_private; then
            echo -e "   ${GREEN}✓${NC} Line $line_num: $script_path (private-src context, found in private repo)"
          elif $found_in_public; then
            echo -e "   ${YELLOW}⚠️  Line $line_num: $script_path found in public repo but used with working-directory: private-src${NC}"
            echo -e "      This might work in CI but seems inconsistent. Consider: ../$script_path"
            ((warnings++))
          fi
        elif [ -n "$has_working_dir" ]; then
          # Has working-directory but not private-src - path likely wrong
          if $found_in_public; then
            echo -e "   ${YELLOW}⚠️  Line $line_num: $script_path uses repo-relative path but workflow has working-directory${NC}"
            echo -e "      This will likely fail in CI. Consider using: ../$script_path"
            ((warnings++))
          elif $found_in_private; then
            echo -e "   ${YELLOW}⚠️  Line $line_num: $script_path found in private repo, working-directory may not access it${NC}"
            ((warnings++))
          fi
        else
          # No working-directory - public repo path is correct
          if $found_in_public; then
            echo -e "   ${GREEN}✓${NC} Line $line_num: $script_path (repo-relative, found)"
          elif $found_in_private; then
            echo -e "   ${BLUE}ℹ️  Line $line_num: $script_path found only in private repo${NC}"
            echo -e "      Will be available during CI when private repo is checked out"
          fi
        fi
      fi
    done <<< "$script_refs"
    
    echo ""
  fi
done <<< "$workflow_files"

# Check that all scripts in scripts/ci/ are actually used
echo "🔍 Checking for unused scripts..."
for script_file in "$REPO_ROOT/scripts/ci"/*.sh "$REPO_ROOT/scripts/ci"/*.py; do
  if [ ! -f "$script_file" ]; then
    continue
  fi
  
  script_name=$(basename "$script_file")
  
  # Skip the test harness and this validator
  if [[ "$script_name" == "test_locally.sh" ]] || [[ "$script_name" == "validate_workflow_paths.sh" ]]; then
    continue
  fi
  
  # Check if script is referenced anywhere in workflows
  if ! grep -r "$script_name" "$REPO_ROOT/.github" > /dev/null 2>&1; then
    echo -e "   ${YELLOW}⚠️  Script not referenced in any workflow: scripts/ci/$script_name${NC}"
    ((warnings++))
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Validation Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
  echo -e "${GREEN}✅ All script paths are valid!${NC}"
  exit 0
elif [ "$errors" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  $warnings warning(s) found${NC}"
  echo ""
  echo "Fix warnings to prevent CI failures when working-directory changes."
  exit 0
else
  echo -e "${RED}❌ $errors error(s) and $warnings warning(s) found${NC}"
  echo ""
  echo "Fix these issues before pushing to avoid CI failures."
  exit 1
fi
