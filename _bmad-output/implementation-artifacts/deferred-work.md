# Deferred Work

- Consider replacing Grafana default `admin/admin` credentials with Kubernetes Secret-driven credentials in local deployment (`deploy/k8s/grafana-deployment.yaml`).
- Validate network policy behavior for Grafana/Prometheus ingress under the target CNI implementation and adjust host-originated access allowances if port-forward/health access is blocked.
