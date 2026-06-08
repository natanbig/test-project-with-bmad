# Resilience Test Artifacts (US-009)

This folder stores outputs from the resilience suite:

- `scripts/resilience/run-resilience-suite.sh`

## Generated Files

- `resilience-<timestamp>.json`: full machine-readable scenario results.
- `resilience-<timestamp>.txt`: concise summary report.
- `latest.json`: copy of the latest JSON run.
- `latest.txt`: copy of the latest text run.

## Scenarios Covered

- `collector-restart`
- `consumer-rebound`
- `network-interruption`

## Report Content

Each scenario includes:

- Fault injection timeline (`fault_window_utc`).
- Recovery timeline (`recovery.recovery_seconds`).
- Windowed totals for producer, collector, and consumer counters.
- Message loss deltas:
  - `producer_collector_delta`
  - `collector_consumer_delta`
- Relative deltas and tolerance decision for reconciliation.

## Run

```bash
chmod +x ./scripts/resilience/run-resilience-suite.sh
./scripts/resilience/run-resilience-suite.sh
```

Run a single scenario:

```bash
./scripts/resilience/run-resilience-suite.sh --scenario collector-restart
./scripts/resilience/run-resilience-suite.sh --scenario consumer-rebound
./scripts/resilience/run-resilience-suite.sh --scenario network-interruption
```
