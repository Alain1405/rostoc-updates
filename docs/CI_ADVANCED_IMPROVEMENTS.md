# Advanced CI Debugging Improvements

## Current Pain Points Analysis

After implementing basic logging improvements, we still face:

1. **Long wait times** - 30-50 minutes to discover a failure
2. **No real-time visibility** - Can't see progress until job completes
3. **Context switching** - Need to manually check GitHub Actions tab
4. **Difficult log search** - GitHub UI search is limited
5. **No failure predictions** - Can't detect issues early
6. **Manual comparison** - Hard to compare failed vs successful runs

---

## High-Impact Improvements (Ranked by ROI)

### 1. Fast-Fail Early Validation (Highest Impact - 10 min implementation)

**Problem**: Build runs for 40 minutes before discovering a simple config error.

**Solution**: Add pre-flight checks that fail fast.

**Implementation** - Add to [.github/workflows/build.yml](../.github/workflows/build.yml):

```yaml
    steps:
      - name: Checkout repo (actions + workflows)
        uses: actions/checkout@v4

      # --- PRE-FLIGHT CHECKS (fail fast) ---
      - name: Pre-flight validation
        shell: bash
        run: |
          echo "🔍 Running pre-flight checks..."
          
          # Check required secrets are set (without exposing values)
          MISSING_SECRETS=()
          [[ -z "${{ secrets.APPLE_SIGNING_IDENTITY }}" ]] && MISSING_SECRETS+=("APPLE_SIGNING_IDENTITY")
          [[ -z "${{ secrets.TAURI_SIGNING_PRIVATE_KEY }}" ]] && MISSING_SECRETS+=("TAURI_SIGNING_PRIVATE_KEY")
          
          if [[ ${#MISSING_SECRETS[@]} -gt 0 ]]; then
            echo "::error::Missing required secrets: ${MISSING_SECRETS[*]}"
            exit 1
          fi
          
          # Check disk space upfront
          AVAILABLE_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
          if [[ $AVAILABLE_GB -lt 20 ]]; then
            echo "::error::Insufficient disk space: ${AVAILABLE_GB}GB available, need 20GB minimum"
            exit 1
          fi
          
          # Check workflow inputs
          if [[ "${{ inputs.is_release }}" == "true" && -z "${{ inputs.ref }}" ]]; then
            echo "::error::Release builds require 'ref' input"
            exit 1
          fi
          
          echo "✅ Pre-flight checks passed"

      # --- Phase 1: Prep (checkout, SSH, toolchains) ---
      - uses: ./.github/actions/build-prep
        # ...
```

**Benefits**:
- ✅ Fail in 30 seconds instead of 40 minutes
- ✅ Clear error messages
- ✅ Save compute costs
- ✅ Faster iteration cycle

**Estimated time saved per failed build**: 30-40 minutes

---

### 2. Real-Time Notifications (High Impact - 30 min implementation)

**Problem**: Need to manually check GitHub Actions tab; no proactive alerts.

**Solution**: Send notifications to Slack/Discord with error summaries.

**Implementation** - Add to [.github/workflows/build.yml](../.github/workflows/build.yml):

