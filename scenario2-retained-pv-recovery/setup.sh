#!/usr/bin/env bash
# Scenario 2 — create the dedicated kind cluster AND arm the scenario (idempotent).
# Arming = namespace + retained PV present, but the Deployment and its PVC are gone,
# exactly like a deployment someone deleted by accident on a Retain-policy volume.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario2"
CTX="kind-${CLUSTER}"

for cmd in docker kind kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER'"
  kind create cluster --config kind-config.yaml --wait 120s
fi

echo "▶ Arming: namespace + retained PV (Deployment & PVC intentionally absent)"
kubectl --context "$CTX" get ns mariadb >/dev/null 2>&1 || kubectl --context "$CTX" create ns mariadb
kubectl --context "$CTX" apply -f manifests/pv.yaml

# Simulate the accident: remove the Deployment and its claim. With Retain, the PV
# keeps the data but goes to "Released". Clear the stale claimRef so the PV is
# Available again and a fresh PVC can bind to it (this keeps setup re-runnable).
kubectl --context "$CTX" -n mariadb delete deploy mariadb --ignore-not-found
kubectl --context "$CTX" -n mariadb delete pvc mariadb --ignore-not-found
kubectl --context "$CTX" patch pv mariadb --type=merge -p '{"spec":{"claimRef":null}}' >/dev/null 2>&1 || true

echo
echo "✅ Scenario armed. Current state:"
kubectl --context "$CTX" get pv mariadb
kubectl --context "$CTX" -n mariadb get deploy,pvc,pods
echo
echo "🧪 Task: the 'mariadb' Deployment in namespace 'mariadb' was deleted. Its data"
echo "   lives on the retained PV 'mariadb'. Reconnect it:"
echo "     1) create PVC 'mariadb' (250Mi, ReadWriteOnce) bound to that PV"
echo "     2) edit manifests/deployment.yaml to mount the PVC at /var/lib/mysql"
echo "     3) apply it; the pod must be Running with no restarts"
echo
echo "   • ./solution.sh  — apply the answer key and verify recovery"
