#!/usr/bin/env bash
set -euo pipefail

python scripts/ci/send_discord_webhook.py \
  --skip-missing \
  --label "build failure" \
  --content "Build failed: ${MATRIX_NAME}" \
  --title "Build Failed: ${MATRIX_NAME}" \
  --color "15158332" \
  --field "Platform=${MATRIX_PLATFORM} ${MATRIX_ARCH}" \
  --field "Variant=${MATRIX_VARIANT}" \
  --field "Version=${BUILD_VERSION:-unknown}" \
  --field "Author=${GITHUB_ACTOR}" \
  --field "Logs=[View Logs](https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID})" \
  --field "Build logs=build-logs-${MATRIX_VARIANT}-${MATRIX_PLATFORM}-${MATRIX_ARCH}-${GITHUB_RUN_NUMBER}" \
  --field "Diagnostics=diagnostics-${MATRIX_PLATFORM}-${MATRIX_ARCH}-${GITHUB_RUN_NUMBER}" \
  --field "Commit=[${GITHUB_SHA}](https://github.com/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA})" \
  --field "Branch=${GITHUB_REF_NAME}"
