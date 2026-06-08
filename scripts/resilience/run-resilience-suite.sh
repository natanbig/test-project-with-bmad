#!/usr/bin/env bash

set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required." >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 2
fi

NAMESPACE="${NAMESPACE:-okps}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
METRICS_WINDOW="${METRICS_WINDOW:-2m}"
RECOVERY_TIMEOUT_SECONDS="${RECOVERY_TIMEOUT_SECONDS:-300}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-10}"
METRICS_VALIDATION_TOLERANCE_PERCENT="${METRICS_VALIDATION_TOLERANCE_PERCENT:-0.5}"
CONSUMER_DOWNTIME_SECONDS="${CONSUMER_DOWNTIME_SECONDS:-30}"
NETWORK_INTERRUPTION_SECONDS="${NETWORK_INTERRUPTION_SECONDS:-30}"
OUTPUT_DIR="${OUTPUT_DIR:-_bmad-output/test-artifacts/resilience}"
SCENARIO="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--scenario all|collector-restart|consumer-rebound|network-interruption]

Environment overrides:
  NAMESPACE
  PROMETHEUS_URL
  METRICS_WINDOW
  RECOVERY_TIMEOUT_SECONDS
  POLL_INTERVAL_SECONDS
  METRICS_VALIDATION_TOLERANCE_PERCENT
  CONSUMER_DOWNTIME_SECONDS
  NETWORK_INTERRUPTION_SECONDS
  OUTPUT_DIR
