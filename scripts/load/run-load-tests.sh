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

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FAIRNESS_SCRIPT="$SCRIPT_DIR/calc-fairness.py"

if [[ ! -f "$FAIRNESS_SCRIPT" ]]; then
  echo "ERROR: missing fairness script at $FAIRNESS_SCRIPT" >&2
  exit 2
fi

NAMESPACE="${NAMESPACE:-okps}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/_bmad-output/test-artifacts/load}"
SCENARIOS=()
OVERRIDE_P_REPLICAS=""
OVERRIDE_C_REPLICAS=""
OVERRIDE_U_REPLICAS=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --scenario <path>            Scenario YAML file. Can be passed multiple times.
  --producer-replicas <list>   Override producer replicas (comma-separated).
  --collector-replicas <list>  Override collector replicas (comma-separated).
  --consumer-replicas <list>   Override consumer replicas (comma-separated).
  --help                       Show this help.

Defaults:
  --scenario tests/load/steady-state.yaml
  --scenario tests/load/burst.yaml

Environment overrides:
  NAMESPACE
  PROMETHEUS_URL
  OUTPUT_DIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIOS+=("$2")
      shift 2
      ;;
    --producer-replicas)
      OVERRIDE_P_REPLICAS="$2"
      shift 2
      ;;
    --collector-replicas)
      OVERRIDE_C_REPLICAS="$2"
      shift 2
      ;;
    --consumer-replicas)
      OVERRIDE_U_REPLICAS="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  SCENARIOS=(
    "$ROOT_DIR/tests/load/steady-state.yaml"
    "$ROOT_DIR/tests/load/burst.yaml"
  )
fi

mkdir -p "$OUTPUT_DIR"

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf "%s" "$s"
}

yaml_scalar() {
  local key="$1"
  local file="$2"
  local raw
  raw="$(grep -E "^[[:space:]]*${key}:[[:space:]]*" "$file" | head -n1 | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//")"
  raw="${raw%\"}"
  raw="${raw#\"}"
  trim "$raw"
}

yaml_array() {
  local key="$1"
  local file="$2"
  local raw
  raw="$(grep -E "^[[:space:]]*${key}:[[:space:]]*\[[^]]*\]" "$file" | head -n1 | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//")"
  raw="${raw#[}"
  raw="${raw%]}"
  raw="$(echo "$raw" | tr ',' ' ')"
  trim "$raw"
}

csv_to_words() {
  echo "$1" | tr ',' ' '
}

query_scalar() {
  local query="$1"
  local result
  result="$(curl -fsS -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query")"
  echo "$result" | jq -r '.data.result[0].value[1] // "0"'
}

float_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit (a < b) ? 0 : 1 }'
}

float_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit (a > b) ? 0 : 1 }'
}

float_div() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) print "0"; else printf "%.6f", a / b }'
}

summarize_bottlenecks() {
  local collector_ratio="$1"
  local consumer_ratio="$2"
  local fairness_score="$3"
  local skew_ratio="$4"
  local producer_errors="$5"
  local collector_errors="$6"
  local consumer_errors="$7"
  local min_collector_ratio="$8"
  local min_consumer_ratio="$9"
  local min_fairness="${10}"
  local max_skew="${11}"

  local bottlenecks=""
  local actions=""

  if float_lt "$collector_ratio" "$min_collector_ratio"; then
    bottlenecks+="collector_ingress_or_export_saturation|"
    actions+="Scale collector replicas and review collector CPU/export queue pressure.|"
  fi

  if float_lt "$consumer_ratio" "$min_consumer_ratio"; then
    bottlenecks+="consumer_tier_saturation|"
    actions+="Scale consumer replicas and inspect decode latency/error trends.|"
  fi

  if float_lt "$fairness_score" "$min_fairness"; then
    bottlenecks+="distribution_fairness_degradation|"
    actions+="Increase consumer replicas and verify runId load-balancing key-cache behavior.|"
  fi

  if float_gt "$skew_ratio" "$max_skew"; then
    bottlenecks+="consumer_hotspotting|"
    actions+="Tune collector endpoint balancing and validate endpoint churn behavior.|"
  fi

  if float_gt "$producer_errors" "0"; then
    bottlenecks+="producer_send_errors|"
    actions+="Reduce per-pod send rate or scale producers with adequate collector capacity.|"
  fi

  if float_gt "$collector_errors" "0"; then
    bottlenecks+="collector_export_errors|"
    actions+="Scale collectors and verify downstream consumer endpoint availability.|"
  fi

  if float_gt "$consumer_errors" "0"; then
    bottlenecks+="consumer_decode_errors|"
    actions+="Inspect payload contract violations and consumer decode path.|"
  fi

  if [[ -z "$bottlenecks" ]]; then
    bottlenecks="none_detected|"
    actions="Current replica mix is healthy; consider this shape as a baseline scaling point.|"
  fi

  jq -n \
    --arg b "$bottlenecks" \
    --arg a "$actions" \
    '{
      bottlenecks: ($b | split("|") | map(select(length > 0))),
      recommended_actions: ($a | split("|") | map(select(length > 0)))
    }'
}

