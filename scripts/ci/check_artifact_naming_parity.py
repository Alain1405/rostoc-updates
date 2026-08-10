#!/usr/bin/env python3
"""Fail when the vendored artifact naming drifts from the canonical contract.

`build_backend_payload.py` carries a vendored copy of `ARTIFACT_NAMING` /
`STORAGE_PATHS` because CI runs this repo at `main` while the private repo is
checked out at the release ref -- importing the contract from the release ref
would let it disagree with the stager that actually names the files.

A vendored copy only stays safe while it stays identical. It did not: the
canonical module described the Linux updater archive as a Tauri v1
`.AppImage.tar.gz` and the vendored copy as a bare `.tar.gz`, while the build
emitted a signed `.AppImage`. Nothing compared the two, so every release built,
signed, and uploaded a Linux AppImage that no manifest ever referenced.

Usage:
    python3 scripts/ci/check_artifact_naming_parity.py [--canonical <path>]

Exits 0 when the two agree (or when the canonical module is unavailable, which
is not this script's failure to report), 1 on any divergence.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
PAYLOAD_SCRIPT = REPO_ROOT / "scripts" / "ci" / "build_backend_payload.py"

# Every combination the release pipeline can publish.
PLATFORM_ARCHES = [
    ("macos", "aarch64"),
    ("macos", "x86_64"),
    ("windows", "x86_64"),
    ("windows", "i686"),
    ("linux", "x86_64"),
    ("linux", "aarch64"),
]
CHANNELS = ["stable", "staging"]
PROBE_VERSION = "9.9.9"
PROBE_FILENAME = "Probe-9.9.9-artifact.bin"
PROBE_CDN_BASE = "https://cdn.invalid"


def load_vendored_naming() -> tuple[Any, Any]:
    """Load the fallback classes from build_backend_payload.py.

    The module prefers the canonical import when a sibling rostoc checkout
    exists, so force the fallback branch to read what CI actually runs.
    """
    source = PAYLOAD_SCRIPT.read_text(encoding="utf-8")
    marker = "if ROSTOC_SCRIPTS.exists():"
    if marker not in source:
        raise SystemExit(
            f"{PAYLOAD_SCRIPT}: expected import guard {marker!r} not found; "
            "update this parity check alongside the module."
        )
    namespace: dict[str, Any] = {
        "__name__": "_vendored_artifact_naming",
        "__file__": str(PAYLOAD_SCRIPT),
    }
    code = compile(source.replace(marker, "if False:"), str(PAYLOAD_SCRIPT), "exec")
    # The module announces its naming source on import; that message describes
    # the forced fallback branch, not what a release run would do.
    with contextlib.redirect_stdout(io.StringIO()):
        exec(code, namespace)  # noqa: S102 - reading our own repo's source on purpose
    return namespace["ARTIFACT_NAMING"], namespace["STORAGE_PATHS"]


def load_canonical_naming(path: Path) -> tuple[Any, Any] | None:
    runtime_config = path / "runtime_config.py"
    if not runtime_config.exists():
        return None
    spec = importlib.util.spec_from_file_location("_canonical_runtime_config", runtime_config)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.ARTIFACT_NAMING, module.STORAGE_PATHS


def call(obj: Any, method: str, *args: Any) -> str:
    """Invoke a naming method, rendering a raise as a comparable sentinel.

    The canonical module raises for a Windows updater archive while the
    vendored copy returns the MSI name; build_backend_payload.py reconciles
    that in get_updater_archive_name(), so it is an accepted difference rather
    than drift.
    """
    try:
        return str(getattr(obj, method)(*args))
    except ValueError:
        return "<ValueError>"


ACCEPTED_DIFFERENCES = {
    # (method, platform): the wrapper in build_backend_payload.py falls back to
    # the installer name for Windows when the canonical module raises.
    ("get_updater_archive_name", "windows"),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--canonical",
        type=Path,
        default=REPO_ROOT.parent / "rostoc" / "scripts",
        help="Directory containing the canonical runtime_config.py",
    )
    args = parser.parse_args()

    canonical = load_canonical_naming(args.canonical)
    if canonical is None:
        print(
            f"Canonical runtime_config.py not found under {args.canonical}; "
            "skipping artifact naming parity check."
        )
        return 0

    canon_naming, canon_paths = canonical
    vendored_naming, vendored_paths = load_vendored_naming()

    mismatches: list[str] = []

    for channel in CHANNELS:
        for platform, arch in PLATFORM_ARCHES:
            for method in ("get_updater_archive_name", "get_installer_name"):
                canon = call(canon_naming, method, PROBE_VERSION, platform, arch, channel)
                vendored = call(
                    vendored_naming, method, PROBE_VERSION, platform, arch, channel
                )
                if canon == vendored or (method, platform) in ACCEPTED_DIFFERENCES:
                    continue
                mismatches.append(
                    f"  {method}({channel}, {platform}, {arch})\n"
                    f"      canonical = {canon}\n"
                    f"      vendored  = {vendored}"
                )

        canon_sig = call(canon_naming, "get_signature_name", PROBE_FILENAME)
        vendored_sig = call(vendored_naming, "get_signature_name", PROBE_FILENAME)
        if canon_sig != vendored_sig:
            mismatches.append(
                f"  get_signature_name({PROBE_FILENAME})\n"
                f"      canonical = {canon_sig}\n"
                f"      vendored  = {vendored_sig}"
            )

        for method in ("get_storage_path", "get_signature_path"):
            canon_path = call(canon_paths, method, PROBE_VERSION, PROBE_FILENAME, channel)
            vendored_path = call(
                vendored_paths, method, PROBE_VERSION, PROBE_FILENAME, channel
            )
            if canon_path != vendored_path:
                mismatches.append(
                    f"  {method}({channel})\n"
                    f"      canonical = {canon_path}\n"
                    f"      vendored  = {vendored_path}"
                )

        canon_cdn = call(
            canon_paths, "get_cdn_url", PROBE_VERSION, PROBE_FILENAME, PROBE_CDN_BASE, channel
        )
        vendored_cdn = call(
            vendored_paths,
            "get_cdn_url",
            PROBE_VERSION,
            PROBE_FILENAME,
            PROBE_CDN_BASE,
            channel,
        )
        if canon_cdn != vendored_cdn:
            mismatches.append(
                f"  get_cdn_url({channel})\n"
                f"      canonical = {canon_cdn}\n"
                f"      vendored  = {vendored_cdn}"
            )

    if mismatches:
        print("::error::Vendored artifact naming has drifted from the canonical contract")
        print(
            f"The fallback in {PAYLOAD_SCRIPT.relative_to(REPO_ROOT)} must stay "
            f"identical to rostoc/scripts/runtime_config.py -- CI publishes with "
            f"the fallback, so drift silently drops artifacts from the manifest."
        )
        for mismatch in mismatches:
            print(mismatch)
        return 1

    print(
        f"✅ Vendored artifact naming matches {args.canonical / 'runtime_config.py'} "
        f"across {len(CHANNELS) * len(PLATFORM_ARCHES)} platform/channel combinations"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
