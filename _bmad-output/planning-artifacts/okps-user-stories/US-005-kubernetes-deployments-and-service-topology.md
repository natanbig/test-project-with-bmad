# US-005: Kubernetes Deployments and Service Topology

## User Story
As a platform engineer, I want deployable Kubernetes manifests for producer, collector, and consumer tiers so that the full pipeline can run and scale in-cluster.

## Acceptance Criteria

- Namespace manifest is provided for deployment isolation.
- Deployments exist for producer, collector, and consumer with replica configuration.
- Collector ClusterIP service exposes OTLP gRPC on 4317.
- Consumer headless service is configured for endpoint discovery.
- ConfigMaps and Secrets are wired for runtime configuration.
- Manifests pass schema validation and server-side dry-run.

## Files to Create

- deploy/k8s/namespace.yaml
- deploy/k8s/producer-deployment.yaml
- deploy/k8s/collector-deployment.yaml
- deploy/k8s/consumer-deployment.yaml
- deploy/k8s/collector-service.yaml
- deploy/k8s/consumer-headless-service.yaml
- deploy/k8s/configmap.yaml
- deploy/k8s/secret.example.yaml

## Files to Change

- deploy/collector/collector-config.yaml
- README.md
- docs/operations/deploy.md

## Dependencies

- US-002
- US-003
- US-004
