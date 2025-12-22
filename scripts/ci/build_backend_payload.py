#!/usr/bin/env python3
"""Build Rostoc backend publish payload from release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Dict

# Add rostoc scripts to path for runtime_config import
ROSTOC_SCRIPTS = Path(__file__).resolve().parents[3] / "rostoc" / "scripts"
if ROSTOC_SCRIPTS.exists():
    sys.path.insert(0, str(ROSTOC_SCRIPTS))
    from runtime_config import ARTIFACT_NAMING, STORAGE_PATHS
else:
    # Fallback for when running without rostoc repo
    class ARTIFACT_NAMING:
        @staticmethod
        def get_updater_archive_name(version: str, platform: str, arch: str) -> str:
            if platform == "macos":
                return f"Rostoc-{version}-darwin-{arch}.app.tar.gz"
            return f"Rostoc-{version}-{platform}-{arch}.tar.gz"

        @staticmethod
        def get_installer_name(version: str, platform: str, arch: str) -> str:
            if platform == "macos":
                return f"Rostoc_{version}_{arch}.dmg"
            elif platform == "windows":
                norm_arch = (
                    "x64" if arch == "x86_64" else "x86" if arch == "i686" else arch
                )
                return f"Rostoc-{version}-windows-{norm_arch}.msi"
            return f"Rostoc-{version}-{platform}-{arch}.AppImage"

        @staticmethod
        def get_signature_name(artifact: str) -> str:
            return f"{artifact}.sig"

    class STORAGE_PATHS:
        @staticmethod
        def get_storage_path(
            version: str, filename: str, channel: str = "stable"
        ) -> str:
            prefix = "releases/staging" if channel == "staging" else "releases"
            return f"{prefix}/v{version}/{filename}"

        @staticmethod
        def get_cdn_url(
            version: str, filename: str, cdn_base: str, channel: str = "stable"
        ) -> str:
            if not cdn_base:
                return ""
            storage_path = STORAGE_PATHS.get_storage_path(version, filename, channel)
            return f"{cdn_base}/{storage_path}"

        @staticmethod
        def get_signature_path(
            version: str, filename: str, channel: str = "stable"
        ) -> str:
            return STORAGE_PATHS.get_storage_path(version, f"{filename}.sig", channel)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_first(root: Path, name: str) -> Path | None:
    if not root.exists():
        return None
    for candidate in root.rglob(name):
        if candidate.is_file():
            return candidate
    return None


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_checksums(root: Path) -> Dict[str, str]:
    """Load checksums from checksums.json file in the root directory."""
    checksums_file = root / "checksums.json"
    if checksums_file.exists():
        try:
            return load_json(checksums_file)
        except (json.JSONDecodeError, KeyError) as err:
            print(f"Warning: Failed to load {checksums_file}: {err}")
    return {}


def build_asset(
    *,
    source: Path | None,
    version: str,
    platform: str,
    architecture: str,
    kind: str,
    cdn_base: str,
    channel: str = "stable",
    signature: Path | None = None,
    mime_type: str = "",
    extra: Dict[str, Any] | None = None,
    stored_checksum: str | None = None,
) -> Dict[str, Any] | None:
    if source is None or not source.exists():
        return None

    # Use centralized path generation from STORAGE_PATHS
    spaces_path = STORAGE_PATHS.get_storage_path(version, source.name, channel)
    cdn_url = STORAGE_PATHS.get_cdn_url(version, source.name, cdn_base, channel)

    # Use stored checksum if available, otherwise compute it
    if stored_checksum:
        checksum = stored_checksum
        print(f"Using stored checksum for {source.name}: {checksum}")
    else:
        checksum = sha256(source)
        print(f"Computed checksum for {source.name}: {checksum}")

    asset: Dict[str, Any] = {
        "platform": platform,
        "architecture": architecture,
        "kind": kind,
        "spaces_path": spaces_path,
        "checksum_sha256": checksum,
        "size_bytes": source.stat().st_size,
        "mime_type": mime_type,
    }

    extra_payload: Dict[str, Any] = dict(extra or {})
    if cdn_url:
        extra_payload.setdefault("cdn_url", cdn_url)

    if signature is not None and signature.exists():
        asset["signature_path"] = STORAGE_PATHS.get_signature_path(
            version, source.name, channel
        )
        sig_text = signature.read_text(encoding="utf-8").strip()
        if sig_text:
            extra_payload.setdefault("signature_ed25519", sig_text)

    if extra_payload:
        asset["extra"] = extra_payload

    return asset


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--channel", default="stable")
    parser.add_argument("--build-sha", required=True)
    parser.add_argument("--cdn-base", default="")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--releases", required=True, type=Path)
    parser.add_argument("--mac-root", default=Path("macos-artifacts"), type=Path)
    parser.add_argument("--windows-root", default=Path("windows-artifacts"), type=Path)
    parser.add_argument("--linux-root", default=Path("linux-artifacts"), type=Path)
    parser.add_argument("--output", default=Path("publish-payload.json"), type=Path)
    return parser.parse_args()


def get_arch_mapping(platform: str, build_arch: str) -> str:
    """Map build architecture to backend architecture naming."""
    if platform == "macos":
        return "arm64" if build_arch == "aarch64" else "x64"
    elif platform == "windows":
        return "x64" if build_arch == "x86_64" else "x86"
    elif platform == "linux":
        return "arm64" if build_arch == "aarch64" else "x64"
    return build_arch


def get_mime_type(platform: str, kind: str) -> str:
    """Get MIME type for artifact based on platform and kind."""
    if kind == "archive":
        return "application/gzip"

    if platform == "macos":
        return "application/x-apple-diskimage"
    elif platform == "windows":
        return "application/x-msi"
    elif platform == "linux":
        return "application/x-executable"
    return "application/octet-stream"


def process_platform_artifacts(
    *,
    platform: str,
    arch: str,
    version: str,
    channel: str,
    artifact_root: Path,
    checksums: Dict[str, str],
    cdn_base: str,
    release_entry: Dict[str, Any],
) -> list[Dict[str, Any]]:
    """Process all artifacts for a given platform/architecture combination."""
    assets: list[Dict[str, Any]] = []
    backend_arch = get_arch_mapping(platform, arch)

    # Platform key in releases.json (e.g., "darwin-aarch64", "windows-x86_64")
    if platform == "macos":
        platform_key = f"darwin-{arch}"
    else:
        platform_key = f"{platform}-{arch}"

    platform_entry = (release_entry.get("platforms", {}) or {}).get(platform_key, {})

    print(f"\n=== Processing {platform} {arch} ===")

    # Process updater archive (if exists)
    archive_name = ARTIFACT_NAMING.get_updater_archive_name(version, platform, arch)
    archive_path = find_first(artifact_root, archive_name)
    archive_sig = find_first(
        artifact_root, ARTIFACT_NAMING.get_signature_name(archive_name)
    )

    if archive_path:
        print(f"Found updater archive: {archive_name}")
        asset = build_asset(
            source=archive_path,
            version=version,
            platform=platform,
            architecture=backend_arch,
            kind="archive",
            cdn_base=cdn_base,
            channel=channel,
            signature=archive_sig,
            mime_type=get_mime_type(platform, "archive"),
            extra={"artifact": "updater"},
            stored_checksum=checksums.get(archive_name),
        )
        if asset:
            assets.append(asset)

    # Process installer (if exists)
    installer_name = ARTIFACT_NAMING.get_installer_name(version, platform, arch)
    installer_path = find_first(artifact_root, installer_name)
    installer_sig = find_first(
        artifact_root, ARTIFACT_NAMING.get_signature_name(installer_name)
    )

    if installer_path:
        print(f"Found installer: {installer_name}")
        installer_meta = platform_entry.get("installer", {})

        extra = {"artifact": "installer"}
        # Include notarization metadata for macOS
        if platform == "macos" and installer_meta:
            if "notarization_status" in installer_meta:
                extra["notarization_status"] = installer_meta["notarization_status"]
            if "submission_id" in installer_meta:
                extra["submission_id"] = installer_meta["submission_id"]

        asset = build_asset(
            source=installer_path,
            version=version,
            platform=platform,
            architecture=backend_arch,
            kind="installer",
            cdn_base=cdn_base,
            channel=channel,
            signature=installer_sig,
            mime_type=get_mime_type(platform, "installer"),
            extra=extra,
            stored_checksum=checksums.get(installer_name),
        )
        if asset:
            assets.append(asset)

    return assets


def main() -> None:
    args = parse_args()

    if not args.manifest.exists():
        raise SystemExit(f"Manifest payload file missing: {args.manifest}")
    if not args.releases.exists():
        raise SystemExit(f"Releases manifest file missing: {args.releases}")

    manifest_payload = load_json(args.manifest)
    releases_data = load_json(args.releases)
    release_entry = (releases_data.get("releases") or [{}])[0]

    # Load stored checksums from all artifact roots
    mac_checksums = load_checksums(args.mac_root)
    windows_checksums = load_checksums(args.windows_root)
    linux_checksums = load_checksums(args.linux_root)

    print(f"Loaded {len(mac_checksums)} macOS checksums")
    print(f"Loaded {len(windows_checksums)} Windows checksums")
    print(f"Loaded {len(linux_checksums)} Linux checksums")

    assets: list[Dict[str, Any]] = []

    # Define all possible platform/architecture combinations to check
    # These match the build matrix in the CI workflow
    platform_configs = [
        # macOS builds
        ("macos", "aarch64", args.mac_root, mac_checksums),
        ("macos", "x86_64", args.mac_root, mac_checksums),
        # Windows builds
        ("windows", "x86_64", args.windows_root, windows_checksums),
        ("windows", "i686", args.windows_root, windows_checksums),
        # Linux builds
        ("linux", "x86_64", args.linux_root, linux_checksums),
        ("linux", "aarch64", args.linux_root, linux_checksums),
        # Note: You'll need to add --linux-root argument if Linux builds are included
    ]

    # Process each platform/architecture combination
    for platform, arch, artifact_root, checksums in platform_configs:
        if not artifact_root.exists():
            print(
                f"Skipping {platform} {arch}: artifact root {artifact_root} not found"
            )
            continue

        platform_assets = process_platform_artifacts(
            platform=platform,
            arch=arch,
            version=args.version,
            channel=args.channel,
            artifact_root=artifact_root,
            checksums=checksums,
            cdn_base=args.cdn_base,
            release_entry=release_entry,
        )
        assets.extend(platform_assets)

    # Allow publishing without Linux (optional platform)
    # Require at least one macOS or Windows asset
    has_required_platform = any(
        asset["platform"] in ["macos", "windows"] for asset in assets
    )

    if not assets:
        raise SystemExit(
            "No release assets discovered; refusing to publish empty payload"
        )

    if not has_required_platform:
        print("Warning: No macOS or Windows assets found (required platforms)")
        raise SystemExit(
            "No assets from required platforms (macOS, Windows); refusing to publish"
        )

    payload = {
        "channel": args.channel or "stable",
        "version": args.version,
        "status": "live",
        "build_sha": args.build_sha,
        "manifest_payload": manifest_payload,
        "metadata": {
            "releases_entry": release_entry,
        },
        "assets": assets,
    }

    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote backend payload with {len(assets)} asset(s) -> {args.output}")


if __name__ == "__main__":
    main()
