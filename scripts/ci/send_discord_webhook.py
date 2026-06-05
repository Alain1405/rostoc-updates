#!/usr/bin/env python3
"""Send a Discord webhook message for CI notifications."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any


def parse_field(value: str) -> dict[str, Any]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("fields must use NAME=VALUE")

    name, field_value = value.split("=", 1)
    name = name.strip()
    field_value = field_value.strip()
    if not name:
        raise argparse.ArgumentTypeError("field name cannot be empty")

    return {
        "name": name,
        "value": field_value or "n/a",
        "inline": True,
    }


def parse_color(value: str) -> int:
    try:
        return int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("color must be an integer") from exc


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    if args.content:
        payload["content"] = args.content
    if args.username:
        payload["username"] = args.username
    if args.avatar_url:
        payload["avatar_url"] = args.avatar_url

    embed: dict[str, Any] = {}
    if args.title:
        embed["title"] = args.title
    if args.description:
        embed["description"] = args.description
    if args.color is not None:
        embed["color"] = args.color
    if args.field:
        embed["fields"] = args.field

    if embed:
        payload["embeds"] = [embed]

    if not payload:
        raise ValueError("Discord payload must include content or embed data")

    return payload


def post_payload(webhook_url: str, payload: dict[str, Any], timeout_seconds: float) -> None:
    request = urllib.request.Request(
        webhook_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "rostoc-ci",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        response.read()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--webhook-url-env", default="DISCORD_WEBHOOK_URL")
    parser.add_argument("--skip-missing", action="store_true")
    parser.add_argument("--label", default="Discord notification")
    parser.add_argument("--content")
    parser.add_argument("--title")
    parser.add_argument("--description")
    parser.add_argument("--color", type=parse_color)
    parser.add_argument("--field", action="append", type=parse_field)
    parser.add_argument("--username", default="Rostoc CI")
    parser.add_argument("--avatar-url")
    parser.add_argument("--timeout-seconds", type=float, default=10.0)
    args = parser.parse_args()

    webhook_url = os.environ.get(args.webhook_url_env, "").strip()
    if not webhook_url:
        message = f"{args.webhook_url_env} is not set; skipping {args.label}"
        if args.skip_missing:
            print(f"[WARN] {message}")
            return 0
        print(f"[ERROR] {message}", file=sys.stderr)
        return 1

    try:
        payload = build_payload(args)
        post_payload(webhook_url, payload, args.timeout_seconds)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        print(
            f"[ERROR] Discord webhook failed with HTTP {exc.code}: {detail}",
            file=sys.stderr,
        )
        return 1
    except (OSError, ValueError) as exc:
        print(f"[ERROR] Discord webhook failed: {exc}", file=sys.stderr)
        return 1

    print(f"[INFO] Sent {args.label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
