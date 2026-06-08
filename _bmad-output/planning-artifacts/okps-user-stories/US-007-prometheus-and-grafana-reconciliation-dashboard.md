# US-007: Prometheus and Grafana Reconciliation Dashboard

## User Story
As an SRE, I want standardized metrics scraping and Grafana reconciliation panels so that I can validate producer, collector, and consumer counts in near real time.

## Acceptance Criteria

- Prometheus scrapes producer, collector, and consumer metrics endpoints.
- Grafana dashboard includes total sent, collector received, and consumers received panels.
- Dashboard includes delta panels for producer->collector and collector->consumer.
- Dashboard includes ratio panels: collector_receive_ratio, consumer_receive_ratio, collector_to_consumer_ratio.
- Per-consumer distribution panel is present.
- Dashboard uses configurable metrics_window variable.

## Files to Create

- deploy/monitoring/prometheus-scrape-okps.yaml
- deploy/monitoring/grafana-okps-dashboard.json
- docs/monitoring/queries.md

## Files to Change

- README.md
- docs/operations/deploy.md

## Dependencies

- US-002
- US-003
- US-004
- US-005
