import json
import shlex
import sys


GENERATED_PREFIXES = (
    "src/client/generated/",
    "src/client/backend-api/",
    "frontend/packages/types/api/",
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
    if tool_name in {"apply_patch", "edit", "write"}:
        return True
    write_tokens = ("edit", "create", "rename", "delete", "write", "replace")
    return any(token in tool_name for token in write_tokens) and "read" not in tool_name


def is_terminal_tool(tool_name):
    terminal_tokens = ("bash", "shell", "terminal", "task", "command", "exec")
    return any(token in tool_name for token in terminal_tokens)


def command_tokens(command):
    try:
        return [token.lower() for token in shlex.split(command)]
    except ValueError:
        return command.lower().split()


def has_option(tokens, start, option):
    return option in tokens[start:]


def flag_letters(tokens, start):
    letters = set()
    for token in tokens[start:]:
        if token == "--":
            break
        if token.startswith("--"):
            continue
        if token.startswith("-"):
            letters.update(token.lstrip("-"))
    return letters


def is_destructive_command(command):
    tokens = command_tokens(command)
    for index, token in enumerate(tokens):
        if token == "git" and index + 1 < len(tokens):
            subcommand = tokens[index + 1]
            if subcommand == "reset" and has_option(tokens, index + 2, "--hard"):
                return True
            if subcommand == "checkout" and has_option(tokens, index + 2, "--"):
                return True
            if subcommand == "clean":
                flags = flag_letters(tokens, index + 2)
                if "f" in flags:
                    return True
        if token == "rm":
            flags = flag_letters(tokens, index + 1)
            if {"r", "f"}.issubset(flags):
                return True
    return False


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

    tool_name = str(payload.get("tool_name") or payload.get("toolName") or "").lower()
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}

    if is_write_tool(tool_name):
        for raw_value in collect_strings(tool_input):
            candidate = normalize_path(raw_value)
            if any(candidate.startswith(prefix) or prefix in candidate or f"/{prefix}" in candidate for prefix in GENERATED_PREFIXES):
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
        command = str(tool_input.get("command") or tool_input.get("cmd") or "")
        if is_destructive_command(command):
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
