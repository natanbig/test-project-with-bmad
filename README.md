# test-project-with-bmad

## Services

- Producer: sends OTLP gRPC traces with envelope attributes to the collector path.
- Consumer: receives OTLP gRPC traces, decodes envelope attributes, validates the contract, and exposes receive/decode metrics.
- Collector: receives OTLP gRPC, applies runId-affinity load balancing, and exports OTLP gRPC to consumer endpoints from headless-service discovery.

Run locally:
- Producer: make run-producer
- Consumer: make run-consumer

## Scale and Distribution Fairness Validation (US-010)

- Scenario profiles:
	- `tests/load/steady-state.yaml`
	- `tests/load/burst.yaml`
- Load/fairness runner: `scripts/load/run-load-tests.sh`
- Fairness calculator: `scripts/load/calc-fairness.py`
- Reports output: `_bmad-output/test-artifacts/load/README.md`

Run both profiles:

```bash
chmod +x ./scripts/load/run-load-tests.sh ./scripts/load/calc-fairness.py
./scripts/load/run-load-tests.sh
```

Run a single profile:

```bash
./scripts/load/run-load-tests.sh --scenario tests/load/steady-state.yaml
./scripts/load/run-load-tests.sh --scenario tests/load/burst.yaml
```

Override replica matrix for a targeted run set:

```bash
./scripts/load/run-load-tests.sh \
	--producer-replicas 2,4 \
	--collector-replicas 1,2 \
	--consumer-replicas 2,4
```

## Collector Config (US-004)

- Collector config: `deploy/collector/collector-config.yaml`
- Collector routing architecture notes: `docs/architecture/collector-routing.md`
- Collector deployment notes and validate command: `deploy/collector/README.md`

## Kubernetes Deployment Topology (US-005)

- Namespace, deployments, services, and runtime config manifests: `deploy/k8s/`
- Collector ingress service: `deploy/k8s/collector-service.yaml` (ClusterIP on 4317)
- Consumer discovery service: `deploy/k8s/consumer-headless-service.yaml` (headless)
- Runtime ConfigMaps and example Secret: `deploy/k8s/configmap.yaml`, `deploy/k8s/secret.example.yaml`
- End-to-end deployment and validation runbook: `docs/operations/deploy.md`

## Monitoring and Reconciliation Dashboard (US-007)

- Prometheus scrape jobs for producer, collector, and consumer metrics: `deploy/monitoring/prometheus-scrape-okps.yaml`
- Grafana reconciliation dashboard definition: `deploy/monitoring/grafana-okps-dashboard.json`
- Query catalog and panel formulas (including `$metrics_window`): `docs/monitoring/queries.md`

## Alerting and Reconciliation Gate (US-008)

- Prometheus alert rules for warning and critical reconciliation thresholds: `deploy/monitoring/prometheus-alerts-okps.yaml`
- Reconciliation gate script (wrapper): `scripts/validate-reconciliation.sh`
- Reconciliation PromQL evaluator and report generator: `scripts/validate-reconciliation-promql.sh`
- Gate artifacts (machine-readable + human-readable): `_bmad-output/test-artifacts/reconciliation/README.md`

Run locally:

```bash
chmod +x ./scripts/validate-reconciliation.sh ./scripts/validate-reconciliation-promql.sh
./scripts/validate-reconciliation.sh
```

## Resilience Test Suite (US-009)

- Scenario docs:
	- `tests/resilience/collector-restart.md`
	- `tests/resilience/consumer-rebound.md`
	- `tests/resilience/network-interruption.md`
- Runner script: `scripts/resilience/run-resilience-suite.sh`
- Report artifacts: `_bmad-output/test-artifacts/resilience/README.md`

Run locally:

```bash
chmod +x ./scripts/resilience/run-resilience-suite.sh
./scripts/resilience/run-resilience-suite.sh
```

Run an individual scenario:

```bash
./scripts/resilience/run-resilience-suite.sh --scenario collector-restart
./scripts/resilience/run-resilience-suite.sh --scenario consumer-rebound
./scripts/resilience/run-resilience-suite.sh --scenario network-interruption
```

## Payload Contract

The payload envelope contract for OKPS is defined in `proto/okps/envelope.proto`.
Validation logic for payload bounds is implemented in `pkg/contract/validate.go` with tests in `pkg/contract/validate_test.go`.
Contract documentation, compatibility notes, and examples are in `docs/contracts/payload-contract.md`.
