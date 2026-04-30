#!/usr/bin/env bash

set -euo pipefail

COMMAND=${1:?COMMAND is required}

product_name_for_variant() {
  case "$1" in
    staging)
      echo "Rostoc-staging"
      ;;
    dev)
      echo "Rostoc-dev"
      ;;
    *)
      echo "Rostoc"
      ;;
  esac
}

install_aws_cli_if_missing() {
  if ! command -v aws >/dev/null 2>&1; then
    echo "Installing AWS CLI..."
    pip install --quiet awscli
  fi
}

detect_release_token() {
  if [[ -n "${UPDATES_REPO_TOKEN:-}" ]]; then
    echo "available=true" >> "$GITHUB_OUTPUT"
  else
    echo "available=false" >> "$GITHUB_OUTPUT"
    {
      echo '### ℹ️ Release asset upload skipped'
      echo "\`UPDATES_REPO_TOKEN\` not provided; skipping release artifact upload."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

locate_macos() {
  local search_dirs=() tarball="" sig_file="" cand alt_sig dir

  while IFS= read -r line; do
    search_dirs+=("$line")
  done < <(python scripts/ci/get_bundle_dirs.py macos tarball)

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    cand=$(find "$dir" -maxdepth 1 -name '*.app.tar.gz' -print -quit 2>/dev/null || true)
    if [[ -n "$cand" ]]; then
      tarball="$cand"
      break
    fi
  done

  if [[ -n "$tarball" ]]; then
    sig_file="${tarball}.sig"
    if [[ ! -f "$sig_file" ]]; then
      alt_sig=$(find "$(dirname "$tarball")" -maxdepth 1 -name "$(basename "$tarball").sig" -print -quit 2>/dev/null || true)
      if [[ -n "$alt_sig" ]]; then
        sig_file="$alt_sig"
      fi
    fi
  fi

  echo "Tarball: $tarball" >&2
  echo "Signature: $sig_file" >&2

  if [[ -z "$tarball" ]]; then
    echo 'Missing updater tarball (.app.tar.gz)'
    for dir in "${search_dirs[@]}"; do
      if [[ -d "$dir" ]]; then
        echo "[INFO] Contents of $dir:" >&2
        ls -al "$dir" >&2
      fi
    done
    exit 1
  fi
  if [[ -z "$sig_file" || ! -f "$sig_file" ]]; then
    echo 'Missing updater signature (.app.tar.gz.sig)'
    exit 1
  fi

  echo "tarball=$tarball" >> "$GITHUB_OUTPUT"
  echo "signature=$sig_file" >> "$GITHUB_OUTPUT"
}

prepare_macos() {
  local product_name search_dirs=() dmg_path="" dmg_name="" dir cand dmg_size tarball_name
  local tarball=${TARBALL:?TARBALL is required}
  local signature=${SIGNATURE:?SIGNATURE is required}
  local version=${VERSION:?VERSION is required}
  local arch=${ARCH:?ARCH is required}
  local variant=${VARIANT:-production}

  product_name=$(product_name_for_variant "$variant")

  mkdir -p "../updates/macos"

  tarball_name="${product_name}-${version}-darwin-${arch}.app.tar.gz"
  cp "$tarball" "../updates/macos/$tarball_name"
  cp "$signature" "../updates/macos/${tarball_name}.sig"
  cp "$tarball" "../updates/macos/${product_name}.app.tar.gz"
  cp "$signature" "../updates/macos/${product_name}.app.tar.gz.sig"

  while IFS= read -r line; do
    search_dirs+=("$line")
  done < <(python scripts/ci/get_bundle_dirs.py macos dmg)

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    cand=$(find "$dir" -maxdepth 1 -name '*.dmg' -print -quit 2>/dev/null || true)
    if [[ -n "$cand" && -f "$cand" ]]; then
      dmg_path="$cand"
      break
    fi
  done

  if [[ -n "$dmg_path" && -f "$dmg_path" ]]; then
    dmg_name="${product_name}_${version}_${arch}.dmg"
    dmg_size=$(du -h "$dmg_path" | cut -f1)
    echo "[INFO] Found DMG at ${dmg_path} (${dmg_size}), copying to updates as ${dmg_name}"
    echo "[INFO] Variant: ${variant}, Product name: ${product_name}"
    cp -v "$dmg_path" "../updates/macos/${dmg_name}"
    ls -lh "../updates/macos/${dmg_name}"
  else
    echo "[WARN] No DMG found in any search directory"
    for dir in "${search_dirs[@]}"; do
      if [[ -d "$dir" ]]; then
        echo "[DEBUG] Contents of $dir:" >&2
        ls -la "$dir" 2>/dev/null || true
      fi
    done
  fi

  {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
    echo "version=${version}"
    echo "git_sha=$(git rev-parse --short HEAD)"
    echo "variant=${variant}"
  } > "../updates/version.txt"

  bash ../.github/scripts/generate-checksums.sh "../updates/macos"

  {
    echo "tarball_name=$tarball_name"
    echo "dmg_name=${dmg_name}"
    echo "product_name=${product_name}"
  } >> "$GITHUB_OUTPUT"
}

upload_macos() {
  local release_prefix dmg_checksum tarball_checksum dmg_s3_url
  local version product_name tarball_name dmg_name

  install_aws_cli_if_missing

  release_prefix=${RELEASE_PREFIX:-releases}
  version=${VERSION:?VERSION is required}
  product_name=${PRODUCT_NAME:?PRODUCT_NAME is required}
  tarball_name=${TARBALL_NAME:?TARBALL_NAME is required}
  dmg_name=${DMG_NAME:-}

  echo "[INFO] Uploading macOS binaries to Spaces: ${SPACES_BUCKET}/${release_prefix}/v${version}/"
  echo "[INFO] Product name: ${product_name}"
  echo "[INFO] Tarball: ${tarball_name}"
  echo "[INFO] DMG: ${dmg_name}"

  echo "[INFO] Loading checksums from checksums.txt"
  tarball_checksum=$(grep "${tarball_name}" "../updates/macos/checksums.txt" | awk '{print $1}')
  echo "[INFO] Expected tarball checksum: ${tarball_checksum}"

  echo "[INFO] Uploading tarball..."
  aws s3 cp --endpoint-url "${SPACES_ENDPOINT}" "../updates/macos/${tarball_name}" "s3://${SPACES_BUCKET}/${release_prefix}/v${version}/${tarball_name}" --acl public-read
  aws s3 cp --endpoint-url "${SPACES_ENDPOINT}" "../updates/macos/${tarball_name}.sig" "s3://${SPACES_BUCKET}/${release_prefix}/v${version}/${tarball_name}.sig" --acl public-read

  if [[ -n "$dmg_name" && -f "../updates/macos/${dmg_name}" ]]; then
    echo "[INFO] Uploading signed, unstapled DMG for backend-managed notarization"
    echo "[INFO] CI will replace this artifact after stapling completes"

    dmg_checksum=$(grep "${dmg_name}" "../updates/macos/checksums.txt" | awk '{print $1}')
    echo "[INFO] Expected DMG checksum: ${dmg_checksum}"

    dmg_s3_url="s3://${SPACES_BUCKET}/${release_prefix}/v${version}/${dmg_name}"
    aws s3 cp --endpoint-url "${SPACES_ENDPOINT}" "../updates/macos/${dmg_name}" "${dmg_s3_url}" --acl public-read

    bash ../.github/scripts/verify-s3-upload.sh "../updates/macos/${dmg_name}" "${dmg_s3_url}" "${dmg_checksum}" "${SPACES_ENDPOINT}"
  fi

  echo "[INFO] ✅ macOS upload complete"
}

generate_windows_checksums() {
  echo "[INFO] Generating checksums for Windows MSI files"
  (cd "../updates/windows" && sha256sum ./*.msi > checksums.txt)
  echo "[INFO] Checksums generated:"
  cat "../updates/windows/checksums.txt"
}

upload_windows() {
  local release_prefix msi_checksum msi_s3_url
  local version product_name msi_name archive_name

  install_aws_cli_if_missing

  release_prefix=${RELEASE_PREFIX:-releases}
  version=${VERSION:?VERSION is required}
  product_name=${PRODUCT_NAME:?PRODUCT_NAME is required}
  msi_name=${MSI_NAME:?MSI_NAME is required}
  archive_name=${ARCHIVE_NAME:-not found}

  echo "[INFO] Uploading Windows binaries to Spaces: ${SPACES_BUCKET}/${release_prefix}/v${version}/"
  echo "[INFO] Product name: ${product_name}"
  echo "[INFO] MSI installer: ${msi_name}"
  echo "[INFO] MSI for updates: ${archive_name}"

  echo "[INFO] Loading checksums from checksums.txt"
  msi_checksum=$(grep "${msi_name}" "../updates/windows/checksums.txt" | awk '{print $1}')
  echo "[INFO] Expected MSI checksum: ${msi_checksum}"

  echo "[INFO] Uploading MSI installer..."
  msi_s3_url="s3://${SPACES_BUCKET}/${release_prefix}/v${version}/${msi_name}"
  aws s3 cp --endpoint-url "${SPACES_ENDPOINT}" "../updates/windows/${msi_name}" "${msi_s3_url}" --acl public-read

  bash ../.github/scripts/verify-s3-upload.sh "../updates/windows/${msi_name}" "${msi_s3_url}" "${msi_checksum}" "${SPACES_ENDPOINT}"

  aws s3 cp --endpoint-url "${SPACES_ENDPOINT}" "../updates/windows/${msi_name}.sig" "s3://${SPACES_BUCKET}/${release_prefix}/v${version}/${msi_name}.sig" --acl public-read

  echo "[INFO] ✅ Windows MSI and signature uploaded (MSI will be used for auto-updates)"
  echo "[INFO] Tauri v2: MSI file serves as both installer and updater archive"
  echo "Uploaded to: ${SPACES_ENDPOINT}/${SPACES_BUCKET}/${release_prefix}/v${version}/" >> "$GITHUB_STEP_SUMMARY"
}

locate_linux() {
  local search_dirs=() appimage="" dir cand appimage_size

  while IFS= read -r line; do
    search_dirs+=("$line")
  done < <(python scripts/ci/get_bundle_dirs.py linux appimage)

  echo "[DEBUG] AppImage search directories:"
  for dir in "${search_dirs[@]}"; do
    echo "  - $dir (exists=$([[ -d "$dir" ]] && echo yes || echo no))"
  done

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    echo "[DEBUG] Searching $dir:"
    find "$dir" -maxdepth 3 -type f -name '*.AppImage*' 2>/dev/null | while read -r f; do
      echo "  found: $f ($(du -h "$f" | cut -f1))"
    done
    cand=$(find "$dir" -maxdepth 3 -name '*.AppImage' ! -name '*.AppImage.*' -print -quit 2>/dev/null || true)
    if [[ -n "$cand" ]]; then
      appimage="$cand"
      break
    fi
  done

  if [[ -z "$appimage" ]]; then
    echo "[DEBUG] No AppImage found. Dumping bundle directory tree:"
    for root in target/release/bundle src-tauri/target/release/bundle; do
      if [[ -d "$root" ]]; then
        echo "[DEBUG] === $root ==="
        find "$root" -maxdepth 4 -type f 2>/dev/null | head -40
      fi
    done
    echo "::error::No AppImage artifact found in any search directory"
    exit 1
  fi

  if [[ ! -f "$appimage" ]]; then
    echo "::error::AppImage file not found: $appimage"
    exit 1
  fi

  appimage_size=$(du -h "$appimage" | cut -f1)
  echo "appimage=$appimage" >> "$GITHUB_OUTPUT"
  echo "[INFO] ✅ Located AppImage: $appimage ($appimage_size)"
}

prepare_linux() {
  local appimage=${APPIMAGE:?APPIMAGE is required}
  local version=${VERSION:?VERSION is required}
  local variant=${VARIANT:-production}
  local product_name appimage_name

  if [[ ! -f "$appimage" ]]; then
    echo "::error::AppImage missing: $appimage"
    exit 1
  fi

  product_name=$(product_name_for_variant "$variant")

  mkdir -p "../updates/linux"
  appimage_name="${product_name}-${version}-x86_64.AppImage"
  cp "$appimage" "../updates/linux/$appimage_name"
  cp "$appimage" "../updates/linux/${product_name}-x86_64.AppImage"
  (cd "../updates/linux" && sha256sum ./*.AppImage > checksums.txt)

  echo "[INFO] Linux artifacts staged: $appimage_name"
  echo "[INFO] Variant: ${variant}, Product name: ${product_name}"
  echo "appimage_name=$appimage_name" >> "$GITHUB_OUTPUT"
  echo "product_name=${product_name}" >> "$GITHUB_OUTPUT"
}

upload_linux() {
  local release_prefix
  local version product_name appimage_name

  install_aws_cli_if_missing

  release_prefix=${RELEASE_PREFIX:-releases}
  version=${VERSION:?VERSION is required}
  product_name=${PRODUCT_NAME:?PRODUCT_NAME is required}
  appimage_name=${APPIMAGE_NAME:?APPIMAGE_NAME is required}

  echo "[INFO] Uploading Linux binaries to Spaces: ${SPACES_BUCKET}/${release_prefix}/v${version}/"
  echo "[INFO] Product name: ${product_name}"
  echo "[INFO] AppImage: ${appimage_name}"

  aws s3 cp --endpoint-url "${SPACES_ENDPOINT}" "../updates/linux/${appimage_name}" "s3://${SPACES_BUCKET}/${release_prefix}/v${version}/${appimage_name}" --acl public-read

  echo "[INFO] ✅ Linux upload complete"
}

case "$COMMAND" in
  detect-release-token)
    detect_release_token
    ;;
  locate-macos)
    locate_macos
    ;;
  prepare-macos)
    prepare_macos
    ;;
  upload-macos)
    upload_macos
    ;;
  generate-windows-checksums)
    generate_windows_checksums
    ;;
  upload-windows)
    upload_windows
    ;;
  locate-linux)
    locate_linux
    ;;
  prepare-linux)
    prepare_linux
    ;;
  upload-linux)
    upload_linux
    ;;
  *)
    echo "Unknown COMMAND: $COMMAND" >&2
    exit 1
    ;;
esac