run_one() {
  local scenario_name="$1"
  local scenario_profile="$2"
  local duration_seconds="$3"
  local ramp_up_seconds="$4"
  local metrics_window_seconds="$5"
  local sample_interval_seconds="$6"
  local min_fairness="$7"
  local max_skew="$8"
  local min_consumer_ratio="$9"
  local min_collector_ratio="${10}"
  local producer_replicas="${11}"
  local collector_replicas="${12}"
  local consumer_replicas="${13}"

  local run_id="${scenario_name}-p${producer_replicas}-c${collector_replicas}-u${consumer_replicas}-$(date -u +%Y%m%dT%H%M%SZ)"
  local run_json="$OUTPUT_DIR/${run_id}.json"
  local run_txt="$OUTPUT_DIR/${run_id}.txt"

  echo "Running load profile=$scenario_profile run=$run_id"

  kubectl -n "$NAMESPACE" scale deploy/okps-producer --replicas="$producer_replicas" >/dev/null
  kubectl -n "$NAMESPACE" scale deploy/okps-collector --replicas="$collector_replicas" >/dev/null
  kubectl -n "$NAMESPACE" scale deploy/okps-consumer --replicas="$consumer_replicas" >/dev/null

  kubectl -n "$NAMESPACE" rollout status deploy/okps-producer --timeout=300s >/dev/null
  kubectl -n "$NAMESPACE" rollout status deploy/okps-collector --timeout=300s >/dev/null
  kubectl -n "$NAMESPACE" rollout status deploy/okps-consumer --timeout=300s >/dev/null

  sleep "$ramp_up_seconds"
  sleep "$duration_seconds"

  local window="${metrics_window_seconds}s"

  local producer_expr="sum(increase(okps_producer_messages_sent_total[$window]))"
  local collector_expr="sum(increase(okps_collector_messages_received_total[$window]))"
  local consumer_expr="sum(increase(okps_consumer_messages_received_total[$window]))"
  local producer_err_expr="sum(increase(okps_producer_send_errors_total[$window]))"
  local collector_err_expr="sum(increase(okps_collector_export_errors_total[$window]))"
  local consumer_err_expr="sum(increase(okps_consumer_decode_errors_total[$window]))"
  local per_consumer_expr="sum by (pod) (increase(okps_consumer_messages_received_total[$window]))"

  local producer_sent
  local collector_received
  local consumers_received
  local producer_errors
  local collector_errors
  local consumer_errors
  local collector_ratio
  local consumer_ratio

  producer_sent="$(query_scalar "$producer_expr")"
  collector_received="$(query_scalar "$collector_expr")"
  consumers_received="$(query_scalar "$consumer_expr")"
  producer_errors="$(query_scalar "$producer_err_expr")"
  collector_errors="$(query_scalar "$collector_err_expr")"
  consumer_errors="$(query_scalar "$consumer_err_expr")"

  collector_ratio="$(float_div "$collector_received" "$producer_sent")"
  consumer_ratio="$(float_div "$consumers_received" "$producer_sent")"

  local vector_result
  local distribution_tmp
  local fairness_tmp
  distribution_tmp="$(mktemp)"
  fairness_tmp="$(mktemp)"

  vector_result="$(curl -fsS -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$per_consumer_expr")"
  echo "$vector_result" | jq '[
    .data.result[]? | {
      pod: (.metric.pod // .metric.kubernetes_pod_name // .metric.instance // "unknown"),
      value: (.value[1] | tonumber)
    }
  ]' >"$distribution_tmp"

  python3 "$FAIRNESS_SCRIPT" --input "$distribution_tmp" --min-fairness "$min_fairness" >"$fairness_tmp"

  local fairness_score
  local skew_ratio
  fairness_score="$(jq -r '.fairness_score' "$fairness_tmp")"
  skew_ratio="$(jq -r '.skew_ratio_max_to_min' "$fairness_tmp")"

  local bottleneck_json
  bottleneck_json="$(summarize_bottlenecks \
    "$collector_ratio" \
    "$consumer_ratio" \
    "$fairness_score" \
    "$skew_ratio" \
    "$producer_errors" \
    "$collector_errors" \
    "$consumer_errors" \
    "$min_collector_ratio" \
    "$min_consumer_ratio" \
    "$min_fairness" \
    "$max_skew")"

  jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg scenario_name "$scenario_name" \
    --arg scenario_profile "$scenario_profile" \
    --argjson duration_seconds "$duration_seconds" \
    --argjson ramp_up_seconds "$ramp_up_seconds" \
    --argjson sample_interval_seconds "$sample_interval_seconds" \
    --arg metrics_window "$window" \
    --arg namespace "$NAMESPACE" \
    --arg prometheus_url "$PROMETHEUS_URL" \
    --argjson producer_replicas "$producer_replicas" \
    --argjson collector_replicas "$collector_replicas" \
    --argjson consumer_replicas "$consumer_replicas" \
    --argjson producer_sent "$producer_sent" \
    --argjson collector_received "$collector_received" \
    --argjson consumers_received "$consumers_received" \
    --argjson producer_errors "$producer_errors" \
    --argjson collector_errors "$collector_errors" \
    --argjson consumer_errors "$consumer_errors" \
    --argjson collector_ratio "$collector_ratio" \
    --argjson consumer_ratio "$consumer_ratio" \
    --argjson distribution "$(cat "$distribution_tmp")" \
    --argjson fairness "$(cat "$fairness_tmp")" \
    --argjson analysis "$bottleneck_json" \
    '{
      generated_at_utc: $generated_at,
      scenario: {
        name: $scenario_name,
        profile: $scenario_profile,
        duration_seconds: $duration_seconds,
        ramp_up_seconds: $ramp_up_seconds,
        sample_interval_seconds: $sample_interval_seconds,
        metrics_window: $metrics_window
      },
      environment: {
        namespace: $namespace,
        prometheus_url: $prometheus_url
      },
      replicas: {
        producer: $producer_replicas,
        collector: $collector_replicas,
        consumer: $consumer_replicas
      },
      totals: {
        producer_sent: $producer_sent,
        collector_received: $collector_received,
        consumers_received: $consumers_received
      },
      ratios: {
        collector_receive_ratio: $collector_ratio,
        consumer_receive_ratio: $consumer_ratio
      },
      errors: {
        producer_send_errors: $producer_errors,
        collector_export_errors: $collector_errors,
        consumer_decode_errors: $consumer_errors
      },
      per_consumer_distribution: $distribution,
      fairness: $fairness,
      saturation_analysis: $analysis
    }' >"$run_json"

  cat >"$run_txt" <<EOF