```yaml
      # --- Phase 5: Artifacts ---
      - uses: ./.github/actions/build-artifacts
        # ... existing code ...

      # --- Notify on failure ---
      - name: Notify build failure (Slack/Discord)
        if: failure()
        uses: slackapi/slack-github-action@v1.27.0
        with:
          payload: |
            {
              "text": "❌ Build Failed: ${{ matrix.name }}",
              "blocks": [
                {
                  "type": "header",
                  "text": {
                    "type": "plain_text",
                    "text": "❌ Build Failed: ${{ matrix.name }}"
                  }
                },
                {
                  "type": "section",
                  "fields": [
                    {
                      "type": "mrkdwn",
                      "text": "*Platform:* ${{ matrix.platform }}"
                    },
                    {
                      "type": "mrkdwn",
                      "text": "*Arch:* ${{ matrix.arch }}"
                    },
                    {
                      "type": "mrkdwn",
                      "text": "*Variant:* ${{ matrix.variant }}"
                    },
                    {
                      "type": "mrkdwn",
                      "text": "*Version:* ${{ steps.prep.outputs.version }}"
                    }
                  ]
                },
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Quick Links:*\n• <https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Logs>\n• Download: `build-logs-${{ matrix.variant }}-${{ matrix.platform }}-${{ matrix.arch }}-${{ github.run_number }}`\n• Download: `diagnostics-${{ matrix.platform }}-${{ matrix.arch }}-${{ github.run_number }}`"
                  }
                },
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Commit:* <https://github.com/${{ github.repository }}/commit/${{ github.sha }}|${{ github.sha }}>\n*Author:* ${{ github.actor }}\n*Branch:* ${{ github.ref_name }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

**Alternative: Discord Webhook** (simpler setup):

```yaml
      - name: Notify build failure (Discord)
        if: failure()
        uses: tsickert/discord-webhook@v6.0.0
        with:
          webhook-url: ${{ secrets.DISCORD_WEBHOOK_URL }}
          username: "CI Bot"
          avatar-url: "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png"
          embed-title: "❌ Build Failed: ${{ matrix.name }}"
          embed-description: |
            **Platform**: ${{ matrix.platform }} ${{ matrix.arch }}
            **Variant**: ${{ matrix.variant }}
            **Version**: ${{ steps.prep.outputs.version }}
            **Author**: ${{ github.actor }}
            
            [View Logs](https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }})
          embed-color: 15158332
```

**Setup**:
1. Create Slack/Discord webhook
2. Add as repository secret: `SLACK_WEBHOOK_URL` or `DISCORD_WEBHOOK_URL`
3. Done!

**Benefits**:
- ✅ Instant failure alerts
- ✅ No need to check GitHub manually
- ✅ Context in notification (platform, version, links)
- ✅ Works on mobile
- ✅ Team visibility

**Estimated time saved per failed build**: 5-10 minutes (no context switching)

---

### 3. Intelligent Caching Strategy (Medium Impact - 1 hour implementation)

**Problem**: Rebuilding dependencies from scratch wastes 10-15 minutes per build.

**Solution**: Aggressive multi-layer caching with smart invalidation.

**Implementation** - Create [.github/actions/build-cache/action.yml](../.github/actions/build-cache/action.yml):

```yaml
name: 'Intelligent Build Cache'
description: 'Multi-layer caching for Rust, Node, Python, and build artifacts'

inputs:
  platform:
    required: true
  arch:
    required: true

runs:
  using: 'composite'
  steps:
    # Layer 1: Rust dependencies (slow to rebuild)
    - name: Cache Rust dependencies
      uses: Swatinem/rust-cache@v2
      with:
        workdir: private-src/src-tauri
        key: rust-${{ inputs.platform }}-${{ inputs.arch }}
        cache-all-crates: true
        
    # Layer 2: Node modules (pnpm)
    - name: Cache pnpm store
      uses: actions/cache@v4
      with:
        path: ~/.local/share/pnpm/store
        key: pnpm-${{ runner.os }}-${{ hashFiles('private-src/pnpm-lock.yaml') }}
        restore-keys: |
          pnpm-${{ runner.os }}-
          
    # Layer 3: Python packages (uv)
    - name: Cache Python packages
      uses: actions/cache@v4
      with:
        path: |
          ~/.cache/uv
          private-src/.venv
        key: python-${{ inputs.platform }}-${{ inputs.arch }}-${{ hashFiles('private-src/pyproject.toml', 'private-src/shared-python/pyproject.toml') }}
        restore-keys: |
          python-${{ inputs.platform }}-${{ inputs.arch }}-
          
    # Layer 4: Python runtime staging (expensive to rebuild)
    - name: Cache Python runtime staging
      uses: actions/cache@v4
      with:
        path: private-src/build/runtime_staging
        key: runtime-${{ inputs.platform }}-${{ inputs.arch }}-${{ hashFiles('private-src/scripts/bundle_runtime.py', 'private-src/shared-python/**') }}
        restore-keys: |
          runtime-${{ inputs.platform }}-${{ inputs.arch }}-
          
    # Layer 5: Tauri build artifacts (incremental compilation)
    - name: Cache Tauri target directory
      uses: actions/cache@v4
      with:
        path: private-src/src-tauri/target
        key: tauri-target-${{ inputs.platform }}-${{ inputs.arch }}-${{ github.sha }}
        restore-keys: |
          tauri-target-${{ inputs.platform }}-${{ inputs.arch }}-
