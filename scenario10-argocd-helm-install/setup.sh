#!/usr/bin/env bash
# Scenario 10 — create the dedicated kind cluster AND arm the scenario.
#
# Arming = the state the exam hands you: a running cluster with an EMPTY `argocd`
# namespace, and the exam question (from a real 2025/2026 CKA question):
#
#   1. Add the official Argo CD Helm repository with the name `argo` to the cluster.
#      (The exam gives you the URL: https://argoproj.github.io/argo-helm)
#   2. The Argo CD CRDs "have already been pre-installed in the cluster".
#   3. Generate a Helm template for release `argocd`, chart argo/argo-cd version
#      7.7.3, namespace `argocd`, saved to argo-helm.yaml — configured NOT to
#      install the CRDs.
#   4. Install release `argocd` with the same chart/version/namespace, again NOT
#      installing the CRDs. You do NOT need to configure access to the Argo CD UI.
#
# The lab twist (same as the source walkthrough): premise 2 is FALSE here — a fresh
# cluster has no argoproj.io CRDs. So the crds.install=false install comes up with
# argocd-server & friends crashlooping ("the server could not find the requested
# resource"), and diagnosing that is the second half of the lesson. The pinned
# v2.13.0 CRD manifests (matching chart 7.7.3's appVersion) are downloaded into
# manifests/crds/ as the fix material.
#
# Idempotent and re-runnable: uninstalls any previous Argo CD release, removes the
# argoproj CRDs and the learner's argo-helm.yaml, removes the `argo` Helm repo, and
# recreates an empty `argocd` namespace — back to the unsolved state.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario10"
CTX="kind-${CLUSTER}"
K="kubectl --context ${CTX}"
H="helm --kube-context ${CTX}"
ARGOCD_VERSION="v2.13.0"   # = appVersion of chart argo/argo-cd 7.7.3
CRD_BASE="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/crds"

for cmd in docker kind kubectl helm curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

# ── the pinned CRD manifests (the fix material, downloaded once) ─────────────
fetch_crds() {
  mkdir -p manifests/crds
  for f in application-crd.yaml applicationset-crd.yaml appproject-crd.yaml; do
    if [ ! -s "manifests/crds/$f" ]; then
      echo "▶ Downloading manifests/crds/$f (Argo CD ${ARGOCD_VERSION})"
      curl -sSL "${CRD_BASE}/$f" -o "manifests/crds/$f"
      [ -s "manifests/crds/$f" ] || { echo "❌ download of $f failed"; exit 1; }
    fi
  done
  echo "✓ Argo CD ${ARGOCD_VERSION} CRD manifests present in manifests/crds/."
}

create_cluster() {
  echo "▶ Creating kind cluster '$CLUSTER' (single node, default CNI)"
  kind create cluster --config kind-config.yaml
}

# Fully return the cluster (and the host-side Helm state) to the unsolved state.
reset_argocd() {
  if $H status argocd -n argocd >/dev/null 2>&1; then
    echo "▶ Uninstalling the previous 'argocd' Helm release"
    $H uninstall argocd -n argocd --wait --timeout 3m >/dev/null 2>&1 || true
  fi
  $K delete ns argocd --ignore-not-found --wait --timeout=180s >/dev/null 2>&1 || true
  $K get crd -o name 2>/dev/null | grep 'argoproj\.io' \
    | xargs -r $K delete --timeout=90s >/dev/null 2>&1 || true
  # the learner's artifacts: the generated template + the added repo
  rm -f argo-helm.yaml
  helm repo remove argo >/dev/null 2>&1 || true
}

# ── manifests + cluster ──────────────────────────────────────────────────────
fetch_crds

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists."
else
  create_cluster
fi

# ── reset to the UNSOLVED state ──────────────────────────────────────────────
echo "▶ Resetting to the unsolved state (remove any Argo CD release, CRDs, repo, template)"
reset_argocd

echo "▶ Pre-creating the empty 'argocd' namespace (the exam provides it)"
$K create namespace argocd >/dev/null

echo
echo "✅ Scenario armed. Empty 'argocd' namespace, NO argoproj CRDs, no 'argo' Helm repo:"
echo
$K get ns argocd
$K get crd 2>/dev/null | grep argoproj || echo "  (no argoproj.io CRDs — the question's 'pre-installed' premise is false here, on purpose)"
echo
echo "🧪 Task (exam wording):"
echo "   1. Add the official Argo CD Helm repo as 'argo' (https://argoproj.github.io/argo-helm)."
echo "   2. helm template release 'argocd', chart argo/argo-cd version 7.7.3, namespace"
echo "      'argocd', saved to argo-helm.yaml — configure the chart to NOT install CRDs."
echo "   3. helm install the same release/chart/version/namespace, again without CRDs."
echo "      (No need to configure access to the Argo CD server UI.)"
echo "   …then figure out why the pods are crashlooping. manifests/crds/ has the fix."
echo
echo "   • ./solution.sh  — apply the answer key (repo, template, install, diagnose, fix)"
echo "   • ./run-demo.sh  — capture the lesson's real output for the video"
