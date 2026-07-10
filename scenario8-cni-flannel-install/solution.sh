#!/usr/bin/env bash
# Scenario 8 — answer key: install flannel, reconcile its net-conf Network to the cluster
# pod CIDR (192.168.0.0/16), restart the flannel pods, get the nodes Ready, and prove
# pod-to-pod connectivity across nodes.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario8"
CTX="kind-${CLUSTER}"
NS="kube-flannel"
K="kubectl --context ${CTX}"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }

echo "▶ Installing flannel from the provided manifest (net-conf Network 10.244.0.0/16)"
$K apply -f manifests/kube-flannel.yml

echo "▶ Giving flannel a moment to try (and fail) to acquire a lease…"
sleep 15
echo "  flannel pods (expect CrashLoopBackOff/Error — CIDR mismatch):"
$K -n "$NS" get pods -o wide || true
echo
echo "  why (from a flannel pod's logs):"
POD="$($K -n "$NS" get pods -l app=flannel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -n "$POD" ] && $K -n "$NS" logs "$POD" 2>/dev/null | grep -iE 'lease|net configuration|CIDR|192.168|10.244' | head -5 || true

echo
echo "▶ Fixing the mismatch: set net-conf.json Network to the cluster pod CIDR (192.168.0.0/16)"
# The exam way is `kubectl edit configmap kube-flannel-cfg -n kube-flannel` and change the
# Network line. Non-interactively that's the same single substitution, replacing the whole
# object so every other key (cni-conf.json) is preserved:
$K -n "$NS" get configmap kube-flannel-cfg -o json \
  | sed 's#10\.244\.0\.0/16#192.168.0.0/16#' \
  | $K replace -f -
echo "  net-conf.json now:"
$K -n "$NS" get configmap kube-flannel-cfg -o jsonpath='{.data.net-conf\.json}'; echo

echo "▶ Restarting the flannel pods so they re-read the config"
$K -n "$NS" delete pod -l app=flannel --ignore-not-found
$K -n "$NS" rollout status ds/kube-flannel-ds --timeout=150s

echo "▶ Waiting for all nodes to become Ready"
$K wait --for=condition=Ready nodes --all --timeout=150s
$K -n kube-system rollout status deploy/coredns --timeout=150s || true
echo
$K get nodes

echo
echo "▶ Proving pod-to-pod connectivity across nodes (test1 on the worker, test2 on the control-plane)"
$K apply -f manifests/connectivity-test.yaml
$K wait --for=condition=Ready pod/test1 pod/test2 --timeout=120s
$K get pods -o wide -l app=conn-test
IP2="$($K get pod test2 -o jsonpath='{.status.podIP}')"
echo "  ping test2 (${IP2}) from test1:"
if $K exec test1 -- ping -c 3 "$IP2"; then
  echo
  echo "✅ Done: flannel installed + reconciled to the cluster CIDR, nodes Ready, pods can talk across the overlay."
else
  echo
  echo "❌ Cross-node ping failed — flannel may still be settling; re-check 'kubectl -n ${NS} get pods'."
  exit 1
fi