```

**Use in workflow**:

```yaml
      - uses: ./.github/actions/build-prep
        # ... existing prep ...

      # --- Add caching layer ---
      - uses: ./.github/actions/build-cache
        with:
          platform: ${{ matrix.platform }}
          arch: ${{ matrix.arch }}

      - uses: ./.github/actions/build-compile
        # ... existing compile ...
```

**Benefits**:
- ✅ 10-15 minute reduction in build time
- ✅ Reduced GitHub Actions compute costs
- ✅ Faster iteration on fixes
- ✅ Incremental compilation works

**Estimated time saved per build**: 10-15 minutes

---

### 4. Interactive Debug Mode (Medium Impact - 15 min setup)

**Problem**: Can't SSH into runner to debug live issues.

**Solution**: Use GitHub Actions `tmate` for interactive debugging.

**Implementation** - Add to [.github/workflows/build.yml](../.github/workflows/build.yml):

```yaml
      # --- Phase 2: Compile ---
      - uses: ./.github/actions/build-compile
        id: compile
        # ... existing inputs ...

      # --- DEBUG MODE: SSH into runner on failure ---
      - name: Setup tmate session (debug mode)
        if: failure() && contains(github.event.head_commit.message, '[debug]')
        uses: mxschmitt/action-tmate@v3
        timeout-minutes: 30
        with:
          limit-access-to-actor: true
          detached: true
```

**Usage**:
1. Commit with `[debug]` in message: `git commit -m "test: Debug build failure [debug]"`
2. Push to trigger workflow
3. When build fails, get SSH command from logs
4. SSH into runner: `ssh <tmate-command>`
5. Inspect files, re-run commands, debug interactively
6. Exit when done

**Benefits**:
- ✅ Interactive debugging
- ✅ Test fixes without re-running entire CI
- ✅ Inspect filesystem state
- ✅ Run commands manually

**Security**: `limit-access-to-actor: true` ensures only you can connect.

**Estimated time saved per complex debug session**: 1-2 hours

---

### 5. Automated Error Pattern Detection (Low Effort, High Value - 20 min)

**Problem**: Same errors happen repeatedly; no learning from past failures.

**Solution**: Build error knowledge base and suggest solutions.

**Implementation** - Create [.github/scripts/analyze-error.sh](../.github/scripts/analyze-error.sh):

```bash
#!/usr/bin/env bash
# Analyze build errors and suggest solutions based on known patterns

ERROR_LOG="${1:?Error log file required}"

# Define error patterns and solutions
declare -A ERROR_PATTERNS=(
  ["codesign.*errSecInternalComponent"]="🔐 **Keychain Access Issue**\nSolution: Unlock keychain with security unlock-keychain\nDocs: https://github.com/Alain1405/rostoc-updates/blob/main/docs/MACOS_SIGNING.md"
  
  ["LINK : fatal error LNK1120"]="🔗 **Windows Linker Error**\nSolution: Missing DLL or library dependency\nCheck: Visual Studio installation, Windows SDK version"
  
  ["UnicodeDecodeError.*cp1252"]="📝 **Windows Encoding Error**\nSolution: Add PYTHONIOENCODING=utf-8 to environment\nFixed in: #PR-123"
  
  ["No space left on device"]="💾 **Disk Space Issue**\nSolution: Clean up before build or use larger runner\nCommand: df -h && rm -rf target/"
  
  ["thread.*panicked.*unwrap.*on.*None"]="🦀 **Rust Panic (Option::unwrap)**\nSolution: Check for None values in Rust code\nLikely cause: Missing file or config"
  
  ["error\[E0277\].*trait bound"]="🦀 **Rust Trait Bound Error**\nSolution: Type doesn't implement required trait\nCheck: Generic constraints and trait implementations"
  
  ["ModuleNotFoundError.*rostoc"]="🐍 **Python Import Error**\nSolution: Virtual environment not activated or package not installed\nFix: source .venv/bin/activate && pip install -e ."
)

echo "🔍 Analyzing error log: ${ERROR_LOG}"
echo ""

