# US-004: OTel Collector Load-Balancing Configuration

## User Story
As a platform engineer, I want the collector tier to route telemetry to consumers using runId-affinity load balancing so that per-run distribution stays stable during active traffic.

## Acceptance Criteria

- Collector receiver accepts OTLP gRPC on port 4317.
- Export path sends OTLP gRPC to consumer endpoints discovered through headless service.
- Load balancing policy uses runId key-based routing.
- Key cache has bounded TTL and size settings.
- Collector emits counters for receive, export, and export errors.
- Config validation passes with otelcol dry-run or equivalent validation command.

## Files to Create

- deploy/collector/collector-config.yaml
- deploy/collector/README.md

## Files to Change

- README.md
- docs/architecture/collector-routing.md

## Dependencies

- US-001
- US-003
