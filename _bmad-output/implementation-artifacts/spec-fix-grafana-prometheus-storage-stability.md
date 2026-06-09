---
title: 'Fix Grafana/Prometheus Monitoring Stability Under Node Disk Pressure'
type: 'bugfix'
created: '2026-06-09T00:00:00Z'
status: 'done'
baseline_commit: '1a0f8e5710d8f4a8c94622dee2f5c933e8b04d9f'
context:
  - '{project-root}/docs/operations/deploy.md'
  - '{project-root}/deploy/k8s/grafana-deployment.yaml'
  - '{project-root}/deploy/k8s/prometheus-deployment.yaml'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Local OKPS monitoring is unstable when cluster node storage is constrained: Grafana fails at startup with `no space left on device` when creating `/var/lib/grafana/png`, and Prometheus can crash with `SIGBUS` during active query tracker initialization.

**Approach:** Harden monitoring runtime storage behavior in Kubernetes manifests and operational flow so Grafana and Prometheus start reliably under constrained disk conditions, while keeping deployment scale conservative (`replicas: 1` for both services).

## Boundaries & Constraints

**Always:**
- Keep Grafana and Prometheus `replicas: 1`.
- Keep fix scope limited to local Kubernetes manifests, Makefile orchestration, and deployment runbook updates.
- Preserve existing monitoring topology (Prometheus service + Grafana provisioning + current dashboard ConfigMaps).
- Add explicit, bounded runtime-storage controls for Grafana and Prometheus to reduce disk-pressure sensitivity.

**Ask First:**
- Whether persistence beyond local/dev runtime is required now (PVC-backed monitoring state) or should stay ephemeral.
- Whether to add automatic pre-deploy image prune inside `make k8s-up` versus keeping prune as an explicit operator action.

**Never:**
- Increase monitoring replicas above 1 in this bugfix.
- Introduce Helm, operators, or cloud-managed monitoring dependencies.
- Refactor producer/collector/consumer application behavior as part of this monitoring stability fix.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| GRAFANA_STARTUP_UNDER_PRESSURE | Node has tight disk space; Grafana pod starts | Grafana reaches Ready without failing to create runtime directories/files | Pod restart policy remains standard; runbook points to prune + rollout checks if node remains saturated |
| PROMETHEUS_STARTUP_UNDER_PRESSURE | Node has tight disk space; Prometheus pod starts | Prometheus reaches Ready and does not crash with SIGBUS in active query tracker path | Bounded retention/runtime-path controls prevent crash-prone startup path; runbook includes recovery commands |
| DEPLOYMENT_RECOVERY_FLOW | Prior failed monitoring rollout exists | Operator runs documented prune/redeploy flow and monitoring pods recover to Ready | Commands are deterministic and include rollout status checks |

</frozen-after-approval>

## Code Map

- `deploy/k8s/grafana-deployment.yaml` -- Grafana container env/volume behavior and replica count.
- `deploy/k8s/prometheus-deployment.yaml` -- Prometheus args/runtime paths/volume behavior and replica count.
- `Makefile` -- deployment and recovery orchestration (`k8s-up`, `k8s-prune-images`, rollout checks).
- `docs/operations/deploy.md` -- operator-facing recovery and validation flow.
- `scripts/k8s-prune-node-images.sh` -- node-level image pruning utility used for disk recovery.

## Tasks & Acceptance

**Execution:**
- [x] `deploy/k8s/grafana-deployment.yaml` -- keep `replicas: 1`; add explicit runtime-path storage handling for `/var/lib/grafana` (including png path behavior) to avoid startup failure under disk pressure -- ensures Grafana can initialize required runtime directories predictably.
- [x] `deploy/k8s/prometheus-deployment.yaml` -- keep `replicas: 1`; add bounded runtime-storage/query-tracker configuration (args and mounts) to prevent SIGBUS-prone startup under constrained node storage -- stabilizes Prometheus process initialization.
- [x] `Makefile` -- make recovery flow explicit and deterministic around `k8s-prune-images`, monitoring rollout restart, and rollout status verification -- improves repeatable operator recovery after storage-related failures.
- [x] `docs/operations/deploy.md` -- document exact troubleshooting and recovery sequence for Grafana no-space and Prometheus SIGBUS startup failures, including verification commands -- aligns runbook with implemented behavior.
- [x] `scripts/k8s-prune-node-images.sh` -- verify script messaging and behavior align with new runbook flow and monitoring recovery usage -- prevents operator ambiguity during incident recovery.

