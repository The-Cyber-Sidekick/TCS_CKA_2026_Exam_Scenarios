#!/usr/bin/env bash
# Scenario 6 — create the dedicated kind cluster AND arm the scenario.
#
# Arming = the PREREQUISITES the exam hands you already running: an Ingress controller
# (ingress-nginx) serving an existing `web` Ingress over HTTPS for gateway.web.k8s.local,
# the web Deployment + Service behind it, the web-tls Secret, and the Gateway API stack
# (Envoy Gateway, GatewayClass `eg`) installed but with NO Gateway/HTTPRoute yet.
#
# Your job: recreate the Ingress's routing with a Gateway + HTTPRoute, verify HTTPS,
# then delete the Ingress. Idempotent and re-runnable (re-applies the Ingress and
# removes any previously-created Gateway/HTTPRoute, resetting to the unsolved state).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario6"
CTX="kind-${CLUSTER}"
NS="web"
HOST="gateway.web.k8s.local"
INGRESS_NGINX_REF="controller-v1.11.3"          # kind-compatible ingress-nginx release
ENVOY_GATEWAY_VERSION="v1.8.1"                   # matches the learning cluster
K="kubectl --context ${CTX}"

for cmd in docker kind kubectl openssl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

# ── cluster ──────────────────────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER'"
  kind create cluster --config kind-config.yaml --wait 120s
fi

# ── ingress-nginx (hosts the EXISTING Ingress) ───────────────────────────────
if $K -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  echo "✓ ingress-nginx already installed."
else
  echo "▶ Installing ingress-nginx (${INGRESS_NGINX_REF})"
  $K apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_REF}/deploy/static/provider/kind/deploy.yaml"
fi
echo "▶ Waiting for the ingress-nginx controller to be ready"
$K -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s

# ── Gateway API + Envoy Gateway (GatewayClass 'eg', NO Gateway yet) ───────────
if $K -n envoy-gateway-system get deploy envoy-gateway >/dev/null 2>&1; then
  echo "✓ Envoy Gateway already installed."
else
  echo "▶ Installing Envoy Gateway (${ENVOY_GATEWAY_VERSION}) + Gateway API CRDs"
  $K apply --server-side -f "https://github.com/envoyproxy/gateway/releases/download/${ENVOY_GATEWAY_VERSION}/install.yaml"
fi
$K -n envoy-gateway-system wait --for=condition=Available deploy/envoy-gateway --timeout=180s
# kind has no LoadBalancer; force the Envoy proxy Service to ClusterIP via an EnvoyProxy
# referenced by the GatewayClass, else the Gateway never programs (AddressNotAssigned).
echo "▶ Ensuring GatewayClass 'eg' is wired for kind (ClusterIP proxy)"
$K apply -f - <<'EOF'
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: kind-proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: ClusterIP
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: kind-proxy-config
    namespace: envoy-gateway-system
EOF

# ── namespace + TLS secret (self-signed, never committed) ─────────────────────
$K get ns "$NS" >/dev/null 2>&1 || $K create ns "$NS"
if ! $K -n "$NS" get secret web-tls >/dev/null 2>&1; then
  echo "▶ Generating self-signed cert and creating the web-tls Secret"
  TMP="$(mktemp -d)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$TMP/tls.key" -out "$TMP/tls.crt" \
    -subj "/CN=${HOST}" -addext "subjectAltName=DNS:${HOST}" >/dev/null 2>&1
  $K -n "$NS" create secret tls web-tls --cert="$TMP/tls.crt" --key="$TMP/tls.key"
  rm -rf "$TMP"
else
  echo "✓ Secret web-tls already present."
fi

# ── web app + Service + tester, and the EXISTING Ingress ─────────────────────
echo "▶ Arming: web app, Service, tester, and the existing Ingress"
$K apply -f manifests/web-app.yaml
$K apply -f manifests/ingress.yaml
# Reset to the UNSOLVED state: remove any Gateway/HTTPRoute left by a previous solve.
$K -n "$NS" delete httproute web-route --ignore-not-found >/dev/null 2>&1 || true
$K -n "$NS" delete gateway   web-gateway --ignore-not-found >/dev/null 2>&1 || true

echo "▶ Waiting for the workloads to be ready"
$K -n "$NS" rollout status deploy/web    --timeout=120s
$K -n "$NS" rollout status deploy/tester --timeout=120s

# ── confirm the EXISTING Ingress already serves HTTPS ────────────────────────
echo "▶ Confirming the existing Ingress serves HTTPS for ${HOST}"
ING_IP="$($K -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')"
ok=""
for i in $(seq 1 20); do
  if $K -n "$NS" exec deploy/tester -- \
       curl -sk --max-time 10 --resolve "${HOST}:443:${ING_IP}" "https://${HOST}/" 2>/dev/null | grep -q "WEB APP OK"; then
    ok="yes"; break
  fi
  sleep 3
done
[ -n "$ok" ] && echo "  ✓ Ingress serving: https://${HOST} -> 'WEB APP OK'" \
             || echo "  ⚠ Ingress not answering yet (it may need another moment to admit the route)."

echo
echo "✅ Scenario armed. Prerequisites in place:"
$K -n "$NS" get deploy,svc,ingress
echo
$K get gatewayclass
echo
echo "🧪 Task: migrate the existing 'web' Ingress to the Gateway API, keeping HTTPS."
echo "   1. Create a Gateway (gatewayClassName: eg) with an HTTPS listener on 443 for"
echo "      ${HOST}, terminating TLS with the web-tls Secret."
echo "   2. Create an HTTPRoute 'web-route' for ${HOST} that forwards / to web:80."
echo "   3. Verify HTTPS works through the Gateway, then DELETE the 'web' Ingress."
echo
echo "   • ./solution.sh  — apply the answer key (Gateway + HTTPRoute), verify, delete Ingress"
