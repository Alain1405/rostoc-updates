---
name: rostoc-updates-loki
description: Grafana Loki log aggregation for Rostoc CI builds. Use when searching CI build logs, debugging failed builds by run ID, filtering logs by platform/status/variant, or accessing centralized log monitoring.
---

# Grafana Loki Log Aggregation

All CI builds automatically ship logs to Grafana Cloud for centralized search and analysis.

## Grafana Cloud Access

| Resource | URL |
|----------|-----|
| Stack | https://rostocci.grafana.net/ |
| **Explore (Recommended)** | https://rostocci.grafana.net/explore |
| Logs App | https://rostocci.grafana.net/a/grafana-lokiexplore-app/explore |
| Datasource | `grafanacloud-logs` (pre-configured) |
| Retention | 14 days |

**Use Explore view** for line-by-line log viewing. Update query: `{run_id="YOUR_RUN_ID"}`

## Required Secrets

| Secret | Value |
|--------|-------|
| `LOKI_URL` | `https://logs-prod-032.grafana.net/loki/api/v1/push` |
| `LOKI_USERNAME` | `1445820` |
| `LOKI_PASSWORD` | API token via Access Policies → Create Access Policy → Loki write scope |

## Log Labels

All logs include these labels for filtering:

| Label | Description |
|-------|-------------|
| `run_id` | GitHub Actions run ID |
| `run_number` | Sequential run number |
| `platform` | macos, windows, linux |
| `arch` | aarch64, x86_64, i686 |
| `variant` | production, staging |
| `status` | success, failure |
| `job` | build, publish, etc. |
| `actor` | GitHub username |
| `branch` | Branch name |
| `commit` | Full commit SHA |
| `version` | Build version |

## Common Queries

```logql
# Search by platform
{platform="macos"}

# Search by failure status
{status="failure"}

# Combine multiple labels
{platform="windows", variant="staging", status="failure"}

# Search by commit or run
{commit="abc123"}
{run_id="12345"}

# Full-text search within logs
{platform="macos"} |= "error" |= "codesign"

# All failed builds
{job="build", status="failure"}

# macOS failures only
{platform="macos", status="failure"}

# Staging variant issues
{variant="staging"}

# Pattern match errors
{job="build"} |~ "(error|failed|panic)"
```

## Workflow Integration

- Logs ship via direct Loki Push API
- Runs with `if: always()` - ships on success AND failure
- Uses `continue-on-error: true` to not break builds if Loki is down
- Source file: `build-<platform>-<arch>.log` from execute_build.sh
- Authentication via HTTP Basic Auth (username:password)

## Quick Access Links

**Specific run:**
```
https://rostocci.grafana.net/explore?...&panes={"lsb":{"queries":[{"expr":"{run_id=\"YOUR_RUN_ID\"}"}]}}
```

Replace `YOUR_RUN_ID` with the actual GitHub Actions run ID.
