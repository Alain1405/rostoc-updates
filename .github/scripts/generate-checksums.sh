#!/usr/bin/env bash
# Generate checksums for all artifacts in a directory
set -euo pipefail

ARTIFACTS_DIR="${1:?Usage: $0 <artifacts_dir>}"

if [[ ! -d "$ARTIFACTS_DIR" ]]; then
  echo "[ERROR] Directory not found: $ARTIFACTS_DIR" >&2
  exit 1
fi

cd "$ARTIFACTS_DIR"

echo "[INFO] Computing SHA256 checksums for all artifacts in $ARTIFACTS_DIR"

# Compute checksums for all relevant files
if command -v sha256sum &>/dev/null; then
  sha256sum ./*.tar.gz ./*.dmg 2>/dev/null > checksums.txt || sha256sum ./*.tar.gz ./*.msi 2>/dev/null > checksums.txt || true
else
  shasum -a 256 ./*.tar.gz ./*.dmg 2>/dev/null > checksums.txt || shasum -a 256 ./*.tar.gz ./*.msi 2>/dev/null > checksums.txt || true
fi

if [[ ! -s checksums.txt ]]; then
  echo "[WARN] No artifacts found to checksum" >&2
  exit 0
fi

echo "[INFO] Generated checksums.txt:"
cat checksums.txt

# Also create a JSON file with checksums for easier parsing
echo "{" > checksums.json
first=true
while IFS= read -r line; do
  checksum=$(echo "$line" | awk '{print $1}')
  filename=$(echo "$line" | awk '{print $2}' | sed 's|^\./||')
  if [ "$first" = true ]; then
    first=false
  else
    echo "," >> checksums.json
  fi
  echo "  \"$filename\": \"$checksum\"" >> checksums.json
done < checksums.txt
echo "" >> checksums.json
echo "}" >> checksums.json

echo "[INFO] Generated checksums.json:"
cat checksums.json

echo "[INFO] ✅ Checksum generation complete"
