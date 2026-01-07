#!/usr/bin/env bash
# Ship build logs to Grafana Loki line-by-line for proper display
# Usage: ship_logs_to_loki.sh <log_file> <labels_json>

set -euo pipefail

LOG_FILE="${1:?Log file path required}"
LABELS_JSON="${2:?Labels JSON required}"

# Required environment variables
LOKI_URL="${LOKI_URL:?LOKI_URL must be set}"
LOKI_USERNAME="${LOKI_USERNAME:?LOKI_USERNAME must be set}"
LOKI_PASSWORD="${LOKI_PASSWORD:?LOKI_PASSWORD must be set}"

# Configuration
MAX_BATCH_LINES="${MAX_BATCH_LINES:-1000}"
MAX_LINE_LENGTH="${MAX_LINE_LENGTH:-32000}"

# Validation
if [[ ! -f "$LOG_FILE" ]]; then
  echo "⚠️  Log file not found: $LOG_FILE" >&2
  exit 0  # Don't fail the build for missing logs
fi

# Count lines for progress tracking
TOTAL_LINES=$(wc -l < "$LOG_FILE" || echo "0")
if [[ "$TOTAL_LINES" -eq 0 ]]; then
  echo "⚠️  Log file is empty: $LOG_FILE" >&2
  exit 0
fi

echo "📤 Shipping $TOTAL_LINES log lines to Loki..."

# Helper function to send batch to Loki
send_batch() {
  local values="$1"
  local payload
  
  payload=$(cat <<EOF
{
  "streams": [
    {
      "stream": ${LABELS_JSON},
      "values": ${values}
    }
  ]
}
EOF
  )
  
  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -u "${LOKI_USERNAME}:${LOKI_PASSWORD}" \
    --data-binary "$payload" \
    "${LOKI_URL}" 2>&1) || {
    echo "❌ Loki API request failed" >&2
    return 1
  }
  
  local status_code
  status_code=$(echo "$response" | tail -n1)
  
  if [[ "$status_code" == "204" ]]; then
    return 0
  else
    echo "⚠️  Loki returned HTTP $status_code" >&2
    return 1
  fi
}

# Process log file in batches
BASE_TIMESTAMP=$(date -u +%s)000000000  # nanoseconds
BATCH_VALUES="["
LINE_COUNT=0
BATCH_COUNT=0
FIRST_IN_BATCH=true

while IFS= read -r line || [[ -n "$line" ]]; do
  # Truncate excessively long lines to prevent Loki ingestion issues
  if [[ ${#line} -gt $MAX_LINE_LENGTH ]]; then
    line="${line:0:$MAX_LINE_LENGTH}... [truncated]"
  fi
  
  # Escape line for JSON using jq
  ESCAPED_LINE=$(printf '%s' "$line" | jq -Rs .)
  
  # Add to batch
  if [[ "$FIRST_IN_BATCH" == "true" ]]; then
    FIRST_IN_BATCH=false
  else
    BATCH_VALUES+=","
  fi
  
  BATCH_VALUES+="[\"$BASE_TIMESTAMP\",$ESCAPED_LINE]"
  BASE_TIMESTAMP=$((BASE_TIMESTAMP + 1))
  LINE_COUNT=$((LINE_COUNT + 1))
  
  # Send batch when reaching limit
  if [[ $((LINE_COUNT % MAX_BATCH_LINES)) -eq 0 ]]; then
    BATCH_VALUES+="]"
    
    if send_batch "$BATCH_VALUES"; then
      BATCH_COUNT=$((BATCH_COUNT + 1))
      echo "  ✅ Batch $BATCH_COUNT ($MAX_BATCH_LINES lines) shipped"
    else
      echo "  ❌ Batch $BATCH_COUNT failed (non-fatal)"  
    fi
    
    # Reset for next batch
    BATCH_VALUES="["
    FIRST_IN_BATCH=true
  fi
done < "$LOG_FILE"

# Send remaining lines
if [[ "$FIRST_IN_BATCH" == "false" ]]; then
  BATCH_VALUES+="]"
  
  if send_batch "$BATCH_VALUES"; then
    BATCH_COUNT=$((BATCH_COUNT + 1))
    REMAINING=$((LINE_COUNT % MAX_BATCH_LINES))
    echo "  ✅ Final batch ($REMAINING lines) shipped"
  else
    echo "  ❌ Final batch failed (non-fatal)"
  fi
fi

echo "✅ Logs shipped to Loki: $BATCH_COUNT batches, $LINE_COUNT total lines"
exit 0
