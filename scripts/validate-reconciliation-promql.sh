#!/usr/bin/env bash

set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 2
fi

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
METRICS_WINDOW="${METRICS_WINDOW:-5m}"
METRICS_VALIDATION_TOLERANCE_PERCENT="${METRICS_VALIDATION_TOLERANCE_PERCENT:-0.5}"
SCRAPE_INTERVAL_SECONDS="${SCRAPE_INTERVAL_SECONDS:-10}"
OUTPUT_DIR="${OUTPUT_DIR:-_bmad-output/test-artifacts/reconciliation}"

if ! [[ "$SCRAPE_INTERVAL_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SCRAPE_INTERVAL_SECONDS must be an integer." >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
json_report="$OUTPUT_DIR/reconciliation-${timestamp}.json"
txt_report="$OUTPUT_DIR/reconciliation-${timestamp}.txt"
latest_json="$OUTPUT_DIR/latest.json"
latest_txt="$OUTPUT_DIR/latest.txt"

critical_ratio="$(awk -v t="$METRICS_VALIDATION_TOLERANCE_PERCENT" 'BEGIN { printf "%.6f", 1 - (t / 100) }')"
warning_ratio="$(awk -v t="$METRICS_VALIDATION_TOLERANCE_PERCENT" 'BEGIN { printf "%.6f", 1 - ((t / 2) / 100) }')"
sustained_window="$((SCRAPE_INTERVAL_SECONDS * 2))s"

producer_expr="sum(increase(okps_producer_messages_sent_total[$METRICS_WINDOW]))"
collector_expr="sum(increase(okps_collector_messages_received_total[$METRICS_WINDOW]))"
consumer_expr="sum(increase(okps_consumer_messages_received_total[$METRICS_WINDOW]))"
collector_ratio_expr="$collector_expr / clamp_min($producer_expr, 1)"
consumer_ratio_expr="$consumer_expr / clamp_min($producer_expr, 1)"

query_scalar() {
  local query="$1"
  local result

  result="$(curl -fsS -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query")"
  echo "$result" | jq -r '.data.result[0].value[1] // "0"'
}

is_true() {
  awk -v v="$1" 'BEGIN { if (v + 0 > 0.5) print "true"; else print "false" }'
}

float_abs() {
  awk -v v="$1" 'BEGIN { if (v < 0) v = -v; printf "%.6f", v }'
}

float_sub() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.6f", a - b }'
}

float_div() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) printf "0.000000"; else printf "%.6f", a / b }'
}

float_le() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit (a <= b) ? 0 : 1 }'
}

producer_sent="$(query_scalar "$producer_expr")"
collector_received="$(query_scalar "$collector_expr")"
consumers_received="$(query_scalar "$consumer_expr")"
collector_receive_ratio="$(query_scalar "$collector_ratio_expr")"
consumer_receive_ratio="$(query_scalar "$consumer_ratio_expr")"

collector_ratio_sustained_expr="(min_over_time(($collector_ratio_expr)[$sustained_window:]) < $critical_ratio) and ($producer_expr > 0)"
consumer_ratio_sustained_expr="(min_over_time(($consumer_ratio_expr)[$sustained_window:]) < $critical_ratio) and ($producer_expr > 0)"

collector_ratio_critical_sustained="$(is_true "$(query_scalar "$collector_ratio_sustained_expr")")"
consumer_ratio_critical_sustained="$(is_true "$(query_scalar "$consumer_ratio_sustained_expr")")"

producer_collector_delta="$(float_sub "$producer_sent" "$collector_received")"
collector_consumer_delta="$(float_sub "$collector_received" "$consumers_received")"
producer_collector_relative_delta="$(float_div "$(float_abs "$producer_collector_delta")" "$producer_sent")"
collector_consumer_relative_delta="$(float_div "$(float_abs "$collector_consumer_delta")" "$collector_received")"
tolerance_ratio="$(awk -v t="$METRICS_VALIDATION_TOLERANCE_PERCENT" 'BEGIN { printf "%.6f", t / 100 }')"

gate_pass="false"
if float_le "$producer_collector_relative_delta" "$tolerance_ratio" \
  && float_le "$collector_consumer_relative_delta" "$tolerance_ratio" \
  && [[ "$producer_sent" != "0" ]] \
  && [[ "$collector_received" != "0" ]] \
  && [[ "$consumers_received" != "0" ]] \
  && [[ "$collector_ratio_critical_sustained" == "false" ]] \
  && [[ "$consumer_ratio_critical_sustained" == "false" ]]; then
  gate_pass="true"
fi

cat >"$json_report" <<EOF
{
  "generated_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prometheus_url": "${PROMETHEUS_URL}",
  "metrics_window": "${METRICS_WINDOW}",
  "scrape_interval_seconds": ${SCRAPE_INTERVAL_SECONDS},
  "sustained_window": "${sustained_window}",
  "metrics_validation_tolerance_percent": ${METRICS_VALIDATION_TOLERANCE_PERCENT},
  "thresholds": {
    "warning_ratio": ${warning_ratio},
    "critical_ratio": ${critical_ratio}
  },
  "totals": {
    "producer_sent": ${producer_sent},
    "collector_received": ${collector_received},
    "consumers_received": ${consumers_received}
  },
  "ratios": {
    "collector_receive_ratio": ${collector_receive_ratio},
    "consumer_receive_ratio": ${consumer_receive_ratio}
  },
  "deltas": {
    "producer_collector_delta": ${producer_collector_delta},
    "collector_consumer_delta": ${collector_consumer_delta},
    "producer_collector_relative_delta": ${producer_collector_relative_delta},
    "collector_consumer_relative_delta": ${collector_consumer_relative_delta}
  },
  "sustained_below_critical_ratio": {
    "collector_receive_ratio": ${collector_ratio_critical_sustained},
    "consumer_receive_ratio": ${consumer_ratio_critical_sustained}
  },
  "gate_pass": ${gate_pass}
}
EOF

cat >"$txt_report" <<EOF
OKPS Reconciliation Gate Report
Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
Prometheus URL: ${PROMETHEUS_URL}
metrics_window: ${METRICS_WINDOW}
metrics_validation_tolerance_percent: ${METRICS_VALIDATION_TOLERANCE_PERCENT}
critical_ratio_threshold: ${critical_ratio}
warning_ratio_threshold: ${warning_ratio}
sustained_window: ${sustained_window}

Totals:
  producer_sent: ${producer_sent}
  collector_received: ${collector_received}
  consumers_received: ${consumers_received}

Ratios:
  collector_receive_ratio: ${collector_receive_ratio}
  consumer_receive_ratio: ${consumer_receive_ratio}

Deltas:
  producer_collector_delta: ${producer_collector_delta}
  producer_collector_relative_delta: ${producer_collector_relative_delta}
  collector_consumer_delta: ${collector_consumer_delta}
  collector_consumer_relative_delta: ${collector_consumer_relative_delta}

Sustained below critical ratio (>1 scrape interval):
  collector_receive_ratio: ${collector_ratio_critical_sustained}
  consumer_receive_ratio: ${consumer_ratio_critical_sustained}

Gate pass: ${gate_pass}
EOF

cp "$json_report" "$latest_json"
cp "$txt_report" "$latest_txt"

echo "JSON report: $json_report"
echo "Text report: $txt_report"
echo "Gate pass: $gate_pass"

if [[ "$gate_pass" != "true" ]]; then
  exit 1
fi
