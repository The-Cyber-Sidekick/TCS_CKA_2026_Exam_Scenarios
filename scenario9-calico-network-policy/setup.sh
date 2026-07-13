#!/usr/bin/env bash
# Scenario 9 — create the dedicated kind cluster AND arm the scenario.
#
# Arming = the state the exam hands you: a running cluster with NO CNI installed yet, so
# the nodes are NotReady and CoreDNS is Pending. The question: install and configure a
# CNI of your choice (flannel or Calico) from manifest files (no Helm), ensure it is
# properly installed, that pods can communicate with each other, AND that the CNI
# supports NetworkPolicy enforcement. That last requirement eliminates flannel (it does
# not enforce NetworkPolicy), so this is a Calico question.
#
# The pinned Calico operator manifests are downloaded into manifests/ ("the manifests the
# question gives you"). Idempotent and re-runnable: removes any Calico install, test pods,
# and NetworkPolicy from a previous solve, resetting to the unsolved state. If the
# in-place Calico uninstall doesn't fully take (finalizers etc.), it recreates the cluster.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario9"
CTX="kind-${CLUSTER}"
K="kubectl --context ${CTX}"
CALICO_VERSION="v3.30.3"
CALICO_BASE="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests"

for cmd in docker kind kubectl curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

# ── the provided manifests (pinned, downloaded once) ─────────────────────────
# operator-crds.yaml is ~2.6MB (32 CRDs) — too big to commit, and too big for
# `kubectl apply` (several CRDs exceed the 256KB last-applied annotation limit), which
# is why the lesson teaches `kubectl create`.
fetch_manifests() {
  for f in operator-crds.yaml tigera-operator.yaml; do
    if [ ! -s "manifests/$f" ]; then
      echo "▶ Downloading manifests/$f (Calico ${CALICO_VERSION})"
      curl -sSL "${CALICO_BASE}/$f" -o "manifests/$f"
      [ -s "manifests/$f" ] || { echo "❌ download of $f failed"; exit 1; }
    fi
  done
  echo "✓ Calico ${CALICO_VERSION} operator manifests present in manifests/."
}

create_cluster() {
  echo "▶ Creating kind cluster '$CLUSTER' (2 nodes, disableDefaultCNI, podSubnet 192.168.0.0/16)"
  # with no CNI the nodes never reach Ready, so kind's default readiness wait is moot.
  kind create cluster --config kind-config.yaml
}

# Fully return the cluster to the no-CNI state. The operator owns the teardown: delete
# the Installation and it removes calico-system; then remove the operator + CRDs. Calico
# leaves its CNI conflist on the nodes (which keeps the kubelet reporting Ready), so
# scrub the node-level artifacts too — the armed state must genuinely read NotReady.
reset_calico() {
  $K delete -f manifests/deny-all.yaml --ignore-not-found >/dev/null 2>&1 || true
  $K delete -f manifests/connectivity-test.yaml --ignore-not-found --now >/dev/null 2>&1 || true
  if $K get crd installations.operator.tigera.io >/dev/null 2>&1; then
    echo "▶ Removing the previous Calico install (operator-managed teardown)"
    $K delete installation default --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
    for i in $(seq 1 40); do
      $K get ns calico-system >/dev/null 2>&1 || break
      sleep 3
    done
    $K delete ns tigera-operator --ignore-not-found --wait --timeout=120s >/dev/null 2>&1 || true
    $K get crd -o name 2>/dev/null | grep -E '(projectcalico\.org|tigera\.io)' \
      | xargs -r $K delete --timeout=90s >/dev/null 2>&1 || true
  fi
  for n in $(kind get nodes --name "$CLUSTER" 2>/dev/null); do
    docker exec "$n" sh -c 'rm -f /etc/cni/net.d/10-calico.conflist /etc/cni/net.d/calico-kubeconfig 2>/dev/null; ip link del vxlan.calico 2>/dev/null; true' 2>/dev/null || true
    # nudge the kubelet so it re-evaluates network readiness promptly
    docker exec "$n" systemctl restart kubelet 2>/dev/null || true
  done
}

# block until every node reports NotReady (all nodes, not just the first)
wait_all_notready() {
  for i in $(seq 1 20); do
    local total nr
    total="$($K get nodes --no-headers 2>/dev/null | wc -l)"
    nr="$($K get nodes --no-headers 2>/dev/null | grep -c ' NotReady ')"
    [ "$total" -gt 0 ] && [ "$nr" -eq "$total" ] && return 0
    sleep 3
  done
  return 1
}

# ── manifests + cluster ──────────────────────────────────────────────────────
fetch_manifests

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists."
else
  create_cluster
fi

# ── reset to the UNSOLVED state ──────────────────────────────────────────────
echo "▶ Resetting to the unsolved state (remove any Calico install, test pods, policies)"
reset_calico

echo "▶ Waiting for the API server to be Ready and the nodes to report NotReady (no CNI)"
$K wait --for=condition=Ready pod -l component=kube-apiserver -n kube-system --timeout=120s >/dev/null 2>&1 || true
if ! wait_all_notready; then
  echo "⚠ In-place Calico removal didn't fully take — recreating the cluster for a clean slate"
  kind delete cluster --name "$CLUSTER"
  create_cluster
  wait_all_notready || true
fi

echo
echo "✅ Scenario armed. The cluster is up but has NO CNI yet:"
echo
$K get nodes
echo
echo "  (nodes are NotReady and CoreDNS is Pending — expected with no CNI installed)"
$K get pods -n kube-system -o wide 2>/dev/null | grep -E 'NAME|coredns' || true
echo
echo "🧪 Task: install and configure a CNI that supports NetworkPolicy enforcement."
echo "   • flannel or Calico — but 'must support NetworkPolicy enforcement' rules flannel out."
echo "   • Install Calico from manifests/ with kubectl create (operator-crds.yaml,"
echo "     tigera-operator.yaml, then custom-resources.yaml — ipPool cidr 192.168.0.0/16)."
echo "   • Get nodes Ready, prove pod-to-pod connectivity, then prove a default-deny"
echo "     NetworkPolicy actually blocks the same traffic."
echo
echo "   • ./solution.sh  — apply the answer key (install Calico, ping OK, deny-all, ping blocked)"
echo "   • ./run-demo.sh  — capture the lesson's real output for the video"