EOF
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! [[ "$RECOVERY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: RECOVERY_TIMEOUT_SECONDS must be an integer." >&2
  exit 2
fi

if ! [[ "$POLL_INTERVAL_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: POLL_INTERVAL_SECONDS must be an integer." >&2
  exit 2
fi

if ! [[ "$CONSUMER_DOWNTIME_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: CONSUMER_DOWNTIME_SECONDS must be an integer." >&2
  exit 2
fi

if ! [[ "$NETWORK_INTERRUPTION_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: NETWORK_INTERRUPTION_SECONDS must be an integer." >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
json_report="$OUTPUT_DIR/resilience-${timestamp}.json"
txt_report="$OUTPUT_DIR/resilience-${timestamp}.txt"
latest_json="$OUTPUT_DIR/latest.json"
latest_txt="$OUTPUT_DIR/latest.txt"

tolerance_ratio="$(awk -v t="$METRICS_VALIDATION_TOLERANCE_PERCENT" 'BEGIN { printf "%.6f", t / 100 }')"

consumer_policy_removed="false"

cleanup() {
  if [[ "$consumer_policy_removed" == "true" ]]; then
    kubectl apply -f deploy/k8s/networkpolicy.yaml >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

query_scalar() {
  local query="$1"
  local result

  result="$(curl -fsS -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query")"
  echo "$result" | jq -r '.data.result[0].value[1] // "0"'
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

sample_metrics() {
  local producer_expr="sum(increase(okps_producer_messages_sent_total[$METRICS_WINDOW]))"
  local collector_expr="sum(increase(okps_collector_messages_received_total[$METRICS_WINDOW]))"
  local consumer_expr="sum(increase(okps_consumer_messages_received_total[$METRICS_WINDOW]))"

  local producer_sent
  local collector_received
  local consumers_received
  local producer_collector_delta
  local collector_consumer_delta
  local producer_collector_relative_delta
  local collector_consumer_relative_delta
  local collector_receive_ratio
  local consumer_receive_ratio

  producer_sent="$(query_scalar "$producer_expr")"
  collector_received="$(query_scalar "$collector_expr")"
  consumers_received="$(query_scalar "$consumer_expr")"

  producer_collector_delta="$(float_sub "$producer_sent" "$collector_received")"
  collector_consumer_delta="$(float_sub "$collector_received" "$consumers_received")"
  producer_collector_relative_delta="$(float_div "$(float_abs "$producer_collector_delta")" "$producer_sent")"
  collector_consumer_relative_delta="$(float_div "$(float_abs "$collector_consumer_delta")" "$collector_received")"
  collector_receive_ratio="$(float_div "$collector_received" "$producer_sent")"
  consumer_receive_ratio="$(float_div "$consumers_received" "$producer_sent")"

  jq -n \
    --arg producer_sent "$producer_sent" \
    --arg collector_received "$collector_received" \
    --arg consumers_received "$consumers_received" \
    --arg producer_collector_delta "$producer_collector_delta" \
    --arg collector_consumer_delta "$collector_consumer_delta" \
    --arg producer_collector_relative_delta "$producer_collector_relative_delta" \
    --arg collector_consumer_relative_delta "$collector_consumer_relative_delta" \
    --arg collector_receive_ratio "$collector_receive_ratio" \
    --arg consumer_receive_ratio "$consumer_receive_ratio" \
    '{
      producer_sent: ($producer_sent | tonumber),
      collector_received: ($collector_received | tonumber),
      consumers_received: ($consumers_received | tonumber),
      producer_collector_delta: ($producer_collector_delta | tonumber),
      collector_consumer_delta: ($collector_consumer_delta | tonumber),
      producer_collector_relative_delta: ($producer_collector_relative_delta | tonumber),
      collector_consumer_relative_delta: ($collector_consumer_relative_delta | tonumber),
      collector_receive_ratio: ($collector_receive_ratio | tonumber),
      consumer_receive_ratio: ($consumer_receive_ratio | tonumber)
    }'
}

is_recovered_from_sample() {
  local sample_json="$1"
  local producer_sent
  local producer_collector_relative_delta
  local collector_consumer_relative_delta

  producer_sent="$(echo "$sample_json" | jq -r '.producer_sent')"
  producer_collector_relative_delta="$(echo "$sample_json" | jq -r '.producer_collector_relative_delta')"
  collector_consumer_relative_delta="$(echo "$sample_json" | jq -r '.collector_consumer_relative_delta')"

  if [[ "$producer_sent" == "0" ]]; then
    return 1
  fi

  if float_le "$producer_collector_relative_delta" "$tolerance_ratio" \
    && float_le "$collector_consumer_relative_delta" "$tolerance_ratio"; then
    return 0
  fi

  return 1
}

wait_for_recovery() {
  local scenario_name="$1"
  local start_epoch
  local now_epoch
  local elapsed
  local sample_json
  local recovered="false"
  local recovery_seconds="-1"
  local last_sample='{}'
  local max_pc_rel_delta="0.000000"
  local max_cc_rel_delta="0.000000"

  start_epoch="$(date +%s)"

  while true; do
    now_epoch="$(date +%s)"
    elapsed="$((now_epoch - start_epoch))"

    if (( elapsed > RECOVERY_TIMEOUT_SECONDS )); then
      break
    fi

    sample_json="$(sample_metrics)"
    last_sample="$sample_json"

    pc_rel="$(echo "$sample_json" | jq -r '.producer_collector_relative_delta')"
    cc_rel="$(echo "$sample_json" | jq -r '.collector_consumer_relative_delta')"

    max_pc_rel_delta="$(awk -v a="$max_pc_rel_delta" -v b="$pc_rel" 'BEGIN { if (b > a) printf "%.6f", b; else printf "%.6f", a }')"
    max_cc_rel_delta="$(awk -v a="$max_cc_rel_delta" -v b="$cc_rel" 'BEGIN { if (b > a) printf "%.6f", b; else printf "%.6f", a }')"

    if is_recovered_from_sample "$sample_json"; then
      recovered="true"
      recovery_seconds="$elapsed"
      break
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  jq -n \
    --arg scenario "$scenario_name" \
    --arg recovered "$recovered" \
    --argjson recovery_seconds "$recovery_seconds" \
    --arg max_pc_rel_delta "$max_pc_rel_delta" \
    --arg max_cc_rel_delta "$max_cc_rel_delta" \
    --arg tolerance_ratio "$tolerance_ratio" \
    --argjson last_sample "$last_sample" \
    '{
      scenario: $scenario,
      recovered: ($recovered == "true"),
      recovery_seconds: $recovery_seconds,
      tolerance_ratio: ($tolerance_ratio | tonumber),
      max_relative_deltas: {
        producer_collector: ($max_pc_rel_delta | tonumber),
        collector_consumer: ($max_cc_rel_delta | tonumber)
      },
      final_sample: $last_sample
    }'
}

ensure_traffic_present() {
  local sample_json
  local producer_sent

  sample_json="$(sample_metrics)"
  producer_sent="$(echo "$sample_json" | jq -r '.producer_sent')"

  if [[ "$producer_sent" == "0" ]]; then
    echo "ERROR: No producer traffic observed over metrics window '$METRICS_WINDOW'." >&2
    echo "Hint: ensure producer pods are running and sending traffic before resilience tests." >&2
    exit 1
  fi
}

run_collector_restart() {
  local start_utc
  local end_utc
  local pre_sample
  local post_sample
  local recovery

  echo "Running scenario: collector-restart"
  pre_sample="$(sample_metrics)"
  start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  kubectl -n "$NAMESPACE" rollout restart deploy/okps-collector
  kubectl -n "$NAMESPACE" rollout status deploy/okps-collector --timeout=300s

  end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  recovery="$(wait_for_recovery "collector-restart")"
  post_sample="$(sample_metrics)"

  jq -n \
    --arg start_utc "$start_utc" \
    --arg end_utc "$end_utc" \
    --argjson pre_sample "$pre_sample" \
    --argjson post_sample "$post_sample" \
    --argjson recovery "$recovery" \
    '{
      scenario: "collector-restart",
      fault_window_utc: { start: $start_utc, end: $end_utc },
      pre_fault_sample: $pre_sample,
      recovery: $recovery,
      post_recovery_sample: $post_sample,
      pass: ($recovery.recovered == true)
    }'
}

run_consumer_rebound() {
  local start_utc
  local end_utc
  local pre_sample
  local post_sample
  local recovery
  local original_replicas

  echo "Running scenario: consumer-rebound"
  pre_sample="$(sample_metrics)"
  original_replicas="$(kubectl -n "$NAMESPACE" get deploy/okps-consumer -o jsonpath='{.spec.replicas}')"
  start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  kubectl -n "$NAMESPACE" scale deploy/okps-consumer --replicas=0
  kubectl -n "$NAMESPACE" rollout status deploy/okps-consumer --timeout=300s

  sleep "$CONSUMER_DOWNTIME_SECONDS"

  kubectl -n "$NAMESPACE" scale deploy/okps-consumer --replicas="$original_replicas"
  kubectl -n "$NAMESPACE" rollout status deploy/okps-consumer --timeout=300s

  end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  recovery="$(wait_for_recovery "consumer-rebound")"
  post_sample="$(sample_metrics)"

  jq -n \
    --arg start_utc "$start_utc" \
    --arg end_utc "$end_utc" \
    --arg original_replicas "$original_replicas" \
    --argjson pre_sample "$pre_sample" \
    --argjson post_sample "$post_sample" \
    --argjson recovery "$recovery" \
    '{
      scenario: "consumer-rebound",
      original_replicas: ($original_replicas | tonumber),
      fault_window_utc: { start: $start_utc, end: $end_utc },
      pre_fault_sample: $pre_sample,
      recovery: $recovery,
      post_recovery_sample: $post_sample,
      pass: ($recovery.recovered == true)
    }'
}

run_network_interruption() {
  local start_utc
  local end_utc
  local pre_sample
  local post_sample
  local recovery

  echo "Running scenario: network-interruption"
  pre_sample="$(sample_metrics)"
  start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  kubectl -n "$NAMESPACE" delete networkpolicy okps-consumer-traffic --ignore-not-found
  consumer_policy_removed="true"

  sleep "$NETWORK_INTERRUPTION_SECONDS"

  kubectl apply -f deploy/k8s/networkpolicy.yaml >/dev/null
  consumer_policy_removed="false"

  end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  recovery="$(wait_for_recovery "network-interruption")"
  post_sample="$(sample_metrics)"

  jq -n \
    --arg start_utc "$start_utc" \
    --arg end_utc "$end_utc" \
    --argjson pre_sample "$pre_sample" \
    --argjson post_sample "$post_sample" \
    --argjson recovery "$recovery" \
    '{
      scenario: "network-interruption",
      fault_window_utc: { start: $start_utc, end: $end_utc },
      pre_fault_sample: $pre_sample,
      recovery: $recovery,
      post_recovery_sample: $post_sample,
      pass: ($recovery.recovered == true)
    }'
}

run_one() {
  local scenario_name="$1"
  case "$scenario_name" in
    collector-restart)
      run_collector_restart
      ;;
    consumer-rebound)
      run_consumer_rebound
      ;;
    network-interruption)
      run_network_interruption
      ;;
    *)
      echo "ERROR: unknown scenario '$scenario_name'" >&2
      exit 2
      ;;
  esac
}

