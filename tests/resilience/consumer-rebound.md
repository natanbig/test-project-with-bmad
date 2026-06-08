# Consumer Rebound Resilience Test

## Objective

Validate that scaling consumers down and back up under sustained load rebounds correctly and restores reconciliation within tolerance.

## Acceptance Criteria Coverage

- Consumer scale-down and scale-up rebound.
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
./scripts/resilience/run-resilience-suite.sh --scenario consumer-rebound
```

## Fault Injection

The suite runs:

```bash
kubectl -n okps scale deploy/okps-consumer --replicas=0
kubectl -n okps rollout status deploy/okps-consumer --timeout=300s
sleep ${CONSUMER_DOWNTIME_SECONDS:-30}
kubectl -n okps scale deploy/okps-consumer --replicas=<original>
kubectl -n okps rollout status deploy/okps-consumer --timeout=300s
```

## Evidence Produced

Per run, the suite writes artifacts under `_bmad-output/test-artifacts/resilience/`:

- Scenario timeline with scale-down and scale-up timestamps.
- Recovery seconds after scale-up completion.
- Windowed producer/collector/consumer totals.
- Message loss deltas and relative deltas across the recovery window.

## Pass Criteria

- Consumers recover to original replica count.
- Recovery is achieved before timeout.
- Post-recovery relative deltas remain within configured tolerance.
