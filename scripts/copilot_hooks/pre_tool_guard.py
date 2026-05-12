import json
import sys


GENERATED_PREFIXES = (
    "src/client/generated/",
    "src/client/backend-api/",
)

DESTRUCTIVE_COMMANDS = (
    "git reset --hard",
    "git checkout --",
    "git clean -fd",
    "git clean -df",
    "git clean -xdf",
    "git clean -xfd",
    "git clean -fxd",
    "sudo rm -rf",
    "rm -rf /",
)


def collect_strings(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        result = []
        for item in value:
            result.extend(collect_strings(item))
        return result
    if isinstance(value, dict):
        result = []
        for item in value.values():
            result.extend(collect_strings(item))
        return result
    return []


def normalize_path(value):
    normalized = value.replace("\\", "/").lstrip("./")
    while normalized.startswith("../"):
        normalized = normalized[3:]
    return normalized


def is_write_tool(tool_name):
    return any(token in tool_name for token in ("edit", "create", "rename", "delete", "write", "replace")) and "read" not in tool_name


def is_terminal_tool(tool_name):
    return any(token in tool_name for token in ("terminal", "task"))


def make_response(decision, reason, *, context=None):
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }
    if context:
        payload["hookSpecificOutput"]["additionalContext"] = context
    return payload


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        json.dump(make_response("allow", "Hook input was not valid JSON"), sys.stdout)
        return

    tool_name = str(payload.get("tool_name") or "").lower()
    tool_input = payload.get("tool_input") or {}

    if is_write_tool(tool_name):
        for raw_value in collect_strings(tool_input):
            candidate = normalize_path(raw_value)
            if any(candidate.startswith(prefix) or f"/{prefix}" in candidate for prefix in GENERATED_PREFIXES):
                json.dump(
                    make_response(
                        "deny",
                        "Generated clients are read-only. Edit the source model or API and regenerate instead.",
                        context="Blocked edit target under src/client/generated or src/client/backend-api.",
                    ),
                    sys.stdout,
                )
                return

    if is_terminal_tool(tool_name):
        command = str(tool_input.get("command") or "")
        normalized_command = " ".join(command.lower().split())
        if any(pattern in normalized_command for pattern in DESTRUCTIVE_COMMANDS):
            json.dump(
                make_response(
                    "ask",
                    "Destructive shell command requires confirmation.",
                    context="This hook asks before reset, clean, checkout --, or rm -rf style commands.",
                ),
                sys.stdout,
            )
            return

    json.dump(make_response("allow", "Allowed by safety hook"), sys.stdout)


if __name__ == "__main__":
    main()