#!/usr/bin/env bash
set -euo pipefail

token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$token" ]]; then
  echo "[WARN] GH_TOKEN/GITHUB_TOKEN not set; skipping cache API inventory" >&2
  exit 0
fi

api_base="https://api.github.com/repos/${GITHUB_REPOSITORY}"
cache_json="${RUNNER_TEMP:-/tmp}/actions-caches.json"
usage_json="${RUNNER_TEMP:-/tmp}/actions-cache-usage.json"

echo "::group::Windows cache lookup inputs"
echo "[INFO] repository=${GITHUB_REPOSITORY}"
echo "[INFO] ref=${GITHUB_REF}"
echo "[INFO] expected-key=${EXPECTED_KEY}"
echo "[INFO] restore-prefix=${RESTORE_PREFIX}"
echo "[INFO] cargo-home=${WINDOWS_CARGO_HOME}"
echo "[INFO] registry=${CACHE_REGISTRY}"
echo "[INFO] git=${CACHE_GIT}"
echo "::endgroup::"

curl -fsSL \
  -H "Authorization: Bearer ${token}" \
  -H "Accept: application/vnd.github+json" \
  "${api_base}/actions/cache/usage" > "$usage_json"

curl -fsSL \
  -H "Authorization: Bearer ${token}" \
  -H "Accept: application/vnd.github+json" \
  "${api_base}/actions/caches?per_page=100" > "$cache_json"

echo "::group::Repository cache usage"
python - "$usage_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    usage = json.load(handle)

print(f"[INFO] active-caches={usage.get('active_caches_count')}")
print(f"[INFO] active-size-bytes={usage.get('active_caches_size_in_bytes')}")
PY
echo "::endgroup::"

echo "::group::Matching cache entries"
python - "$cache_json" "$EXPECTED_KEY" "$RESTORE_PREFIX" <<'PY'
import json
import sys

cache_path, expected_key, restore_prefix = sys.argv[1:]
with open(cache_path, encoding="utf-8") as handle:
    payload = json.load(handle)

rows = []
for cache in payload.get("actions_caches", []):
    key = cache.get("key", "")
    if key == expected_key or key.startswith(restore_prefix):
        rows.append(cache)

if not rows:
    print("[INFO] no matching cache entries visible through API")
else:
    for cache in rows:
        print(
            "\t".join(
                str(cache.get(field, ""))
                for field in (
                    "id",
                    "key",
                    "ref",
                    "version",
                    "size_in_bytes",
                    "last_accessed_at",
                    "created_at",
                )
            )
        )
PY
echo "::endgroup::"

echo "::group::All repository cache entries"
python - "$cache_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

for cache in payload.get("actions_caches", []):
    print(
        "\t".join(
            str(cache.get(field, ""))
            for field in (
                "id",
                "key",
                "ref",
                "version",
                "size_in_bytes",
                "last_accessed_at",
                "created_at",
            )
        )
    )
PY
echo "::endgroup::"