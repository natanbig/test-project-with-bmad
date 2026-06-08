#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
promql_script="$script_dir/validate-reconciliation-promql.sh"

if [[ ! -x "$promql_script" ]]; then
  echo "ERROR: missing executable script: $promql_script" >&2
  exit 2
fi

"$promql_script"

latest_json="${OUTPUT_DIR:-_bmad-output/test-artifacts/reconciliation}/latest.json"
if [[ -f "$latest_json" ]] && command -v jq >/dev/null 2>&1; then
  gate_pass="$(jq -r '.gate_pass' "$latest_json")"
  producer_sent="$(jq -r '.totals.producer_sent' "$latest_json")"
  collector_received="$(jq -r '.totals.collector_received' "$latest_json")"
  consumers_received="$(jq -r '.totals.consumers_received' "$latest_json")"

  echo "Reconciliation summary: producer_sent=$producer_sent collector_received=$collector_received consumers_received=$consumers_received gate_pass=$gate_pass"
fi
