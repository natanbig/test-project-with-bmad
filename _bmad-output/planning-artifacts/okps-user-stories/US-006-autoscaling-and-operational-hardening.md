# US-006: Autoscaling and Operational Hardening

## User Story
As an SRE, I want autoscaling and operational safeguards across all tiers so that the pipeline remains stable during burst load and rolling updates.

## Acceptance Criteria

- HPA is configured for collector and consumer tiers, with optional producer HPA.
- Readiness and liveness probes are defined for all deployments.
- PodDisruptionBudget exists for collector tier.
- Resource requests and limits are set for all workloads.
- Rolling update strategy avoids full service interruption.
- NetworkPolicy restricts traffic to required ports and tiers.

## Files to Create

- deploy/k8s/hpa-producer.yaml
- deploy/k8s/hpa-collector.yaml
- deploy/k8s/hpa-consumer.yaml
- deploy/k8s/pdb-collector.yaml
- deploy/k8s/networkpolicy.yaml

## Files to Change

- deploy/k8s/producer-deployment.yaml
- deploy/k8s/collector-deployment.yaml
- deploy/k8s/consumer-deployment.yaml
- docs/operations/deploy.md

## Dependencies

- US-005
