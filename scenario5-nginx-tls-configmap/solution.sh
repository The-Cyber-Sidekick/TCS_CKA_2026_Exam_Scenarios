#!/usr/bin/env bash
# Scenario 5 — answer key: tighten the ConfigMap to TLS 1.3 only, roll the Deployment,
# and verify that a TLS 1.2 handshake now fails while TLS 1.3 still serves the page.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario5"
CTX="kind-${CLUSTER}"
NS="nginx-static"
SVC="https://nginx-static.${NS}.svc.cluster.local"
EX="kubectl --context ${CTX} -n ${NS} exec deploy/tester --"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }

echo "▶ Updating ConfigMap nginx-config to allow ONLY TLS 1.3"
# In the exam you would `kubectl -n nginx-static edit configmap nginx-config` and change
# the ssl_protocols line in vi; recreating from the corrected file is equivalent (and
# annotation-free, so `get -o yaml | grep ssl_protocols` stays a single clean line).
kubectl --context "$CTX" -n "$NS" delete configmap nginx-config --ignore-not-found >/dev/null 2>&1
kubectl --context "$CTX" create -f manifests/configmap-tls13.yaml

echo "▶ Rolling the Deployment so nginx re-reads the ConfigMap"
kubectl --context "$CTX" -n "$NS" rollout restart deploy/nginx-static
kubectl --context "$CTX" -n "$NS" rollout status  deploy/nginx-static --timeout=120s

echo "▶ Verifying: TLS 1.2 must FAIL, TLS 1.3 must succeed"
# Give the Service a moment to drop the old (terminating) pod from its endpoints, so
# the probe hits the freshly rolled pod rather than briefly timing out.
sleep 3
if $EX curl -sk --max-time 10 --tlsv1.2 --tls-max 1.2 "$SVC" >/dev/null 2>&1; then
  echo "❌ TLS 1.2 still works — the ConfigMap change did not take effect."
  exit 1
fi
echo "  ✓ TLS 1.2 rejected"
if $EX curl -sk --max-time 10 "$SVC" | grep -qi "TLS OK"; then
  echo "  ✓ TLS 1.3 still serves the page"
  echo
  echo "✅ Done: nginx now accepts only TLS 1.3."
else
  echo "❌ TLS 1.3 request did not return the expected page."
  exit 1
fi
