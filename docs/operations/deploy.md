# OKPS Kubernetes Deployment Runbook

This runbook deploys the producer, collector, consumer, Prometheus, and Grafana tiers to a local Kubernetes cluster.

## Prerequisites

- Docker Desktop Kubernetes context is active.
- `kubectl` is installed and points to the target cluster.
- Docker CLI is available so local service images can be built before deploy.

Build local producer/consumer images:

```bash
make docker-build-images
```

## Apply Manifests

Recommended one-step deployment (builds local images first):

```bash
make k8s-up
```

`make k8s-up` also triggers a rollout restart for producer and consumer deployments,
so pods pick up rebuilt `:dev` images.

If monitoring pods fail due to node disk pressure (for example Grafana `no space left on device`
or Prometheus startup faults), run:

```bash
make k8s-recover-monitoring
```

This target prunes unused node images, reapplies monitoring config/deployments, and waits for
Prometheus/Grafana rollout completion.

Manual apply sequence:

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/configmap.yaml
kubectl apply -f deploy/k8s/prometheus-configmap.yaml
kubectl apply -f deploy/k8s/grafana-configmap.yaml
kubectl apply -f deploy/k8s/grafana-dashboard-configmap.yaml
kubectl apply -f deploy/k8s/collector-service.yaml
kubectl apply -f deploy/k8s/consumer-headless-service.yaml
kubectl apply -f deploy/k8s/metrics-headless-services.yaml
kubectl apply -f deploy/k8s/prometheus-service.yaml
kubectl apply -f deploy/k8s/grafana-service.yaml
kubectl apply -f deploy/k8s/producer-deployment.yaml
kubectl apply -f deploy/k8s/collector-deployment.yaml
kubectl apply -f deploy/k8s/consumer-deployment.yaml
kubectl apply -f deploy/k8s/prometheus-deployment.yaml
kubectl apply -f deploy/k8s/grafana-deployment.yaml
kubectl apply -f deploy/k8s/hpa-producer.yaml
kubectl apply -f deploy/k8s/hpa-collector.yaml
kubectl apply -f deploy/k8s/hpa-consumer.yaml
kubectl apply -f deploy/k8s/pdb-collector.yaml
kubectl apply -f deploy/k8s/networkpolicy.yaml
```

Optional secret material for TLS or other runtime sensitive values:

```bash
cp deploy/k8s/secret.example.yaml /tmp/okps-secret.yaml
# edit /tmp/okps-secret.yaml with real values
kubectl apply -f /tmp/okps-secret.yaml
```

## Validate Manifests

Client-side schema validation:

```bash
kubectl apply --dry-run=client -f deploy/k8s/
```

Server-side validation against cluster API:

```bash
kubectl apply --dry-run=server -f deploy/k8s/
```

Collector config validation (optional, containerized):

```bash
docker run --rm \
  -v "$PWD/deploy/collector/collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro" \
  otel/opentelemetry-collector-contrib:0.130.0 \
  validate --config=/etc/otelcol-contrib/config.yaml
```

## Monitoring Setup (Built-In)

Monitoring artifacts are deployed by default with `make k8s-up`:

- Prometheus config source: `deploy/k8s/prometheus-configmap.yaml`
- Grafana provisioning config: `deploy/k8s/grafana-configmap.yaml`
- Grafana dashboard ConfigMap source: `deploy/k8s/grafana-dashboard-configmap.yaml`
- PromQL query catalog: `docs/monitoring/queries.md`

Prometheus and Grafana are available via in-cluster services:

```bash
kubectl -n okps get svc okps-prometheus okps-grafana
```

Port-forward and open the UIs locally:

```bash
kubectl -n okps port-forward svc/okps-prometheus 9090:9090
kubectl -n okps port-forward svc/okps-grafana 3000:3000
```

Grafana defaults to `admin/admin` and auto-provisions:
- datasource `OKPS Prometheus` -> `http://okps-prometheus.okps.svc.cluster.local:9090`
- dashboard from `deploy/monitoring/grafana-okps-dashboard.json`

