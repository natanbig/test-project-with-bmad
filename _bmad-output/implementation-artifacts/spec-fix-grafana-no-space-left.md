---
title: 'Fix Grafana Image Pull Failure: No Space Left on Device'
type: 'bugfix'
created: '2026-06-09T00:00:00Z'
status: 'done'
route: 'one-shot'
---

# Fix Grafana Image Pull Failure: No Space Left on Device

## Intent

**Problem:** The Grafana pod (`spec.containers{grafana}`) fails to start because containerd runs out of disk space while extracting `grafana/grafana:11.2.0` layers onto the overlayfs snapshotter (`no space left on device`). There is no tooling in the project to free node disk space without shelling into nodes manually.

**Approach:** Add a privileged DaemonSet-based prune script (`scripts/k8s-prune-node-images.sh`) that runs `crictl rmi --prune` inside each node's root namespace via `nsenter`, plus a `make k8s-prune-images` target. Running the target frees stale container images from all nodes, after which `make k8s-up` can pull and extract Grafana successfully.

## Suggested Review Order

1. [scripts/k8s-prune-node-images.sh](../../scripts/k8s-prune-node-images.sh) — new script: DaemonSet lifecycle, namespace validation, nsenter-based prune, cleanup trap
2. [Makefile](../../Makefile) — new `k8s-prune-images` target + `PRUNE_NS` variable
