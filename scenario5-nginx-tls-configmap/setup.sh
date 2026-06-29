#!/usr/bin/env bash
# Scenario 5 — create the dedicated kind cluster AND arm the scenario.
# Arming = an nginx-static Deployment serving HTTPS from a ConfigMap that currently
# allows BOTH TLS 1.2 and TLS 1.3, a Service in front of it, and a tester pod that
# can curl it. Your job is to tighten the ConfigMap to TLS 1.3 only and roll the
# Deployment so the change takes effect.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario5"
CTX="kind-${CLUSTER}"
NS="nginx-static"

for cmd in docker kind kubectl openssl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER'"
  kind create cluster --config kind-config.yaml --wait 120s
fi

kubectl --context "$CTX" get ns "$NS" >/dev/null 2>&1 || kubectl --context "$CTX" create ns "$NS"

# Self-signed cert/key for the nginx server, delivered as a TLS Secret. Generated
# here (not committed) so no private key lives in git. Idempotent: created only if
# the Secret is missing.
if ! kubectl --context "$CTX" -n "$NS" get secret nginx-tls >/dev/null 2>&1; then
  echo "▶ Generating self-signed cert and creating the nginx-tls Secret"
  TMP="$(mktemp -d)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$TMP/tls.key" -out "$TMP/tls.crt" \
    -subj "/CN=nginx-static.nginx-static.svc.cluster.local" >/dev/null 2>&1
  kubectl --context "$CTX" -n "$NS" create secret tls nginx-tls \
    --cert="$TMP/tls.crt" --key="$TMP/tls.key"
  rm -rf "$TMP"
else
  echo "✓ Secret nginx-tls already present."
fi

echo "▶ Arming: ConfigMap (TLS 1.2 + 1.3), Deployment, Service, tester"
# Recreate (not apply) the BASELINE configmap: it resets a previous solve's TLS-1.3-only
# state (re-runnable) AND avoids the last-applied-configuration annotation, so the
# lesson's `get -o yaml | grep ssl_protocols` returns one clean line.
kubectl --context "$CTX" -n "$NS" delete configmap nginx-config --ignore-not-found >/dev/null 2>&1
kubectl --context "$CTX" create -f manifests/configmap.yaml
kubectl --context "$CTX" apply -f manifests/deployment.yaml
kubectl --context "$CTX" apply -f manifests/tester.yaml

# If the Deployment already existed, force it to pick up the baseline ConfigMap.
kubectl --context "$CTX" -n "$NS" rollout restart deploy/nginx-static
echo "▶ Waiting for the workloads to be ready"
kubectl --context "$CTX" -n "$NS" rollout status deploy/nginx-static --timeout=120s
kubectl --context "$CTX" -n "$NS" rollout status deploy/tester       --timeout=120s

echo
echo "✅ Scenario armed. Current state:"
kubectl --context "$CTX" -n "$NS" get deploy,svc,configmap
echo
echo "🧪 Task: the nginx-static Deployment serves HTTPS using the 'nginx-config'"
echo "   ConfigMap, which currently allows TLS 1.2 AND 1.3. Update the ConfigMap so"
echo "   ONLY TLS 1.3 is allowed, then restart the Deployment so it takes effect."
echo "   A TLS 1.2 curl to the service must then fail."
echo
echo "   • ./solution.sh  — apply the answer key (TLS 1.3 only) and verify"
