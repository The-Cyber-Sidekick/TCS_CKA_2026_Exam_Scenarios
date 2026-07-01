#!/usr/bin/env bash
# Scenario 7 — create the dedicated kind cluster AND arm the scenario.
#
# Arming = the PREREQUISITES the exam hands you already running: the `autoscale`
# namespace, an `apache-server` Deployment (php-apache, with a CPU request so a
# utilization target has something to be a percentage of), and a working metrics-server
# (HPA reads CPU from it). There is NO HorizontalPodAutoscaler yet.
#
# Your job: create an HPA named `apache-server` targeting that Deployment, CPU target
# 50%, min 1 / max 4, with a 30s scaleDown stabilization window. Idempotent and
# re-runnable (re-applies the Deployment and removes any previously-created HPA,
# resetting to the unsolved state).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario7"
CTX="kind-${CLUSTER}"
NS="autoscale"
METRICS_SERVER_VERSION="v0.7.2"                  # kind-compatible metrics-server release
K="kubectl --context ${CTX}"

for cmd in docker kind kubectl; do
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

# ── metrics-server (HPA's CPU source) ────────────────────────────────────────
# kind's kubelet serves metrics with a self-signed cert, so metrics-server needs
# --kubelet-insecure-tls or it never becomes Available and every HPA shows <unknown>.
if $K -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  echo "✓ metrics-server already installed."
else
  echo "▶ Installing metrics-server (${METRICS_SERVER_VERSION})"
  $K apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"
fi
echo "▶ Patching metrics-server for kind (--kubelet-insecure-tls)"
if ! $K -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls'; then
  $K -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
echo "▶ Waiting for metrics-server to be Available"
$K -n kube-system rollout status deploy/metrics-server --timeout=180s

# ── namespace + the workload to be scaled ────────────────────────────────────
$K get ns "$NS" >/dev/null 2>&1 || $K create ns "$NS"
echo "▶ Arming: the apache-server Deployment + Service"
$K apply -f manifests/apache-app.yaml
# Reset to the UNSOLVED state: remove any HPA left by a previous solve.
$K -n "$NS" delete hpa apache-server --ignore-not-found >/dev/null 2>&1 || true

echo "▶ Waiting for the apache-server Deployment to be ready"
$K -n "$NS" rollout status deploy/apache-server --timeout=120s

# ── confirm metrics are flowing for the workload ─────────────────────────────
echo "▶ Waiting for metrics-server to report CPU for apache-server pods"
ok=""
for i in $(seq 1 20); do
  if $K -n "$NS" top pods >/dev/null 2>&1; then ok="yes"; break; fi
  sleep 5
done
[ -n "$ok" ] && { echo "  ✓ metrics available:"; $K -n "$NS" top pods 2>/dev/null; } \
             || echo "  ⚠ metrics not flowing yet (give metrics-server another ~30s, then 'kubectl -n ${NS} top pods')."

echo
echo "✅ Scenario armed. Prerequisites in place:"
$K -n "$NS" get deploy,svc
echo
echo "🧪 Task: create a HorizontalPodAutoscaler in the '${NS}' namespace."
echo "   • name:   apache-server"
echo "   • target: the apache-server Deployment"
echo "   • CPU:    50% average utilization per pod"
echo "   • scale:  minReplicas 1, maxReplicas 4"
echo "   • behavior: scaleDown stabilization window = 30 seconds"
echo
echo "   • ./solution.sh  — apply the answer key (autoscaling/v2 HPA) and verify"
