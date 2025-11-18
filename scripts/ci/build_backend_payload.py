#!/usr/bin/env python3
"""Build Rostoc backend publish payload from release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Dict


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


def build_asset(
    *,
    source: Path | None,
    version: str,
    platform: str,
    kind: str,
    cdn_base: str,
    signature: Path | None = None,
    mime_type: str = "",
    extra: Dict[str, Any] | None = None,
) -> Dict[str, Any] | None:
    if source is None or not source.exists():
        return None

    spaces_path = f"releases/v{version}/{source.name}"
    cdn_url = f"{cdn_base}/releases/v{version}/{source.name}" if cdn_base else ""

    asset: Dict[str, Any] = {
        "platform": platform,
        "kind": kind,
        "spaces_path": spaces_path,
        "checksum_sha256": sha256(source),
        "size_bytes": source.stat().st_size,
        "mime_type": mime_type,
    }

    extra_payload: Dict[str, Any] = dict(extra or {})
    if cdn_url:
        extra_payload.setdefault("cdn_url", cdn_url)

    if signature is not None and signature.exists():
        asset["signature_path"] = f"releases/v{version}/{signature.name}"
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
    parser.add_argument("--output", default=Path("publish-payload.json"), type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.manifest.exists():
        raise SystemExit(f"Manifest payload file missing: {args.manifest}")
    if not args.releases.exists():
        raise SystemExit(f"Releases manifest file missing: {args.releases}")

    manifest_payload = load_json(args.manifest)
    releases_data = load_json(args.releases)
    release_entry = (releases_data.get("releases") or [{}])[0]

    assets: list[Dict[str, Any]] = []

    mac_archive = find_first(args.mac_root, f"Rostoc-{args.version}-darwin-aarch64.app.tar.gz")
    mac_signature = find_first(args.mac_root, f"Rostoc-{args.version}-darwin-aarch64.app.tar.gz.sig")
    mac_dmg = find_first(args.mac_root, f"Rostoc_{args.version}_aarch64.dmg")
    win_installer = find_first(args.windows_root, f"Rostoc-{args.version}-windows-x86_64.msi")
    win_signature = find_first(args.windows_root, f"Rostoc-{args.version}-windows-x86_64.msi.sig")

    darwin_entry = (release_entry.get("platforms", {}) or {}).get("darwin-aarch64", {})
    windows_entry = (release_entry.get("platforms", {}) or {}).get("windows-x86_64", {})

    asset = build_asset(
        source=mac_archive,
        version=args.version,
        platform="macos",
        kind="archive",
        cdn_base=args.cdn_base,
        signature=mac_signature,
        mime_type="application/gzip",
        extra={"artifact": "updater"},
    )
    if asset:
        assets.append(asset)

    if mac_dmg is not None:
        installer_meta = darwin_entry.get("installer", {})
        extra = {
            "artifact": "installer",
            "notarization_status": installer_meta.get("notarization_status"),
            "submission_id": installer_meta.get("submission_id"),
        }
        dmg_asset = build_asset(
            source=mac_dmg,
            version=args.version,
            platform="macos",
            kind="installer",
            cdn_base=args.cdn_base,
            mime_type="application/x-apple-diskimage",
            extra=extra,
        )
        if dmg_asset:
            assets.append(dmg_asset)

    windows_extra = {"artifact": "installer"}
    installer_meta = windows_entry.get("installer", {})
    if installer_meta:
        windows_extra.update(installer_meta)

    win_asset = build_asset(
        source=win_installer,
        version=args.version,
        platform="windows",
        kind="installer",
        cdn_base=args.cdn_base,
        signature=win_signature,
        mime_type="application/x-msi",
        extra=windows_extra,
    )
    if win_asset:
        assets.append(win_asset)

    if not assets:
        raise SystemExit("No release assets discovered; refusing to publish empty payload")

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
