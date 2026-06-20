#!/usr/bin/env bash
# Scenario 2 — answer key: create the PVC, wire the deployment to it, verify recovery.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario2"
CTX="kind-${CLUSTER}"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }

echo "▶ Creating the PVC (binds to the retained PV via volumeName + empty storageClass)"
kubectl --context "$CTX" apply -f manifests/pvc.yaml

echo "▶ Waiting for the PVC to bind..."
kubectl --context "$CTX" -n mariadb wait --for=jsonpath='{.status.phase}'=Bound pvc/mariadb --timeout=60s

echo "▶ Applying the wired deployment (storage mounted at /var/lib/mysql)"
kubectl --context "$CTX" apply -f solution/deployment.yaml

echo "▶ Waiting for the rollout..."
kubectl --context "$CTX" -n mariadb rollout status deploy/mariadb --timeout=180s

echo
echo "✅ Recovered:"
kubectl --context "$CTX" get pv mariadb
kubectl --context "$CTX" -n mariadb get pvc,pods -o wide
