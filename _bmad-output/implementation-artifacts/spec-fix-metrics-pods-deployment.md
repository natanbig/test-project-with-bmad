---
title: 'Fix Missing Metrics Stack Pod Deployment (Prometheus and Grafana)'
type: 'bugfix'
created: '2026-06-08T12:00:00Z'
status: 'done'
baseline_commit: 'c114a51c46e3e62e9536db20094eb0c5e8cae4f9'
context:
  - '{project-root}/skills/reports/okps-system-design.md'
  - '{project-root}/docs/operations/deploy.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** OKPS currently deploys only producer/collector/consumer workloads, while Prometheus and Grafana are treated as external/manual integration artifacts. This conflicts with the OKPS system design expectation that observability services are part of the deployed local stack.

**Approach:** Add Kubernetes manifests that deploy Prometheus and Grafana pods/services with baseline local configuration, and update deploy/cleanup runbooks so `k8s-up` and `k8s-down` consistently manage the metrics stack alongside existing OKPS resources.

## Boundaries & Constraints

**Always:**
- Keep the fix limited to local Kubernetes deployment assets and deployment documentation.
- Reuse existing monitoring assets where possible: `deploy/monitoring/prometheus-scrape-okps.yaml`, `deploy/monitoring/prometheus-alerts-okps.yaml`, and `deploy/monitoring/grafana-okps-dashboard.json`.
- Ensure Prometheus can scrape producer, collector, and consumer metrics after deployment.
- Ensure Grafana can query the in-cluster Prometheus service by default.
- Use explicit Kubernetes manifests under `deploy/k8s/` consistent with current project style.

**Ask First:**
- Whether persistence is required for Prometheus/Grafana data in this local Docker Desktop phase (PVC vs ephemeral storage).
- Whether external exposure should be `ClusterIP` only or include optional `NodePort` settings.
- Whether to include optional auth hardening defaults (Grafana admin secret requirement) in this bugfix or defer to a follow-up.

**Never:**
- Refactor existing producer/collector/consumer runtime behavior.
- Replace the current deployment approach with Helm in this fix.
- Introduce cloud-managed observability dependencies.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | User runs `make k8s-up` on Docker Desktop context | Prometheus and Grafana pods are created in `okps` namespace, services are created, Prometheus scrape targets include OKPS workloads | N/A |
| PARTIAL_CLEANUP | Existing cluster has old OKPS resources and user runs `make k8s-down` | Prometheus/Grafana manifests are deleted with `--ignore-not-found=true` semantics | Missing resources do not fail cleanup |
| MISCONFIGURED_DATASOURCE | Grafana starts before Prometheus service is ready | Grafana pod remains healthy; dashboard queries may show temporary no-data until Prometheus becomes reachable | Document rollout-order expectation and readiness checks |

</frozen-after-approval>

## Code Map

- `deploy/k8s/` -- primary Kubernetes manifests for deployed local stack.
- `Makefile` -- `k8s-up` and `k8s-down` orchestration targets.
- `docs/operations/deploy.md` -- operator runbook and validation commands.
- `deploy/monitoring/prometheus-scrape-okps.yaml` -- existing scrape snippet to embed/use in Prometheus config.
- `deploy/monitoring/grafana-okps-dashboard.json` -- existing dashboard to provision/import.

## Tasks & Acceptance

**Execution:**
- [x] `deploy/k8s/prometheus-configmap.yaml` -- add Prometheus config (global scrape interval + OKPS scrape jobs) -- enables in-cluster scraping without manual copy/paste.
- [x] `deploy/k8s/prometheus-deployment.yaml` -- add Prometheus deployment using official image and config mount -- deploys Prometheus pod in local stack.
- [x] `deploy/k8s/prometheus-service.yaml` -- add Prometheus service (port 9090) -- enables in-cluster discovery by Grafana and optional port-forward.
- [x] `deploy/k8s/grafana-configmap.yaml` -- add Grafana provisioning for Prometheus datasource and dashboard provider -- avoids manual UI setup each deploy.
- [x] `deploy/k8s/grafana-dashboard-configmap.yaml` -- package existing OKPS dashboard JSON into ConfigMap -- provides automatic dashboard availability.
- [x] `deploy/k8s/grafana-deployment.yaml` -- add Grafana deployment mounting provisioning/dashboard config -- deploys Grafana pod in local stack.
- [x] `deploy/k8s/grafana-service.yaml` -- add Grafana service (port 3000) -- enables local access and port-forward workflows.
- [x] `deploy/k8s/networkpolicy.yaml` -- extend policy to allow required metrics-stack traffic (Prometheus scrape and Grafana->Prometheus) -- preserves least-privilege intent while enabling observability flow.
- [x] `Makefile` -- include new manifests in `k8s-up` apply order and `k8s-down` cleanup order -- ensures full-stack lifecycle is automated.
- [x] `docs/operations/deploy.md` -- replace manual external-monitoring-only guidance with built-in metrics-stack flow and validation commands -- keeps operations guidance aligned with real deployment.

