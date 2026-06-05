#!/usr/bin/env python3
"""Validate Codex instruction, skill, agent, hook, and MCP assets."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11
    tomllib = None


FORBIDDEN_SKILL_DIRS = {
    ".git",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    "dist",
    "build",
}
UNSUPPORTED_SKILL_FIELDS = {
    "model",
    "argument-hint",
    "tools",
    "agents",
    "user-invocable",
    "disable-model-invocation",
    "allowed-tools",
}
UNSUPPORTED_AGENT_FIELDS = {
    "tools",
    "agents",
    "user-invocable",
    "argument-hint",
}
LEGACY_PATH_MARKERS = (
    ".github/agents",
    ".github/skills",
    ".github/prompts",
    ".github/copilot-instructions.md",
)
SECRET_KEYS = ("api_key", "apikey", "token", "secret", "password")


@dataclass
class Finding:
    repo: str
    severity: str
    path: str
    message: str


class Reporter:
    def __init__(self) -> None:
        self.findings: list[Finding] = []

    def add(self, repo: Path, severity: str, path: Path | str, message: str) -> None:
        display_path = str(path)
        if isinstance(path, Path):
            try:
                display_path = str(path.relative_to(repo))
            except ValueError:
                display_path = str(path)
        self.findings.append(Finding(repo.name, severity, display_path, message))

    def error(self, repo: Path, path: Path | str, message: str) -> None:
        self.add(repo, "error", path, message)

    def warn(self, repo: Path, path: Path | str, message: str) -> None:
        self.add(repo, "warning", path, message)


def parse_frontmatter(path: Path) -> tuple[dict[str, str], list[str], int | None]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        return {}, lines, None

    end = None
    for idx, line in enumerate(lines[1:], start=1):
        if line == "---":
            end = idx
            break
    if end is None:
        return {}, lines, None

    data: dict[str, str] = {}
    for line in lines[1:end]:
        if not line.strip() or line.startswith(" ") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    return data, lines, end


def validate_agents_md(repo: Path, reporter: Reporter) -> None:
    path = repo / "AGENTS.md"
    if not path.exists():
        reporter.error(repo, path, "missing repo-level AGENTS.md")
        return
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        reporter.error(repo, path, "AGENTS.md is empty")
    if len(text.encode("utf-8")) > 32_768:
        reporter.error(repo, path, "AGENTS.md exceeds Codex default project_doc_max_bytes")
    for marker in LEGACY_PATH_MARKERS:
        if marker in text:
            reporter.error(repo, path, f"active instructions reference legacy path {marker}")


def validate_skills(repo: Path, reporter: Reporter) -> None:
    skills_root = repo / ".agents" / "skills"
    if not skills_root.exists():
        reporter.error(repo, skills_root, "missing .agents/skills")
        return

    names: dict[str, Path] = {}
    skill_files = sorted(skills_root.glob("*/SKILL.md"))
    if not skill_files:
        reporter.warn(repo, skills_root, "no skills found")

    for forbidden in FORBIDDEN_SKILL_DIRS:
        for path in skills_root.rglob(forbidden):
            reporter.error(repo, path, f"forbidden vendored/cache directory in skill tree: {forbidden}")

    for skill_file in skill_files:
        text = skill_file.read_text(encoding="utf-8")
        data, lines, end = parse_frontmatter(skill_file)
        if not text.startswith("---\n"):
            reporter.error(repo, skill_file, "SKILL.md must start with YAML frontmatter")
        if end is None:
            reporter.error(repo, skill_file, "SKILL.md frontmatter is not closed")
            continue
        if lines and lines[0].startswith("```"):
            reporter.error(repo, skill_file, "SKILL.md is wrapped in a markdown code fence")
        if not data.get("name"):
            reporter.error(repo, skill_file, "missing skill name")
        if not data.get("description"):
            reporter.error(repo, skill_file, "missing skill description")
        name = data.get("name")
        if name:
            if name in names:
                reporter.error(repo, skill_file, f"duplicate skill name also used by {names[name]}")
            names[name] = skill_file
        for field in UNSUPPORTED_SKILL_FIELDS:
            if field in data:
                reporter.error(repo, skill_file, f"unsupported Codex skill frontmatter field: {field}")
        for marker in LEGACY_PATH_MARKERS:
            if marker in text:
                reporter.error(repo, skill_file, f"skill references legacy path {marker}")
        if len(lines) > 500:
            reporter.warn(repo, skill_file, "SKILL.md is over 500 lines; consider progressive disclosure")

    legacy_prompts = sorted((repo / ".github" / "prompts").glob("*.prompt.md"))
    for prompt_file in legacy_prompts:
        skill_name = prompt_file.name.removesuffix(".prompt.md")
        migrated = skills_root / skill_name / "SKILL.md"
        if not migrated.exists():
            reporter.error(repo, prompt_file, f"legacy prompt has no migrated skill at {migrated}")


def validate_codex_agents(repo: Path, reporter: Reporter) -> None:
    agents_root = repo / ".codex" / "agents"
    if not agents_root.exists():
        return
    for path in sorted(agents_root.glob("*.toml")):
        text = path.read_text(encoding="utf-8")
        for field in UNSUPPORTED_AGENT_FIELDS:
            if f"{field} =" in text or f"{field}:" in text:
                reporter.error(repo, path, f"unsupported Copilot agent field: {field}")
        if "(copilot)" in text.lower():
            reporter.error(repo, path, "agent contains Copilot model string")
        if tomllib is None:
            reporter.warn(repo, path, "tomllib unavailable; skipped TOML parse")
            continue
        try:
            data = tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            reporter.error(repo, path, f"invalid TOML: {exc}")
            continue
        for required in ("name", "description", "developer_instructions"):
            if not data.get(required):
                reporter.error(repo, path, f"missing required custom agent field: {required}")


def validate_codex_config(repo: Path, reporter: Reporter) -> None:
    path = repo / ".codex" / "config.toml"
    if not path.exists():
        reporter.warn(repo, path, "missing .codex/config.toml")
        return
    text = path.read_text(encoding="utf-8")
    if tomllib is not None:
        try:
            tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            reporter.error(repo, path, f"invalid TOML: {exc}")
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key = stripped.split("=", 1)[0].strip().lower()
        if any(secret in key for secret in SECRET_KEYS) and "env_var" not in key and "env_vars" not in key:
            reporter.error(repo, f"{path}:{line_no}", "possible hard-coded secret in Codex config")


def run_hook_fixture(script: Path, payload: dict[str, Any]) -> str:
    result = subprocess.run(
        [sys.executable, str(script)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return f"process-error:{result.returncode}"
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        return "invalid-json"
    hook_output = output.get("hookSpecificOutput", {})
    return str(hook_output.get("permissionDecision") or "")


def validate_hooks(repo: Path, reporter: Reporter) -> None:
    hooks_json = repo / ".codex" / "hooks.json"
    hook_script = repo / ".codex" / "hooks" / "pre_tool_guard.py"
    if not hooks_json.exists():
        reporter.error(repo, hooks_json, "missing .codex/hooks.json")
        return
    try:
        data = json.loads(hooks_json.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        reporter.error(repo, hooks_json, f"invalid JSON: {exc}")
        return
    if "hooks" not in data:
        reporter.error(repo, hooks_json, "hooks.json missing top-level hooks object")
    if "$(git rev-parse --show-toplevel)" not in hooks_json.read_text(encoding="utf-8"):
        reporter.warn(repo, hooks_json, "hook command should resolve from git root")
    if not hook_script.exists():
        reporter.error(repo, hook_script, "missing pre_tool_guard.py")
        return

    fixtures = [
        (
            "Bash destructive command",
            {"tool_name": "Bash", "tool_input": {"command": "git reset --hard HEAD"}},
            "ask",
        ),
        (
            "Bash destructive git clean compact flags",
            {"tool_name": "Bash", "tool_input": {"command": "git clean -ffdx"}},
            "ask",
        ),
        (
            "Bash destructive rm reversed flags",
            {"tool_name": "Bash", "tool_input": {"command": "rm -fr .agents"}},
            "ask",
        ),
        (
            "Bash safe command",
            {"tool_name": "Bash", "tool_input": {"command": "git status --short"}},
            "allow",
        ),
        (
            "Generated client edit",
            {
                "tool_name": "apply_patch",
                "tool_input": {"patch": "*** Update File: src/client/generated/api.ts\n"},
            },
            "deny",
        ),
        (
            "Generated dashboard client edit",
            {
                "tool_name": "apply_patch",
                "tool_input": {"patch": "*** Update File: frontend/packages/types/api/index.ts\n"},
            },
            "deny",
        ),
    ]
    for name, payload, expected in fixtures:
        actual = run_hook_fixture(hook_script, payload)
        if actual != expected:
            reporter.error(repo, hook_script, f"hook fixture failed for {name}: expected {expected}, got {actual}")


def discover_repos(start: Path, scope: str) -> list[Path]:
    repo = start.resolve()
    if scope == "repo":
        return [repo]

    candidates = [repo]
    parent = repo.parent
    if repo.name == "rostoc":
        for sibling in ("rostoc-backend", "rostoc-updates"):
            path = parent / sibling
            if path.exists():
                candidates.append(path.resolve())
    return candidates


def validate_repo(repo: Path, reporter: Reporter) -> None:
    validate_agents_md(repo, reporter)
    validate_skills(repo, reporter)
    validate_codex_agents(repo, reporter)
    validate_codex_config(repo, reporter)
    validate_hooks(repo, reporter)


def write_reports(repo: Path, findings: list[Finding], output_format: str) -> None:
    artifacts = repo / ".artifacts" / "llm"
    artifacts.mkdir(parents=True, exist_ok=True)
    counts = {
        "errors": sum(1 for finding in findings if finding.severity == "error"),
        "warnings": sum(1 for finding in findings if finding.severity == "warning"),
    }
    summary = {
        "status": "fail" if counts["errors"] else "pass",
        **counts,
        "findings": [finding.__dict__ for finding in findings],
    }
    (artifacts / "compatibility-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    lines = [
        f"status: {summary['status']}",
        f"errors: {counts['errors']}",
        f"warnings: {counts['warnings']}",
        "",
    ]
    for finding in findings:
        lines.append(f"[{finding.severity}] {finding.repo}:{finding.path}: {finding.message}")
    if not findings:
        lines.append("No Codex asset issues found.")
    (artifacts / "compatibility-summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    if output_format == "json":
        print(json.dumps(summary, indent=2))
    else:
        print("\n".join(lines))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="Repo root to validate")
    parser.add_argument("--scope", choices=("repo", "workspace"), default=os.environ.get("SCOPE", "repo"))
    parser.add_argument("--format", choices=("text", "json"), default=os.environ.get("FORMAT", "text"))
    parser.add_argument("--strict", action="store_true", default=os.environ.get("STRICT") == "1")
    args = parser.parse_args(argv)

    start = Path(args.repo)
    repos = discover_repos(start, args.scope)
    reporter = Reporter()
    for repo in repos:
        validate_repo(repo, reporter)

    if args.strict:
        for finding in list(reporter.findings):
            if finding.severity == "warning":
                reporter.findings.append(
                    Finding(finding.repo, "error", finding.path, f"strict mode escalated warning: {finding.message}")
                )

    write_reports(start.resolve(), reporter.findings, args.format)
    return 1 if any(finding.severity == "error" for finding in reporter.findings) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
