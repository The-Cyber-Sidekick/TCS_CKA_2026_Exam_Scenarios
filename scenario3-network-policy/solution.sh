#!/usr/bin/env bash
# Scenario 3 — answer key: apply the correct least-permissive policy and verify the
# frontend can now reach the backend (while the default-deny stays in place).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario3"
CTX="kind-${CLUSTER}"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }

echo "▶ Applying netpol2 (allow ingress from frontend pods, namespace + podSelector ANDed, port 80)"
kubectl --context "$CTX" apply -f netpol/netpol2-allow-frontend.yaml

echo "▶ Backend policies now (default-deny left untouched, allow-frontend added):"
kubectl --context "$CTX" -n backend get networkpolicy

echo "▶ Probing the backend from the frontend pod..."
if kubectl --context "$CTX" -n frontend exec deploy/frontend -- \
     wget -T 5 -qO- http://backend.backend.svc.cluster.local | grep -qi "Welcome to nginx"; then
  echo
  echo "✅ Recovered: frontend reached the backend through the allow policy."
else
  echo
  echo "❌ Still blocked — check the policy selectors and that Calico is Ready."
  exit 1
fi
