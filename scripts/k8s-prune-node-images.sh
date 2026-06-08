#!/usr/bin/env bash
# k8s-prune-node-images.sh — Prune unused container images from every cluster node.
#
# Deploys a privileged DaemonSet (busybox + nsenter) that runs
# `crictl rmi --prune` inside each node's root mount namespace,
# waits for completion, streams the per-node output, then deletes
# the DaemonSet.  On exit (success or error) the DaemonSet is always
# cleaned up via a trap.
#
# Usage:
#   ./scripts/k8s-prune-node-images.sh [namespace]
#
# Arguments:
#   namespace   Namespace for the transient DaemonSet (default: kube-system)
#
# Requirements:
#   - kubectl configured and pointing at the target cluster
#   - Kubernetes 1.18+ (DaemonSet, tolerations, nsenter-capable nodes)
#   - Nodes must allow privileged containers (standard in most dev clusters)

set -euo pipefail

PRUNE_NS="${1:-kube-system}"

# Validate namespace: must be a valid DNS label (prevent YAML injection).
if [[ ! "$PRUNE_NS" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "ERROR: '$PRUNE_NS' is not a valid Kubernetes namespace name." >&2
  exit 1
fi

DS_NAME="node-image-prune-$(date +%s)"

cleanup() {
  kubectl delete daemonset "$DS_NAME" -n "$PRUNE_NS" --ignore-not-found=true >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Deploying image-prune DaemonSet '$DS_NAME' in namespace '$PRUNE_NS' ..."

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: $DS_NAME
  namespace: $PRUNE_NS
  labels:
    app.kubernetes.io/name: $DS_NAME
    app.kubernetes.io/managed-by: okps-scripts
spec:
  selector:
    matchLabels:
      job: $DS_NAME
      app.kubernetes.io/managed-by: okps-scripts
  template:
    metadata:
      labels:
        job: $DS_NAME
        app.kubernetes.io/managed-by: okps-scripts
    spec:
      hostPID: true
      tolerations:
        - operator: Exists
      initContainers:
        - name: prune
          image: busybox:1.36
          securityContext:
            privileged: true
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          command: ["/bin/sh", "-c"]
          args:
            - |
              if ! nsenter --version >/dev/null 2>&1; then
                echo "ERROR: nsenter not found in this busybox build — cannot prune on node \$NODE_NAME" >&2
                exit 1
              fi
              echo "==> Pruning images on node: \$NODE_NAME"
              nsenter -t 1 -m -u -i -n -- crictl rmi --prune 2>&1 \
                || echo "  Warning: crictl rmi --prune returned non-zero (may be normal if nothing to prune)"
              echo "==> Done: \$NODE_NAME"
          volumeMounts:
            - name: host-run
              mountPath: /run
      containers:
        - name: done
          image: busybox:1.36
          command: ["sh", "-c", "sleep infinity"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
      terminationGracePeriodSeconds: 5
      volumes:
        - name: host-run
          hostPath:
            path: /run
            type: Directory
EOF

echo "Waiting for all nodes to complete image pruning (timeout 180s) ..."
kubectl rollout status daemonset/"$DS_NAME" -n "$PRUNE_NS" --timeout=180s

echo ""
echo "=== Per-node prune output ==="
kubectl logs \
  -l "job=${DS_NAME},app.kubernetes.io/managed-by=okps-scripts" \
  -n "$PRUNE_NS" -c prune --prefix=true 2>/dev/null \
  || kubectl logs \
       -l "job=${DS_NAME},app.kubernetes.io/managed-by=okps-scripts" \
       -n "$PRUNE_NS" --prefix=true 2>/dev/null \
  || echo "  (log retrieval failed — check pods manually in namespace '$PRUNE_NS')"
echo "============================="

echo ""
echo "Image prune complete. Re-run 'make k8s-up' to retry the Grafana deployment."
# DaemonSet cleanup is handled by the EXIT trap.
