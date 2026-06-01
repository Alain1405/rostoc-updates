#!/usr/bin/env bash

set -euo pipefail

COMMAND=${1:?usage: build_metrics.sh <command> ...}
shift

report_run_number() {
  echo "${GITHUB_RUN_NUMBER:-local}"
}

report_stem() {
  local variant platform arch
  variant=${1:?variant is required}
  platform=${2:?platform is required}
  arch=${3:?arch is required}
  echo "build-timings-${variant}-${platform}-${arch}-$(report_run_number)"
}

report_file_name() {
  local variant platform arch
  variant=${1:?variant is required}
  platform=${2:?platform is required}
  arch=${3:?arch is required}
  echo "$(report_stem "$variant" "$platform" "$arch").md"
}

report_artifact_name() {
  local variant platform arch
  variant=${1:?variant is required}
  platform=${2:?platform is required}
  arch=${3:?arch is required}
  report_stem "$variant" "$platform" "$arch"
}

report_path() {
  local report_dir variant platform arch
  report_dir=${1:?report_dir is required}
  variant=${2:?variant is required}
  platform=${3:?platform is required}
  arch=${4:?arch is required}
  echo "${report_dir}/$(report_file_name "$variant" "$platform" "$arch")"
}

escape_cell() {
  local value
  value=${1:-}
  value=${value//$'\r'/}
  value=${value//$'\n'/<br>}
  value=${value//|/\\|}
  echo "$value"
}

path_size() {
  local path
  path=${1:-}

  if [[ -z "$path" || ! -e "$path" ]]; then
    echo "n/a"
    return
  fi

  du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "n/a"
}

multi_path_size() {
  local paths line sizes
  paths=${1:-}
  sizes=()

  while IFS= read -r line; do
    if [[ -n "$line" && -e "$line" ]]; then
      sizes+=("$line: $(path_size "$line")")
    fi
  done <<< "$paths"

  if [[ ${#sizes[@]} -eq 0 ]]; then
    echo "n/a"
    return
  fi

  local joined=""
  local item
  for item in "${sizes[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+="<br>"
    fi
    joined+="$(escape_cell "$item")"
  done
  echo "$joined"
}

ensure_report() {
  local report_dir variant platform arch report_file
  report_dir=${1:?report_dir is required}
  variant=${2:?variant is required}
  platform=${3:?platform is required}
  arch=${4:?arch is required}
  report_file=$(report_path "$report_dir" "$variant" "$platform" "$arch")

  mkdir -p "$report_dir"

  if [[ ! -f "$report_file" ]]; then
    {
      echo "# Build Timings Report"
      echo
      echo "- Run number: $(report_run_number)"
      echo "- Variant: $variant"
      echo "- Platform: $platform"
      echo "- Architecture: $arch"
      echo "- Workflow: ${GITHUB_WORKFLOW:-unknown}"
      echo "- Job: ${GITHUB_JOB:-unknown}"
      echo "- Commit: ${GITHUB_SHA:-unknown}"
      echo "- Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
      echo
      echo "## Cache Signals"
      echo
      echo "| Cache | Hit | Details | Size |"
      echo "| --- | --- | --- | --- |"
      echo
      echo "## Build Compile Phase Timings"
      echo
      echo "| Step | Status | Duration (s) |"
      echo "| --- | --- | ---: |"
    } > "$report_file"
  fi

  echo "$report_file"
}

append_cache_row() {
  local report_file cache_name hit details size
  report_file=${1:?report_file is required}
  cache_name=${2:?cache_name is required}
  hit=${3:-unknown}
  details=${4:-n/a}
  size=${5:-n/a}

  printf '| %s | %s | %s | %s |\n' \
    "$(escape_cell "$cache_name")" \
    "$(escape_cell "$hit")" \
    "$(escape_cell "$details")" \
    "$(escape_cell "$size")" >> "$report_file"
}

append_timing_row() {
  local report_file step_name status duration
  report_file=${1:?report_file is required}
  step_name=${2:?step_name is required}
  status=${3:?status is required}
  duration=${4:?duration is required}

  printf '| %s | %s | %s |\n' \
    "$(escape_cell "$step_name")" \
    "$(escape_cell "$status")" \
    "$(escape_cell "$duration")" >> "$report_file"
}

init_report_command() {
  local report_dir variant platform arch
  report_dir=${1:?report_dir is required}
  variant=${2:?variant is required}
  platform=${3:?platform is required}
  arch=${4:?arch is required}

  ensure_report "$report_dir" "$variant" "$platform" "$arch" >/dev/null
}

append_cache_report_command() {
  local report_dir variant platform arch report_file rust_detail windows_detail python_paths python_detail pnpm_detail
  report_dir=${1:?report_dir is required}
  variant=${2:?variant is required}
  platform=${3:?platform is required}
  arch=${4:?arch is required}
  report_file=$(ensure_report "$report_dir" "$variant" "$platform" "$arch")

  pnpm_detail="store=${PNPM_STORE_PATH:-unknown}"
  append_cache_row \
    "$report_file" \
    "pnpm store" \
    "${PNPM_CACHE_HIT:-unknown}" \
    "$pnpm_detail" \
    "$(path_size "${PNPM_STORE_PATH:-}")"

  python_paths=$(printf '%s\n%s\n%s\n%s\n' \
    "$HOME/.cache/pip" \
    "$HOME/Library/Caches/pip" \
    "$HOME/.cache/uv" \
    "$HOME/Library/Caches/uv")
  python_detail=$(printf 'pip+uv caches on %s' "${RUNNER_OS:-unknown}")
  append_cache_row \
    "$report_file" \
    "python wheels" \
    "${PYTHON_CACHE_HIT:-unknown}" \
    "$python_detail" \
    "$(multi_path_size "$python_paths")"

  if [[ "$platform" == "windows" ]]; then
    windows_detail=$(printf 'lookup=%s<br>matched-key=%s<br>restore-key=%s<br>cargo-home=%s' \
      "${WINDOWS_CARGO_LOOKUP_HIT:-unknown}" \
      "${WINDOWS_CARGO_LOOKUP_MATCHED_KEY:-n/a}" \
      "${WINDOWS_CARGO_LOOKUP_PRIMARY_KEY:-n/a}" \
      "${WINDOWS_CARGO_HOME:-n/a}")
    append_cache_row \
      "$report_file" \
      "windows cargo" \
      "${WINDOWS_CARGO_CACHE_HIT:-unknown}" \
      "$windows_detail" \
      "$(multi_path_size "${WINDOWS_CARGO_REGISTRY:-}"$'\n'"${WINDOWS_CARGO_GIT:-}")"
  else
    rust_detail=$(printf 'target=%s' "${RUST_TARGET_DIR:-target}")
    append_cache_row \
      "$report_file" \
      "rust target" \
      "${RUST_CACHE_HIT:-unknown}" \
      "$rust_detail" \
      "$(path_size "${RUST_TARGET_DIR:-target}")"
  fi
}

run_timed_command() {
  local report_dir variant platform arch step_name report_file start_ts end_ts duration status exit_code
  report_dir=${1:?report_dir is required}
  variant=${2:?variant is required}
  platform=${3:?platform is required}
  arch=${4:?arch is required}
  step_name=${5:?step_name is required}
  shift 5

  if [[ ${1:-} != "--" ]]; then
    echo "usage: build_metrics.sh run-timed-command <report_dir> <variant> <platform> <arch> <step_name> -- <command...>" >&2
    exit 1
  fi
  shift

  report_file=$(ensure_report "$report_dir" "$variant" "$platform" "$arch")
  start_ts=${SECONDS}
  status="success"

  if "$@"; then
    end_ts=${SECONDS}
    duration=$((end_ts - start_ts))
    append_timing_row "$report_file" "$step_name" "$status" "$duration"
    return
  else
    exit_code=$?
    end_ts=${SECONDS}
    duration=$((end_ts - start_ts))
    append_timing_row "$report_file" "$step_name" "failure ($exit_code)" "$duration"
    exit "$exit_code"
  fi
}

case "$COMMAND" in
  init-report)
    init_report_command "$@"
    ;;
  append-cache-report)
    append_cache_report_command "$@"
    ;;
  run-timed-command)
    run_timed_command "$@"
    ;;
  report-artifact-name)
    report_artifact_name "$@"
    ;;
  report-file-name)
    report_file_name "$@"
    ;;
  report-path)
    report_path "$@"
    ;;
  *)
    echo "unknown command: $COMMAND" >&2
    exit 1
    ;;
esac