#!/usr/bin/env bash
# Scenario 3 — create the dedicated kind cluster (Calico CNI) AND arm the scenario.
# Arming = frontend + backend deployments/services up, the backend locked down by a
# default-deny ingress policy, and the three candidate policies left UNAPPLIED in
# netpol/. Your job is to pick and apply the right one.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario3"
CTX="kind-${CLUSTER}"
CALICO_VERSION="v3.28.2"

for cmd in docker kind kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER' (default CNI disabled)"
  kind create cluster --config kind-config.yaml --wait 120s
fi

# Install Calico so NetworkPolicy is actually enforced (kindnet is disabled).
if kubectl --context "$CTX" -n kube-system get daemonset calico-node >/dev/null 2>&1; then
  echo "✓ Calico already installed."
else
  echo "▶ Installing Calico ${CALICO_VERSION} (NetworkPolicy enforcement)"
  kubectl --context "$CTX" apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
fi
echo "▶ Waiting for Calico + nodes to be Ready (CNI must be up before pods schedule)"
kubectl --context "$CTX" -n kube-system rollout status daemonset/calico-node --timeout=240s
kubectl --context "$CTX" wait --for=condition=Ready node --all --timeout=180s

echo "▶ Arming: frontend + backend workloads, then lock the backend down"
kubectl --context "$CTX" get ns frontend >/dev/null 2>&1 || kubectl --context "$CTX" create ns frontend
kubectl --context "$CTX" get ns backend  >/dev/null 2>&1 || kubectl --context "$CTX" create ns backend
kubectl --context "$CTX" apply -f manifests/backend.yaml
kubectl --context "$CTX" apply -f manifests/frontend.yaml
kubectl --context "$CTX" apply -f manifests/default-deny.yaml

# Make setup re-runnable: clear any candidate policy a previous solve applied, so the
# backend always starts blocked again.
kubectl --context "$CTX" -n backend delete networkpolicy allow-frontend allow-frontend-namespace deny-frontend --ignore-not-found

echo "▶ Waiting for the workloads to be ready"
kubectl --context "$CTX" -n backend  rollout status deploy/backend  --timeout=120s
kubectl --context "$CTX" -n frontend rollout status deploy/frontend --timeout=120s

echo
echo "✅ Scenario armed. Current state:"
kubectl --context "$CTX" -n backend get deploy,svc,networkpolicy
kubectl --context "$CTX" -n frontend get deploy
echo
echo "🧪 Task: the frontend must reach the backend Service, but a default-deny ingress"
echo "   policy in the 'backend' namespace blocks it. Three candidate policies sit in"
echo "   netpol/. Review them and apply ONLY the one that is correct and least"
echo "   permissive. Do NOT modify or delete the existing default-deny policy."
echo
echo "   • ./solution.sh  — apply the answer key (netpol2) and verify connectivity"
echo "   • ./run-demo.sh  — capture the lesson's real output for the video"
