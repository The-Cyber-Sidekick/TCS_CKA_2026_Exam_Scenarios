#!/usr/bin/env bash
# Scenario 1 — inject the fault: point kube-apiserver at a wrong etcd endpoint.
# The kubelet reloads the static pod and the apiserver crashloops, so the whole
# control plane looks dead. This is the "post-migration wrong etcd address" bug.
set -euo pipefail

CLUSTER="${CLUSTER:-cka-scenario1}"
NODE="${CLUSTER}-control-plane"
MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
# Wrong port on localhost = immediate "connection refused" (fast, deterministic).
# For the "wrong host IP / i-o timeout" variant from the migration story, set
# BAD_ETCD=https://10.2.0.14:2379 before running.
BAD_ETCD="${BAD_ETCD:-https://127.0.0.1:2399}"

docker inspect "$NODE" >/dev/null 2>&1 || { echo "❌ node '$NODE' not found — run ./setup.sh first"; exit 1; }

# Back up the pristine manifest once so solution.sh / teardown can restore it.
docker exec "$NODE" sh -c "[ -f /root/kube-apiserver.yaml.orig ] || cp $MANIFEST /root/kube-apiserver.yaml.orig"

# Inject the fault silently — the learner should diagnose what broke, not be told.
docker exec "$NODE" sed -i "s#\(--etcd-servers=https://\)[^[:space:]]*#\1${BAD_ETCD#https://}#" "$MANIFEST"
