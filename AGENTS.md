# AGENTS.md

## Purpose

This repository is the public workflow runner for Rostoc desktop builds. The
private `rostoc` repo dispatches CI and release events here so macOS and Windows
builds can run on public GitHub runners, publish compatibility manifests, and
keep the backend latest/download API authoritative.

Reusable workflows live in `.agents/skills/`. Project hooks live in
`.codex/hooks.json`.

## Workspace Structure

- `../rostoc/` - product code and shared scripts checked out by workflows.
- `./` - CI pipelines, workflows, release scripts, manifests, and Pages output.
- `../rostoc-backend/` - Django backend for update publishing and analytics.

## Skills

Use these Codex skills from `.agents/skills/` when relevant:

| Skill | Use |
| --- | --- |
| `rostoc-updates-linting` | Shell, YAML, actionlint, workflow path validation |
| `rostoc-updates-loki` | Grafana Loki log search and CI build log triage |
| `rostoc-updates-tmate` | Interactive CI debugging with tmate |
| `rostoc-updates-version` | Build context, GitHub SHA, and Rostoc version lookup |
| `ci-debugging` | GitHub Actions failure investigation workflow |

## Workflow Architecture

- `ci-dispatch.yml`: private repo push or PR dispatches non-release builds.
- `release-dispatch.yml`: private repo tag dispatches release builds.
- `build-and-publish.yml`: reusable workflow for platform builds, tests, and
  artifacts.
- Stapler workflows poll Apple notarization, staple accepted DMGs, update the
  compatibility manifest, and self-disable when the queue is empty.
- The Rostoc backend public latest/download API is authoritative for smoke
  checks and update consumers.

## Workflow Permissions

Dispatcher workflows must declare:

```yaml
permissions:
  contents: write
  pages: write
  id-token: write
  actions: write
```

## Validation

Run the local CI checks before committing workflow or script changes:

```bash
make format
make lint
make validate-paths
make test-env
```

Common pitfalls:

1. Missing `actions: write` for enabling or disabling workflows.
2. Querying a stale Pages URL instead of cloning the Pages branch.
3. Unquoted shell variables.
4. Relative script paths broken by `working-directory`.
5. Using `${VAR:?}` for variables that may intentionally be empty.

## LLM Asset Validation

Run this before committing Codex instruction, skill, agent, hook, or MCP changes:

```bash
make llm-validate
```
