# US-008: Alerting Rules and Reconciliation Gate

## User Story
As an SRE, I want alert rules and an automated reconciliation gate so that sustained count mismatches fail fast before release.

## Acceptance Criteria

- Prometheus alert rules include warning and critical thresholds for reconciliation failures.
- Alert criteria follow metrics_validation_tolerance_percent.
- Reconciliation gate script evaluates producer_sent, collector_received, and consumers_received.
- Gate fails when ratios remain below threshold for more than one scrape interval.
- Gate output is stored as machine-readable and human-readable reports.

## Files to Create

- deploy/monitoring/prometheus-alerts-okps.yaml
- scripts/validate-reconciliation.sh
- scripts/validate-reconciliation-promql.sh
- _bmad-output/test-artifacts/reconciliation/README.md

## Files to Change

- deploy/monitoring/grafana-okps-dashboard.json
- docs/monitoring/queries.md
- README.md

## Dependencies

- US-007
