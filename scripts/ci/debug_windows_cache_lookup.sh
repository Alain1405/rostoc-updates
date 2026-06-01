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
cache_lookup_env_file="${CACHE_LOOKUP_ENV_FILE:-${RUNNER_TEMP:-/tmp}/windows-cargo-cache-api.env}"

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

python - "$cache_json" "$EXPECTED_KEY" "$RESTORE_PREFIX" "$cache_lookup_env_file" <<'PY'
import json
import shlex
import sys

cache_path, expected_key, restore_prefix, env_path = sys.argv[1:]

with open(cache_path, encoding="utf-8") as handle:
    payload = json.load(handle)

rows = []
exact = None
for cache in payload.get("actions_caches", []):
    key = cache.get("key", "")
    if key == expected_key:
        exact = cache
        rows.append(cache)
    elif key.startswith(restore_prefix):
        rows.append(cache)

rows.sort(
    key=lambda item: (
        item.get("key") != expected_key,
        -(item.get("last_accessed_at") is not None),
        item.get("last_accessed_at") or "",
    )
)
first_match = rows[0] if rows else None

fields = {
    "WINDOWS_CARGO_API_EXACT_VISIBLE": "true" if exact else "false",
    "WINDOWS_CARGO_API_MATCH_COUNT": str(len(rows)),
    "WINDOWS_CARGO_API_EXACT_ID": str((exact or {}).get("id", "")),
    "WINDOWS_CARGO_API_EXACT_KEY": str((exact or {}).get("key", "")),
    "WINDOWS_CARGO_API_EXACT_REF": str((exact or {}).get("ref", "")),
    "WINDOWS_CARGO_API_EXACT_VERSION": str((exact or {}).get("version", "")),
    "WINDOWS_CARGO_API_EXACT_SIZE_BYTES": str((exact or {}).get("size_in_bytes", "")),
    "WINDOWS_CARGO_API_EXACT_LAST_ACCESSED_AT": str((exact or {}).get("last_accessed_at", "")),
    "WINDOWS_CARGO_API_EXACT_CREATED_AT": str((exact or {}).get("created_at", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_ID": str((first_match or {}).get("id", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_KEY": str((first_match or {}).get("key", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_REF": str((first_match or {}).get("ref", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_VERSION": str((first_match or {}).get("version", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_SIZE_BYTES": str((first_match or {}).get("size_in_bytes", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_LAST_ACCESSED_AT": str((first_match or {}).get("last_accessed_at", "")),
    "WINDOWS_CARGO_API_FIRST_MATCH_CREATED_AT": str((first_match or {}).get("created_at", "")),
}

with open(env_path, "w", encoding="utf-8") as handle:
    for key, value in fields.items():
        handle.write(f"{key}={shlex.quote(value)}\n")
PY

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
    print("id\tkey\tref\tversion\tsize_in_bytes\tlast_accessed_at\tcreated_at")
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

echo "::group::Repository cache inventory summary"
python - "$cache_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

actions_caches = payload.get("actions_caches", [])
print(f"[INFO] total-visible-cache-entries={len(actions_caches)}")

for cache in sorted(actions_caches, key=lambda item: item.get("last_accessed_at") or "", reverse=True)[:20]:
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

echo "::group::Windows cache lookup env file"
echo "[INFO] cache-lookup-env-file=$cache_lookup_env_file"
cat "$cache_lookup_env_file"
echo "::endgroup::"