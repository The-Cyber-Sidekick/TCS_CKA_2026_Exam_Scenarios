#!/usr/bin/env bash
# Scenario 10 — answer key: add the argo Helm repo, render the template with
# crds.install=false, install the release the same way, then hit the lab's trap —
# the "pre-installed" CRDs aren't actually there, so argocd-server & friends
# crashloop with "the server could not find the requested resource". Diagnose it,
# install the pinned v2.13.0 CRDs (matching chart 7.7.3's appVersion), rollout
# restart, and verify everything Running.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario10"
CTX="kind-${CLUSTER}"
K="kubectl --context ${CTX}"
H="helm --kube-context ${CTX}"
CHART_VERSION="7.7.3"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }
[ -s manifests/crds/application-crd.yaml ] || { echo "❌ CRD manifests missing — run ./setup.sh first"; exit 1; }

echo "▶ 1) Add the official Argo CD Helm repository as 'argo'"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo list

echo
echo "▶ 2) Render the Helm template (crds.install=false) to argo-helm.yaml"
$H template argocd argo/argo-cd --version "$CHART_VERSION" --namespace argocd \
  --set crds.install=false > argo-helm.yaml
wc -l argo-helm.yaml
echo "  CustomResourceDefinition documents in the template: $(grep -c '^kind: CustomResourceDefinition' argo-helm.yaml || true) (must be 0)"

echo
echo "▶ 3) Install release 'argocd' (same chart/version/namespace, no CRDs)"
$H install argocd argo/argo-cd --version "$CHART_VERSION" --namespace argocd \
  --set crds.install=false
$H ls -n argocd

echo
echo "▶ 4) The trap: the 'pre-installed' CRDs aren't there — pods crashloop"
echo "   waiting for the failure to surface (image pulls + first crashes take a minute)…"
BROKEN=""
for i in $(seq 1 60); do
  if $K get pods -n argocd --no-headers 2>/dev/null | grep -qE 'CrashLoopBackOff|Error'; then BROKEN="yes"; break; fi
  sleep 5
done
$K get pods -n argocd
if [ -z "$BROKEN" ]; then
  echo "⚠ pods never entered CrashLoopBackOff/Error — were the CRDs already installed?"
fi
echo
echo "  the crashing components all say the same thing (argocd-server shown):"
$K logs deploy/argocd-server -n argocd --tail=3 2>/dev/null | tail -3 || true

echo
echo "▶ 5) Diagnose + fix: no argoproj CRDs; install the ones matching the chart's appVersion"
$K get crd | grep argoproj || echo "  (no argoproj.io CRDs — the premise was false)"
$H show chart argo/argo-cd --version "$CHART_VERSION" | grep appVersion
$K apply -f manifests/crds/
$K get crd | grep argoproj

echo
echo "▶ 6) Restart the crashlooped workloads and verify"
$K -n argocd rollout restart deployment
$K -n argocd rollout restart statefulset argocd-application-controller >/dev/null 2>&1 || true
$K -n argocd rollout status deployment argocd-server --timeout=180s
# poll the pod table rather than `kubectl wait --all`: the one-shot redis-secret-init
# job pod never goes Ready, and old pods vanishing mid-rollout make wait error NotFound
all_running() {
  $K get pods -n argocd --no-headers 2>/dev/null \
    | awk '$3=="Completed" {next} {split($2,a,"/"); if (a[1]!=a[2] || $3!="Running") bad=1} END{exit bad}'
}
HEALTHY=""
for i in $(seq 1 60); do
  if all_running; then HEALTHY="yes"; break; fi
  sleep 5
done
$K get pods -n argocd
echo
$H ls -n argocd

echo
if [ -n "$HEALTHY" ]; then
  echo "✅ Done: repo added, template rendered CRD-free, release installed, missing CRDs"
  echo "   diagnosed and installed (${CHART_VERSION} -> v2.13.0), and every pod is Running."
else
  echo "❌ some argocd pods are still not Running/Ready"; exit 1
fi