**Acceptance Criteria:**
- Given Docker Desktop Kubernetes context and built local images, when `make k8s-up` runs, then Prometheus and Grafana pods are created in namespace `okps` and reach Ready state.
- Given Prometheus is deployed, when querying targets or running baseline PromQL checks, then producer/collector/consumer metrics endpoints are scraped successfully.
- Given Grafana is deployed, when port-forwarding/accessing Grafana, then an OKPS datasource to in-cluster Prometheus exists and the reconciliation dashboard is available without manual JSON import.
- Given a deployed stack, when `make k8s-down` runs, then Prometheus/Grafana resources are deleted with the rest of the OKPS resources.
- Given current runbook users, when they follow `docs/operations/deploy.md`, then deployment and monitoring verification steps match actual manifests and commands.

## Spec Change Log

## Design Notes

Use lightweight local defaults and avoid introducing extra controllers (for example ServiceMonitor dependencies) in this bugfix. Keep observability stack self-contained via Deployments + ConfigMaps, then rely on future Helm migration for richer packaging.

## Verification

**Commands:**
- `kubectl apply --dry-run=client -f deploy/k8s/` -- expected: all manifests validate locally.
- `make k8s-up` -- expected: rollout status succeeds for producer, collector, consumer, prometheus, grafana.
- `kubectl -n okps get pods,svc` -- expected: prometheus and grafana resources are present and Ready.
- `kubectl -n okps port-forward svc/okps-prometheus 9090:9090` -- expected: Prometheus UI reachable locally.
- `kubectl -n okps port-forward svc/okps-grafana 3000:3000` -- expected: Grafana UI reachable locally with preconfigured datasource/dashboard.
- `make k8s-down` -- expected: all newly added metrics resources are removed without errors.

## Suggested Review Order

**Deployment Entry Point**

- Start here to understand full lifecycle wiring for monitoring resources.
  [`Makefile:63`](../../Makefile#L63)

- Confirm rollout restarts cover config-driven monitoring components.
  [`Makefile:84`](../../Makefile#L84)

- Verify teardown includes all added monitoring resources.
  [`Makefile:100`](../../Makefile#L100)

**Prometheus Scrape Topology**

- Validate DNS-based per-pod scraping strategy for all tiers.
  [`prometheus-configmap.yaml:11`](../../deploy/k8s/prometheus-configmap.yaml#L11)

- Confirm headless services expose each tier's metrics endpoints.
  [`metrics-headless-services.yaml:1`](../../deploy/k8s/metrics-headless-services.yaml#L1)

**Grafana Provisioning**

- Check datasource UID binding for auto-provisioned dashboard compatibility.
  [`grafana-configmap.yaml:12`](../../deploy/k8s/grafana-configmap.yaml#L12)

- Review provisioning mounts and dashboard ConfigMap integration.
  [`grafana-deployment.yaml:55`](../../deploy/k8s/grafana-deployment.yaml#L55)

- Validate dashboard payload is embedded for no-manual-import startup.
  [`grafana-dashboard-configmap.yaml:1`](../../deploy/k8s/grafana-dashboard-configmap.yaml#L1)

**Network Enforcement**

- Verify Prometheus and Grafana policies under default-deny model.
  [`networkpolicy.yaml:137`](../../deploy/k8s/networkpolicy.yaml#L137)

**Operations Runbook**

- Confirm docs now reflect built-in monitoring deployment flow.
  [`deploy.md:3`](../../docs/operations/deploy.md#L3)

- Confirm monitoring access and validation commands for operators.
  [`deploy.md:84`](../../docs/operations/deploy.md#L84)