OKPS Load Validation Report
Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
Run ID: $run_id
Scenario: $scenario_name ($scenario_profile)
Duration seconds: $duration_seconds
Ramp-up seconds: $ramp_up_seconds
metrics_window: $window

Replica mix:
  producer=$producer_replicas collector=$collector_replicas consumer=$consumer_replicas

Totals:
  producer_sent=$producer_sent
  collector_received=$collector_received
  consumers_received=$consumers_received

Ratios:
  collector_receive_ratio=$collector_ratio
  consumer_receive_ratio=$consumer_ratio

Per-consumer distribution:
$(jq -r '.[] | "  - \(.pod): \(.value)"' "$distribution_tmp")

Fairness:
  fairness_score=$(jq -r '.fairness_score' "$fairness_tmp")
  jain_fairness_index=$(jq -r '.jain_fairness_index' "$fairness_tmp")
  skew_ratio_max_to_min=$(jq -r '.skew_ratio_max_to_min' "$fairness_tmp")

Saturation analysis:
$(echo "$bottleneck_json" | jq -r '.bottlenecks[] | "  - bottleneck: " + .')
$(echo "$bottleneck_json" | jq -r '.recommended_actions[] | "  - recommended_action: " + .')
EOF

  rm -f "$distribution_tmp" "$fairness_tmp"
  echo "$run_json"
}

