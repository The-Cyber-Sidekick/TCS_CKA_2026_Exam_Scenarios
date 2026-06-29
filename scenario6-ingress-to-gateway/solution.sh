#!/usr/bin/env bash
# Scenario 6 — answer key: create the Gateway + HTTPRoute that replace the existing
# Ingress, verify HTTPS still works through the Gateway, then delete the Ingress.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario6"
CTX="kind-${CLUSTER}"
NS="web"
HOST="gateway.web.k8s.local"
K="kubectl --context ${CTX}"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }

# curl the given edge IP over HTTPS for $HOST from the in-cluster tester pod, retrying
# while the data plane provisions. Echoes the body; returns non-zero if never "WEB APP OK".
probe() {
  local ip="$1" body
  for i in $(seq 1 20); do
    body="$($K -n "$NS" exec deploy/tester -- \
      curl -sk --max-time 10 --resolve "${HOST}:443:${ip}" "https://${HOST}/" 2>/dev/null || true)"
    if printf '%s' "$body" | grep -q "WEB APP OK"; then printf '%s' "$body"; return 0; fi
    sleep 3
  done
  printf '%s' "$body"; return 1
}

echo "▶ Creating the Gateway (gatewayClassName: eg, HTTPS listener for ${HOST})"
$K apply -f manifests/gateway.yaml
echo "▶ Creating the HTTPRoute web-route (/ -> web:80)"
$K apply -f manifests/httproute.yaml

echo "▶ Waiting for the Gateway to be Programmed"
$K -n "$NS" wait --for=condition=Programmed gateway/web-gateway --timeout=180s

# The Envoy data plane Service for this Gateway lives in envoy-gateway-system, labelled
# with the owning Gateway. Grab its ClusterIP to probe from inside the cluster.
echo "▶ Resolving the Envoy proxy Service for web-gateway"
EG_IP=""
for i in $(seq 1 20); do
  EG_IP="$($K -n envoy-gateway-system get svc \
    -l gateway.envoyproxy.io/owning-gateway-name=web-gateway \
    -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || true)"
  [ -n "$EG_IP" ] && [ "$EG_IP" != "None" ] && break
  sleep 3
done
[ -n "$EG_IP" ] || { echo "❌ could not find the Envoy proxy Service for web-gateway"; exit 1; }
echo "  proxy ClusterIP: ${EG_IP}"

echo "▶ Verifying HTTPS through the Gateway"
if probe "$EG_IP" | grep -q "WEB APP OK"; then
  echo "  ✓ Gateway serving: https://${HOST} -> 'WEB APP OK'"
else
  echo "❌ Gateway did not serve the expected page."
  exit 1
fi

echo "▶ Migration verified — deleting the now-redundant 'web' Ingress"
$K -n "$NS" delete ingress web --ignore-not-found

echo "▶ Re-verifying HTTPS still works through the Gateway after the Ingress is gone"
if probe "$EG_IP" | grep -q "WEB APP OK"; then
  echo "  ✓ Still serving over the Gateway"
  echo
  echo "✅ Done: traffic migrated from Ingress to the Gateway API, HTTPS preserved."
else
  echo "❌ Gateway stopped serving after the Ingress was deleted."
  exit 1
fi