**Acceptance Criteria:**
- Given constrained node disk conditions, when Grafana starts, then it reaches Ready without `failed to create directory "/var/lib/grafana/png"` errors.
- Given constrained node disk conditions, when Prometheus starts, then it reaches Ready without `SIGBUS` crash in active query tracker initialization.
- Given `make k8s-up` deployment flow, when monitoring manifests are applied, then Prometheus and Grafana remain at `replicas: 1`.
- Given prior monitoring startup failures, when operator follows documented prune/redeploy steps, then monitoring deployments recover and `kubectl -n okps rollout status` passes for both services.
- Given the updated runbook, when users run verification commands, then they can confirm monitoring pod health and service accessibility consistently.

## Spec Change Log

## Design Notes

The fix should favor bounded runtime behavior over broad architecture changes:
- Keep deployment model unchanged (Deployments + ConfigMaps).
- Tighten runtime storage/retention/query-tracker settings only where startup instability was observed.
- Preserve current metrics and dashboard provisioning semantics.

## Verification

**Commands:**
- `kubectl apply --dry-run=client -f deploy/k8s/` -- expected: all manifests validate.
- `make k8s-prune-images` -- expected: per-node prune runs and completes without script failure.
- `make k8s-up` -- expected: deployments roll out successfully.
- `kubectl -n okps rollout status deploy/okps-prometheus` -- expected: successful rollout.
- `kubectl -n okps rollout status deploy/okps-grafana` -- expected: successful rollout.
- `kubectl -n okps get pods -l app.kubernetes.io/name=okps-prometheus` -- expected: Prometheus pod Ready, no crash loop.
- `kubectl -n okps get pods -l app.kubernetes.io/name=okps-grafana` -- expected: Grafana pod Ready.
- `kubectl -n okps logs deploy/okps-grafana --tail=200` -- expected: no png directory no-space startup error.
- `kubectl -n okps logs deploy/okps-prometheus --tail=200` -- expected: no SIGBUS/fault startup trace.

## Suggested Review Order

**Runtime storage hardening**

- Start where both startup failures are neutralized for Grafana runtime writes.
  [`grafana-deployment.yaml:57`](../../deploy/k8s/grafana-deployment.yaml#L57)

- Confirm Grafana data-path override aligns with mounted runtime volume.
  [`grafana-deployment.yaml:33`](../../deploy/k8s/grafana-deployment.yaml#L33)

- Validate Prometheus TSDB path bounds and retention constraints.
  [`prometheus-deployment.yaml:26`](../../deploy/k8s/prometheus-deployment.yaml#L26)

- Verify Prometheus now uses bounded writable volume at TSDB path.
  [`prometheus-deployment.yaml:63`](../../deploy/k8s/prometheus-deployment.yaml#L63)

**Recovery orchestration entrypoint**

- Review the new operator entrypoint for deterministic monitoring recovery.
  [`Makefile:111`](../../Makefile#L111)

- Check timeout guards and restart sequencing for non-hanging recovery runs.
  [`Makefile:118`](../../Makefile#L118)

**Runbook and operator guidance**

- Confirm recovery command is documented at deployment workflow entry.
  [`deploy.md:28`](../../docs/operations/deploy.md#L28)

- Validate troubleshooting signatures map directly to observed failure logs.
  [`deploy.md:213`](../../docs/operations/deploy.md#L213)

**Support script messaging**

- Ensure prune utility points operators to the new recovery command.
  [`k8s-prune-node-images.sh:121`](../../scripts/k8s-prune-node-images.sh#L121)
