#!/usr/bin/env python3
"""CLI wrapper for STORAGE_PATHS helpers from runtime_config.

This allows shell scripts to use the centralized path generation without hardcoding.

Usage:
    python get_storage_path.py <type> <version> <filename> [channel]

Types:
    path      - Get storage path for artifact
    url       - Get CDN URL for artifact (requires SPACES_CDN_BASE env var)
    signature - Get signature path for artifact

Examples:
    python get_storage_path.py path 0.2.143 Rostoc_0.2.143_aarch64.dmg stable
    # Output: releases/v0.2.143/Rostoc_0.2.143_aarch64.dmg

    python get_storage_path.py path 0.2.143 Rostoc_0.2.143_aarch64.dmg staging
    # Output: releases/staging/v0.2.143/Rostoc_0.2.143_aarch64.dmg

    SPACES_CDN_BASE=https://cdn.example.com python get_storage_path.py url 0.2.143 file.dmg stable
    # Output: https://cdn.example.com/releases/v0.2.143/file.dmg
"""

import os
import sys
from pathlib import Path

# Add rostoc scripts to path for runtime_config import
# Try CI path first (private-src/), then local dev path (sibling repo)
SCRIPT_DIR = Path(__file__).resolve().parent
ROSTOC_SCRIPTS_CI = (
    SCRIPT_DIR.parents[1] / "private-src" / "scripts"
)  # rostoc-updates/scripts/ci -> rostoc-updates/ -> private-src/scripts
ROSTOC_SCRIPTS_LOCAL = (
    SCRIPT_DIR.parents[3] / "rostoc" / "scripts"
)  # For local development

if ROSTOC_SCRIPTS_CI.exists():
    sys.path.insert(0, str(ROSTOC_SCRIPTS_CI))
    from runtime_config import STORAGE_PATHS
elif ROSTOC_SCRIPTS_LOCAL.exists():
    sys.path.insert(0, str(ROSTOC_SCRIPTS_LOCAL))
    from runtime_config import STORAGE_PATHS
else:
    # Fallback for when running without rostoc repo
    class STORAGE_PATHS:
        CHANNEL_PREFIXES = {
            "stable": "releases",
            "staging": "releases/staging",
            "beta": "releases/beta",
            "dev": "releases/dev",
        }

        @staticmethod
        def get_storage_path(
            version: str, filename: str, channel: str = "stable"
        ) -> str:
            prefix = STORAGE_PATHS.CHANNEL_PREFIXES.get(channel, "releases")
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


def main():
    if len(sys.argv) < 4:
        print(
            "Usage: python get_storage_path.py <type> <version> <filename> [channel]",
            file=sys.stderr,
        )
        print("Types: path, url, signature", file=sys.stderr)
        sys.exit(1)

    path_type = sys.argv[1]
    version = sys.argv[2]
    filename = sys.argv[3]
    channel = sys.argv[4] if len(sys.argv) > 4 else "stable"

    try:
        if path_type == "path":
            print(STORAGE_PATHS.get_storage_path(version, filename, channel))

        elif path_type == "url":
            cdn_base = os.environ.get("SPACES_CDN_BASE", "")
            if not cdn_base:
                print(
                    "Error: SPACES_CDN_BASE environment variable not set",
                    file=sys.stderr,
                )
                sys.exit(1)
            print(STORAGE_PATHS.get_cdn_url(version, filename, cdn_base, channel))

        elif path_type == "signature":
            print(STORAGE_PATHS.get_signature_path(version, filename, channel))

        else:
            print(f"Error: Unknown type '{path_type}'", file=sys.stderr)
            print("Valid types: path, url, signature", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
