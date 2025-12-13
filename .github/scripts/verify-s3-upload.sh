#!/usr/bin/env bash
# Verify that a file uploaded to S3-compatible storage matches expected checksum
set -euo pipefail

FILE_PATH="${1:?Usage: $0 <file_path> <s3_url> <expected_checksum> <endpoint_url>}"
S3_URL="${2:?Missing S3 URL}"
EXPECTED_CHECKSUM="${3:?Missing expected checksum}"
ENDPOINT_URL="${4:?Missing endpoint URL}"

FILENAME=$(basename "$FILE_PATH")

echo "[INFO] Verifying upload of ${FILENAME}"
echo "[INFO] Expected checksum: ${EXPECTED_CHECKSUM}"

# Download file from S3 to temp location
TEMP_FILE="/tmp/verify_${FILENAME}_$$"
trap 'rm -f "$TEMP_FILE"' EXIT

echo "[INFO] Downloading from S3: ${S3_URL}"
aws s3 cp \
  --endpoint-url "${ENDPOINT_URL}" \
  "${S3_URL}" \
  "${TEMP_FILE}" \
  --no-progress

# Compute checksum of downloaded file
if command -v sha256sum &>/dev/null; then
  ACTUAL_CHECKSUM=$(sha256sum "${TEMP_FILE}" | awk '{print $1}')
else
  ACTUAL_CHECKSUM=$(shasum -a 256 "${TEMP_FILE}" | awk '{print $1}')
fi

echo "[INFO] Downloaded file checksum: ${ACTUAL_CHECKSUM}"

# Compare checksums
if [ "${ACTUAL_CHECKSUM}" != "${EXPECTED_CHECKSUM}" ]; then
  echo "[ERROR] ❌ Checksum mismatch!" >&2
  echo "  Expected: ${EXPECTED_CHECKSUM}" >&2
  echo "  Got:      ${ACTUAL_CHECKSUM}" >&2
  exit 1
fi

echo "[INFO] ✅ Checksum verified: ${ACTUAL_CHECKSUM}"