ensure_traffic_present

scenarios=()
if [[ "$SCENARIO" == "all" ]]; then
  scenarios=("collector-restart" "consumer-rebound" "network-interruption")
else
  scenarios=("$SCENARIO")
fi

scenario_results='[]'
failed_count=0

for scenario_name in "${scenarios[@]}"; do
  scenario_json="$(run_one "$scenario_name")"
  scenario_results="$(echo "$scenario_results" | jq --argjson s "$scenario_json" '. + [$s]')"

  passed="$(echo "$scenario_json" | jq -r '.pass')"
  if [[ "$passed" != "true" ]]; then
    failed_count=$((failed_count + 1))
  fi
done

gate_pass="true"
if (( failed_count > 0 )); then
  gate_pass="false"
fi

cat >"$json_report" <<EOF
$(jq -n \
  --arg generated_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg namespace "$NAMESPACE" \
  --arg prometheus_url "$PROMETHEUS_URL" \
  --arg metrics_window "$METRICS_WINDOW" \
  --argjson recovery_timeout_seconds "$RECOVERY_TIMEOUT_SECONDS" \
  --argjson poll_interval_seconds "$POLL_INTERVAL_SECONDS" \
  --arg metrics_validation_tolerance_percent "$METRICS_VALIDATION_TOLERANCE_PERCENT" \
  --argjson scenarios "$scenario_results" \
  --arg gate_pass "$gate_pass" \
  --argjson failed_count "$failed_count" \
  '{
    generated_at_utc: $generated_at_utc,
    namespace: $namespace,
    prometheus_url: $prometheus_url,
    metrics_window: $metrics_window,
    recovery_timeout_seconds: $recovery_timeout_seconds,
    poll_interval_seconds: $poll_interval_seconds,
    metrics_validation_tolerance_percent: ($metrics_validation_tolerance_percent | tonumber),
    scenarios: $scenarios,
    failed_count: $failed_count,
    gate_pass: ($gate_pass == "true")
  }')