FOUND_PATTERNS=()
for pattern in "${!ERROR_PATTERNS[@]}"; do
  if grep -qE "$pattern" "$ERROR_LOG" 2>/dev/null; then
    FOUND_PATTERNS+=("$pattern")
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Known Error Pattern Detected:"
    echo ""
    echo -e "${ERROR_PATTERNS[$pattern]}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
done

if [[ ${#FOUND_PATTERNS[@]} -eq 0 ]]; then
  echo "❓ No known error patterns detected"
  echo "This may be a new type of failure - consider adding it to the knowledge base"
  echo ""
  echo "Top error lines:"
  grep -iE "(error|failed|panic)" "$ERROR_LOG" | head -10
fi
```

**Use in workflow** - Add to [scripts/ci/execute_build.sh](../scripts/ci/execute_build.sh):

```bash
# Extract and highlight errors if build failed
if [[ ${BUILD_EXIT_CODE} -ne 0 ]]; then
  ERROR_LOG="errors-${PLATFORM}-${ARCH}.txt"
  {
    # ... existing error extraction ...
  } > "${ERROR_LOG}"
  
  # NEW: Analyze with knowledge base
  if [[ -f "../.github/scripts/analyze-error.sh" ]]; then
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "### 💡 Suggested Solutions" >> "$GITHUB_STEP_SUMMARY"
    bash "../.github/scripts/analyze-error.sh" "${ERROR_LOG}" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
```

**Benefits**:
- ✅ Instant solution suggestions
- ✅ Links to relevant docs
- ✅ Reduces repetitive debugging
- ✅ Knowledge base grows over time

**Estimated time saved per known error**: 10-30 minutes

---

### 6. Build Performance Dashboard (Optional - 2 hours)

**Problem**: No visibility into build time trends, bottlenecks, or regressions.

**Solution**: Generate performance metrics and visualizations.

**Implementation** - Create [.github/scripts/track-performance.sh](../.github/scripts/track-performance.sh):

```bash
#!/usr/bin/env bash
# Track build performance metrics

METRICS_FILE="build-metrics.json"
START_TIME=$(date +%s)

{
  echo "{"
  echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
  echo "  \"platform\": \"${PLATFORM}\","
  echo "  \"arch\": \"${ARCH}\","
  echo "  \"variant\": \"${ROSTOC_APP_VARIANT}\","
  echo "  \"run_id\": \"${GITHUB_RUN_NUMBER}\","
  echo "  \"commit_sha\": \"${GITHUB_SHA:0:7}\","
  echo "  \"phases\": {"
  echo "    \"checkout\": 0,"  # Will be updated by workflow
  echo "    \"dependencies\": 0,"
  echo "    \"rust_compile\": 0,"
  echo "    \"signing\": 0,"
  echo "    \"total\": 0"
  echo "  },"
  echo "  \"cache\": {"
  echo "    \"rust_hit\": false,"
  echo "    \"node_hit\": false,"
  echo "    \"python_hit\": false"
  echo "  },"
  echo "  \"artifacts\": {"
  echo "    \"dmg_size_mb\": 0,"
  echo "    \"msi_size_mb\": 0,"
  echo "    \"appimage_size_mb\": 0"
  echo "  }"
  echo "}"
} > "$METRICS_FILE"

# Upload to tracking endpoint (optional)
if [[ -n "${BUILD_METRICS_ENDPOINT:-}" ]]; then
  curl -X POST "$BUILD_METRICS_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d @"$METRICS_FILE" || true
fi
```

**Visualization**: Use GitHub Pages to display trends.

**Benefits**:
- ✅ Identify performance regressions
- ✅ Track cache hit rates
- ✅ Optimize slowest phases
- ✅ Compare across platforms

---

### 7. Log Aggregation Service (Optional - 1 hour setup)

**Problem**: GitHub Actions UI search is limited; logs expire after 90 days.

**Solutions**:

#### Option A: Datadog Logs (Recommended for scale)

```yaml
      - name: Ship logs to Datadog
        if: always()
        uses: datadog/agent-github-action@v1.3
        with:
          api_key: ${{ secrets.DATADOG_API_KEY }}
          
      # Logs automatically forwarded to Datadog
```

**Features**:
- Real-time log streaming
- Advanced search/filtering
- Custom dashboards
- Alerts on patterns
- 15-month retention

**Cost**: Free tier includes 500MB/day

#### Option B: Better Stack (formerly Logtail) - Cheaper

```yaml
      - name: Ship logs to Better Stack
        if: always()
        run: |
          curl -X POST https://in.logs.betterstack.com \
            -H "Authorization: Bearer ${{ secrets.BETTERSTACK_TOKEN }}" \
            -H "Content-Type: application/json" \
            -d @<(jq -Rs '{message: .}' build-*.log)
```

**Features**:
- Live tail
- Fast search
- Team sharing
- 1-year retention

**Cost**: Free tier includes 1GB/month

#### Option C: Self-Hosted Loki (Free but requires maintenance)

```yaml
      - name: Ship logs to Loki
        if: always()
        run: |
          cat build-*.log | promtail-client \
            --url https://loki.yourcompany.com/loki/api/v1/push \
            --tenant-id rostoc-ci
```

**Benefits of log aggregation**:
- ✅ Search across all runs
- ✅ Longer retention
- ✅ Real-time visibility
- ✅ Advanced filtering
- ✅ Alerting rules

**Recommended**: Start with Better Stack (cheapest, easiest setup).

---

## Implementation Roadmap

### Phase 1: Immediate Wins (30 minutes total)
1. ✅ Fast-fail validation (10 min)
2. ✅ Slack/Discord notifications (15 min)
3. ✅ Error pattern detection (20 min)

**Expected savings**: 30-60 min per failed build

### Phase 2: Performance (1-2 hours)
4. ✅ Intelligent caching (1 hour)
5. ✅ Debug mode setup (15 min)

**Expected savings**: 10-15 min per build + faster iteration

### Phase 3: Analytics (Optional - 2-3 hours)
6. ⏳ Performance dashboard (2 hours)
7. ⏳ Log aggregation service (1 hour)

**Expected savings**: Identify patterns, prevent regressions

---

## Cost-Benefit Analysis

| Improvement | Implementation Time | Time Saved Per Build | Payback After |
|-------------|-------------------|---------------------|---------------|
| Fast-fail validation | 10 min | 30-40 min | 1 failed build |
| Notifications | 15 min | 5-10 min | 2-3 failures |
| Error patterns | 20 min | 10-30 min | 2-3 known errors |
| Intelligent caching | 1 hour | 10-15 min | 6-8 builds |
| Debug mode | 15 min | 1-2 hours | 1 complex debug session |

**Total Phase 1 investment**: 45 minutes  
**Expected return**: 45-80 minutes saved on first failed build

---

## Monitoring Success

### Before Improvements
- Average time to identify failure: 40-50 minutes
- Average time to diagnose root cause: 20-30 minutes
- Average time to fix and verify: 60-90 minutes
- **Total**: 2-3 hours per failure

### After All Improvements
- Fast-fail catches issues: 30 seconds
- Notifications alert immediately: 0 wait time
- Error patterns suggest solution: 5 minutes to diagnose
- Debug mode fixes without re-run: 30 minutes to fix
- **Total**: 30-60 minutes per failure

**🎯 Target**: 3-4x reduction in debugging time

---

## Next Steps

1. **Implement Phase 1** (fast-fail + notifications + error patterns)
2. **Test on next failure** and measure time saved
3. **Document new patterns** in error knowledge base
4. **Implement Phase 2** (caching + debug mode)
5. **Consider Phase 3** based on ROI

---

## Alternative: All-in-One CI Solution

If you want a comprehensive solution without building it yourself:

### BuildPulse (Recommended)
- Automatic flaky test detection
- Failure pattern analysis
- Performance tracking
- GitHub integration
- **Cost**: Free for open source

### CircleCI Insights
- Advanced analytics
- Performance trends
- Failure predictions
- **Cost**: Paid plans only

### Sentry CI Monitoring (New)
- Error tracking across CI/CD
- Performance monitoring
- Release tracking
- **Cost**: Starts at $26/month

---

## Resources

- [GitHub Actions caching guide](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Datadog CI Visibility](https://docs.datadoghq.com/continuous_integration/)
- [Better Stack (Logtail)](https://betterstack.com/logs)
- [Grafana Loki](https://grafana.com/oss/loki/)
- [BuildPulse](https://buildpulse.io/)
