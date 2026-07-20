#!/usr/bin/env bash
set -euo pipefail

required_major="${1:-26}"

xcodebuild -version

actool_path=$(command -v actool || true)
if [[ -z "$actool_path" ]]; then
  echo "::error::actool is not available after selecting Xcode" >&2
  exit 1
fi

version_output=$(actool --version --output-format=human-readable-text)
printf '%s\n' "$version_output"

version=$(awk -F': ' '/short-bundle-version:/ { print $2; exit }' <<< "$version_output")
major="${version%%.*}"

if [[ ! "$major" =~ ^[0-9]+$ ]] || ((major < required_major)); then
  echo "::error::Liquid Glass icons require actool >= ${required_major}; selected short-bundle-version=${version:-unknown}" >&2
  exit 1
fi

echo "[INFO] Liquid Glass icon compiler ready: actool $version ($actool_path)"
