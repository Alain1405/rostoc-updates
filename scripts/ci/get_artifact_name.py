#!/usr/bin/env python3
"""CLI wrapper for ARTIFACT_NAMING helpers from runtime_config.

This allows shell scripts to use the centralized naming without duplicating logic.

Usage:
    python get_artifact_name.py <type> <version> <platform> <arch>
    
Types:
    archive    - Updater archive (.app.tar.gz, .AppImage.tar.gz)
    installer  - Installer (.dmg, .msi, .AppImage)
    signature  - Signature for any artifact (.sig)

Examples:
    python get_artifact_name.py archive 0.2.143 macos aarch64
    # Output: Rostoc-0.2.143-darwin-aarch64.app.tar.gz
    
    python get_artifact_name.py installer 0.2.143 macos aarch64
    # Output: Rostoc_0.2.143_aarch64.dmg
    
    python get_artifact_name.py signature "Rostoc_0.2.143_aarch64.dmg"
    # Output: Rostoc_0.2.143_aarch64.dmg.sig
"""

import sys
from pathlib import Path

# Add rostoc scripts to path for runtime_config import
ROSTOC_SCRIPTS = Path(__file__).resolve().parents[3] / "rostoc" / "scripts"
if ROSTOC_SCRIPTS.exists():
    sys.path.insert(0, str(ROSTOC_SCRIPTS))
    from runtime_config import ARTIFACT_NAMING
else:
    # Fallback for when running without rostoc repo
    class ARTIFACT_NAMING:
        @staticmethod
        def get_updater_archive_name(version: str, platform: str, arch: str) -> str:
            if platform == "macos":
                return f"Rostoc-{version}-darwin-{arch}.app.tar.gz"
            elif platform == "linux":
                return f"Rostoc-{version}-linux-{arch}.AppImage.tar.gz"
            raise ValueError(f"Unsupported platform for updater archive: {platform}")

        @staticmethod
        def get_installer_name(version: str, platform: str, arch: str) -> str:
            if platform == "macos":
                return f"Rostoc_{version}_{arch}.dmg"
            elif platform == "windows":
                norm_arch = "x86" if arch == "i686" else "x64" if arch == "x86_64" else arch
                return f"Rostoc-{version}-windows-{norm_arch}.msi"
            elif platform == "linux":
                return f"Rostoc-{version}-linux-{arch}.AppImage"
            raise ValueError(f"Unsupported platform for installer: {platform}")

        @staticmethod
        def get_signature_name(artifact: str) -> str:
            return f"{artifact}.sig"


def main():
    if len(sys.argv) < 2:
        print("Usage: python get_artifact_name.py <type> [args...]", file=sys.stderr)
        print("Types: archive, installer, signature", file=sys.stderr)
        sys.exit(1)

    artifact_type = sys.argv[1]

    try:
        if artifact_type == "archive":
            if len(sys.argv) != 5:
                print("Usage: python get_artifact_name.py archive <version> <platform> <arch>", file=sys.stderr)
                sys.exit(1)
            version, platform, arch = sys.argv[2], sys.argv[3], sys.argv[4]
            print(ARTIFACT_NAMING.get_updater_archive_name(version, platform, arch))

        elif artifact_type == "installer":
            if len(sys.argv) != 5:
                print("Usage: python get_artifact_name.py installer <version> <platform> <arch>", file=sys.stderr)
                sys.exit(1)
            version, platform, arch = sys.argv[2], sys.argv[3], sys.argv[4]
            print(ARTIFACT_NAMING.get_installer_name(version, platform, arch))

        elif artifact_type == "signature":
            if len(sys.argv) != 3:
                print("Usage: python get_artifact_name.py signature <artifact_name>", file=sys.stderr)
                sys.exit(1)
            artifact_name = sys.argv[2]
            print(ARTIFACT_NAMING.get_signature_name(artifact_name))

        else:
            print(f"Error: Unknown type '{artifact_type}'", file=sys.stderr)
            print("Valid types: archive, installer, signature", file=sys.stderr)
            sys.exit(1)

    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