After Grafana starts, set `metrics_window` as needed (default: `5m`).

Quick reconciliation spot checks from Prometheus expression browser:

```promql
sum(increase(okps_producer_messages_sent_total[5m]))
sum(increase(okps_collector_messages_received_total[5m]))
sum(increase(okps_consumer_messages_received_total[5m]))
```

## Resilience Suite (US-009)

Resilience scenarios and runner:

- `tests/resilience/collector-restart.md`
- `tests/resilience/consumer-rebound.md`
- `tests/resilience/network-interruption.md`
- `scripts/resilience/run-resilience-suite.sh`

Run the full resilience suite:

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

The suite writes reports under `_bmad-output/test-artifacts/resilience/` with recovery timelines and message loss deltas.

## Load and Fairness Validation (US-010)

Load/fairness scenarios:

- `tests/load/steady-state.yaml`
- `tests/load/burst.yaml`

Runner and fairness calculator:

- `scripts/load/run-load-tests.sh`
- `scripts/load/calc-fairness.py`

Run both profiles (steady-state + burst):

```bash
chmod +x ./scripts/load/run-load-tests.sh ./scripts/load/calc-fairness.py
./scripts/load/run-load-tests.sh
```

Run only one profile:

```bash
./scripts/load/run-load-tests.sh --scenario tests/load/steady-state.yaml
./scripts/load/run-load-tests.sh --scenario tests/load/burst.yaml
```

Target a specific replica matrix:

```bash
./scripts/load/run-load-tests.sh \
  --producer-replicas 2,4 \
  --collector-replicas 1,2 \
  --consumer-replicas 2,4
```

The runner scales producer/collector/consumer replicas per test combination, computes per-consumer distribution stats, derives a fairness score per run, and emits bottleneck/saturation recommendations.

Artifacts are written to:

- `_bmad-output/test-artifacts/load/` (timestamped JSON/TXT reports)
- `_bmad-output/test-artifacts/load/latest.json`
- `_bmad-output/test-artifacts/load/latest.txt`

## Rollout Checks

```bash
kubectl -n okps get pods
kubectl -n okps get svc
kubectl -n okps get hpa
kubectl -n okps get pdb
kubectl -n okps rollout status deploy/okps-producer
kubectl -n okps rollout status deploy/okps-collector
kubectl -n okps rollout status deploy/okps-consumer
kubectl -n okps rollout status deploy/okps-prometheus
kubectl -n okps rollout status deploy/okps-grafana
```

Troubleshooting signatures this runbook addresses:
- Grafana: `failed to create directory "/var/lib/grafana/png": no space left on device`
- Prometheus: `fatal error: fault` / `SIGBUS` during startup

## Cleanup

```bash
kubectl delete -f deploy/k8s/grafana-deployment.yaml
kubectl delete -f deploy/k8s/prometheus-deployment.yaml
kubectl delete -f deploy/k8s/producer-deployment.yaml
kubectl delete -f deploy/k8s/collector-deployment.yaml
kubectl delete -f deploy/k8s/consumer-deployment.yaml
kubectl delete -f deploy/k8s/hpa-producer.yaml
kubectl delete -f deploy/k8s/hpa-collector.yaml
kubectl delete -f deploy/k8s/hpa-consumer.yaml
kubectl delete -f deploy/k8s/pdb-collector.yaml
kubectl delete -f deploy/k8s/networkpolicy.yaml
kubectl delete -f deploy/k8s/grafana-service.yaml
kubectl delete -f deploy/k8s/prometheus-service.yaml
kubectl delete -f deploy/k8s/metrics-headless-services.yaml
kubectl delete -f deploy/k8s/collector-service.yaml
kubectl delete -f deploy/k8s/consumer-headless-service.yaml
kubectl delete -f deploy/k8s/grafana-dashboard-configmap.yaml
kubectl delete -f deploy/k8s/grafana-configmap.yaml
kubectl delete -f deploy/k8s/prometheus-configmap.yaml
kubectl delete -f deploy/k8s/configmap.yaml
kubectl delete -f deploy/k8s/namespace.yaml
```
