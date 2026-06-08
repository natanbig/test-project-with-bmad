# Collector Restart Resilience Test

## Objective

Validate that restarting the collector deployment during sustained producer load recovers within the expected timeline and stays within reconciliation tolerance after the recovery window.

## Acceptance Criteria Coverage

- Collector restart under sustained load.
- Recovery timeline is captured.
- Message loss deltas are captured.
- Reconciliation meets tolerance after recovery window.

## Preconditions

- OKPS stack is deployed in namespace `okps`.
- Producer traffic is active (`okps_producer_messages_sent_total` is increasing).
- Prometheus is reachable.

## Execute

```bash
chmod +x ./scripts/resilience/run-resilience-suite.sh
./scripts/resilience/run-resilience-suite.sh --scenario collector-restart
```

## Fault Injection

The suite runs:

```bash
kubectl -n okps rollout restart deploy/okps-collector
kubectl -n okps rollout status deploy/okps-collector --timeout=300s
```

## Evidence Produced

Per run, the suite writes artifacts under `_bmad-output/test-artifacts/resilience/`:

- Scenario event timeline and UTC timestamps.
- Recovery seconds from injection completion to tolerance recovery.
- Windowed totals for producer, collector, and consumers.
- Delta metrics:
  - `producer_collector_delta`
  - `collector_consumer_delta`
  - Relative deltas used by pass/fail gate.

## Pass Criteria

- Recovery is achieved before timeout.
- Post-recovery relative deltas are within:

$$
\text{tolerance ratio} = \frac{\text{METRICS_VALIDATION_TOLERANCE_PERCENT}}{100}
$$

for both producer->collector and collector->consumer paths.