EOF

jq -r '
  "OKPS Resilience Suite Report",
  "Generated (UTC): " + .generated_at_utc,
  "Namespace: " + .namespace,
  "Prometheus URL: " + .prometheus_url,
  "metrics_window: " + .metrics_window,
  "metrics_validation_tolerance_percent: " + (.metrics_validation_tolerance_percent | tostring),
  "",
  (.scenarios[] | (
    "Scenario: " + .scenario,
    "  pass: " + (.pass | tostring),
    "  recovery_seconds: " + (.recovery.recovery_seconds | tostring),
    "  tolerance_ratio: " + (.recovery.tolerance_ratio | tostring),
    "  max producer_collector_relative_delta: " + (.recovery.max_relative_deltas.producer_collector | tostring),
    "  max collector_consumer_relative_delta: " + (.recovery.max_relative_deltas.collector_consumer | tostring),
    "  post producer_collector_delta: " + (.post_recovery_sample.producer_collector_delta | tostring),
    "  post collector_consumer_delta: " + (.post_recovery_sample.collector_consumer_delta | tostring),
    ""
  )),
  "Suite pass: " + (.gate_pass | tostring)
' "$json_report" >"$txt_report"

cp "$json_report" "$latest_json"
cp "$txt_report" "$latest_txt"

echo "JSON report: $json_report"
echo "Text report: $txt_report"
echo "Suite pass: $gate_pass"

if [[ "$gate_pass" != "true" ]]; then
  exit 1
fi