run_results=()

for scenario in "${SCENARIOS[@]}"; do
  if [[ ! -f "$scenario" ]]; then
    if [[ -f "$ROOT_DIR/$scenario" ]]; then
      scenario="$ROOT_DIR/$scenario"
    else
      echo "ERROR: scenario file not found: $scenario" >&2
      exit 2
    fi
  fi

  scenario_name="$(yaml_scalar name "$scenario")"
  scenario_profile="$(yaml_scalar profile "$scenario")"
  duration_seconds="$(yaml_scalar duration_seconds "$scenario")"
  ramp_up_seconds="$(yaml_scalar ramp_up_seconds "$scenario")"
  sample_interval_seconds="$(yaml_scalar sample_interval_seconds "$scenario")"
  metrics_window_seconds="$(yaml_scalar metrics_window_seconds "$scenario")"

  min_fairness="$(yaml_scalar min_fairness_score "$scenario")"
  max_skew="$(yaml_scalar max_consumer_skew_ratio "$scenario")"
  min_consumer_ratio="$(yaml_scalar min_consumer_receive_ratio "$scenario")"
  min_collector_ratio="$(yaml_scalar min_collector_receive_ratio "$scenario")"

  p_replicas="$(yaml_array producer_replicas "$scenario")"
  c_replicas="$(yaml_array collector_replicas "$scenario")"
  u_replicas="$(yaml_array consumer_replicas "$scenario")"

  if [[ -n "$OVERRIDE_P_REPLICAS" ]]; then
    p_replicas="$(csv_to_words "$OVERRIDE_P_REPLICAS")"
  fi
  if [[ -n "$OVERRIDE_C_REPLICAS" ]]; then
    c_replicas="$(csv_to_words "$OVERRIDE_C_REPLICAS")"
  fi
  if [[ -n "$OVERRIDE_U_REPLICAS" ]]; then
    u_replicas="$(csv_to_words "$OVERRIDE_U_REPLICAS")"
  fi

  for p in $p_replicas; do
    for c in $c_replicas; do
      for u in $u_replicas; do
        run_json_path="$(run_one \
          "$scenario_name" \
          "$scenario_profile" \
          "$duration_seconds" \
          "$ramp_up_seconds" \
          "$metrics_window_seconds" \
          "$sample_interval_seconds" \
          "$min_fairness" \
          "$max_skew" \
          "$min_consumer_ratio" \
          "$min_collector_ratio" \
          "$p" \
          "$c" \
          "$u")"
        run_results+=("$run_json_path")
      done
    done
  done
done

summary_json="$OUTPUT_DIR/load-summary-$(date -u +%Y%m%dT%H%M%SZ).json"
summary_txt="$OUTPUT_DIR/load-summary-$(date -u +%Y%m%dT%H%M%SZ).txt"
latest_json="$OUTPUT_DIR/latest.json"
latest_txt="$OUTPUT_DIR/latest.txt"

jq -n --argjson runs "$(printf '%s\n' "${run_results[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
'[
  $runs[] as $path | (input_filename | .)
]' >/dev/null 2>&1 || true

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson runs "$(printf '%s\n' "${run_results[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
  '{
    generated_at_utc: $generated_at,
    report_count: ($runs | length),
    run_reports: $runs
  }' >"$summary_json"

{
  echo "OKPS Load Validation Summary"
  echo "Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Report count: ${#run_results[@]}"
  echo
  echo "Run reports:"
  for rp in "${run_results[@]}"; do
    echo "  - $rp"
  done
} >"$summary_txt"

cp "$summary_json" "$latest_json"
cp "$summary_txt" "$latest_txt"

echo "Summary JSON: $summary_json"
echo "Summary text: $summary_txt"
