# Collector-to-Consumer Network Interruption Test

## Objective

Validate temporary interruption between collector and consumer traffic, then verify recovery behavior and reconciliation tolerance after connectivity is restored.

## Acceptance Criteria Coverage

- Temporary network interruption between collector and consumer.
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
./scripts/resilience/run-resilience-suite.sh --scenario network-interruption
```

## Fault Injection

The suite temporarily removes the consumer ingress allow policy to block collector->consumer traffic:

```bash
kubectl -n okps delete networkpolicy okps-consumer-traffic
sleep ${NETWORK_INTERRUPTION_SECONDS:-30}
kubectl apply -f deploy/k8s/networkpolicy.yaml
```

The script also restores policies during cleanup if interrupted.

## Evidence Produced

Per run, the suite writes artifacts under `_bmad-output/test-artifacts/resilience/`:

- Interruption start/end timestamps.
- Recovery seconds after policy restoration.
- Windowed totals, deltas, and relative deltas.
- Final reconciliation status for post-recovery window.

## Pass Criteria

- Interruption is injected and reverted successfully.
- Recovery is achieved before timeout.
- Final post-recovery deltas meet configured tolerance.
