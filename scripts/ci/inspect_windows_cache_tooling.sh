#!/usr/bin/env bash

set -euo pipefail

command_path() {
  local command_name
  command_name=${1:?command name is required}

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
  else
    echo ""
  fi
}

command_version_line() {
  local command_name path
  command_name=${1:?command name is required}
  shift || true
  path=$(command_path "$command_name")

  if [[ -z "$path" ]]; then
    echo "n/a"
    return
  fi

  "$command_name" "$@" 2>&1 | head -n 1 | tr -d '\r' || echo "n/a"
}

windows_candidates() {
  local command_name output
  command_name=${1:?command name is required}

  if ! command -v where.exe >/dev/null 2>&1; then
    echo "n/a"
    return
  fi

  if ! output=$(where.exe "$command_name" 2>/dev/null); then
    echo "n/a"
    return
  fi

  printf '%s\n' "$output" | tr -d '\r' | awk 'NF { if (count++) { printf ";" } printf "%s", $0 } END { if (!count) { printf "n/a" } }'
}

tar_kind() {
  local tar_version
  tar_version=${1:-}

  case "$tar_version" in
    *"GNU tar"*)
      echo "gnu-tar"
      ;;
    *"bsdtar"*|*"libarchive"*)
      echo "bsdtar"
      ;;
    ""|"n/a")
      echo "missing"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

compression_candidate() {
  local tar_path zstd_path resolved_tar_kind
  tar_path=${1:-}
  zstd_path=${2:-}
  resolved_tar_kind=${3:-unknown}

  if [[ -z "$tar_path" ]]; then
    echo "no-tar-visible"
    return
  fi

  if [[ -n "$zstd_path" ]]; then
    echo "${resolved_tar_kind}+zstd-candidate"
    return
  fi

  echo "${resolved_tar_kind}-without-zstd"
}

tar_path_value=$(command_path tar)
tar_version_value=$(command_version_line tar --version)
tar_kind_value=$(tar_kind "$tar_version_value")
bsdtar_path_value=$(command_path bsdtar)
bsdtar_version_value=$(command_version_line bsdtar --version)
zstd_path_value=$(command_path zstd)
zstd_version_value=$(command_version_line zstd --version)

printf 'runner_os=%s\n' "${WINDOWS_CACHE_RUNNER_OS:-unknown}"
printf 'runner_arch=%s\n' "${WINDOWS_CACHE_RUNNER_ARCH:-unknown}"
printf 'msystem=%s\n' "${MSYSTEM:-unknown}"
printf 'cache_restore_action_version=%s\n' "${WINDOWS_CACHE_ACTION_RESTORE_VERSION:-unknown}"
printf 'cache_save_action_version=%s\n' "${WINDOWS_CACHE_ACTION_SAVE_VERSION:-unknown}"
printf 'tar_path=%s\n' "${tar_path_value:-n/a}"
printf 'tar_version=%s\n' "$tar_version_value"
printf 'tar_kind=%s\n' "$tar_kind_value"
printf 'tar_candidates=%s\n' "$(windows_candidates tar)"
printf 'bsdtar_path=%s\n' "${bsdtar_path_value:-n/a}"
printf 'bsdtar_version=%s\n' "$bsdtar_version_value"
printf 'bsdtar_candidates=%s\n' "$(windows_candidates bsdtar)"
printf 'zstd_path=%s\n' "${zstd_path_value:-n/a}"
printf 'zstd_version=%s\n' "$zstd_version_value"
printf 'zstd_candidates=%s\n' "$(windows_candidates zstd)"
printf 'compression_candidate=%s\n' "$(compression_candidate "${tar_path_value:-}" "${zstd_path_value:-}" "$tar_kind_value")"