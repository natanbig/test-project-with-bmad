---
title: 'Fix Kubernetes Consumer Image Pull Flow'
type: 'bugfix'
created: '2026-06-08T23:38:04+03:00'
status: 'done'
route: 'one-shot'
---

# Fix Kubernetes Consumer Image Pull Flow

## Intent

**Problem:** Kubernetes tried to pull `okps-consumer:dev` from Docker Hub because local images were not reliably built and rolled out before deployment, causing `ImagePullBackOff` for the consumer pod.

**Approach:** Add first-class local image build targets and make `k8s-up` build and restart producer/consumer deployments so rebuilt `:dev` images are present and actually picked up by pods.

## Suggested Review Order

**Deployment execution path**

- Make local image build a mandatory pre-step for cluster apply.
  [`Makefile:63`](../../Makefile#L63)

- Force producer/consumer restart so unchanged `:dev` tags still refresh running pods.
  [`Makefile:76`](../../Makefile#L76)

**Container build reliability**

- Build producer binary for target platform to avoid cross-arch runtime mismatch.
  [`Dockerfile.producer:11`](../../Dockerfile.producer#L11)

- Build consumer binary for target platform for consistent node runtime behavior.
  [`Dockerfile.consumer:11`](../../Dockerfile.consumer#L11)

- Keep Docker build context lean for faster, cleaner image builds.
  [`.dockerignore:1`](../../.dockerignore#L1)

**Operator guidance**

- Document one-step build+deploy and restart behavior in runbook.
  [`deploy.md:19`](../../docs/operations/deploy.md#L19)

- Pin collector validation image version for reproducible validation tooling.
  [`deploy.md:72`](../../docs/operations/deploy.md#L72)

- Mirror operational behavior in top-level project guidance.
  [`README.md:59`](../../README.md#L59)
