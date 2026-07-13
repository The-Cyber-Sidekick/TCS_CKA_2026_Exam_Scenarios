#!/usr/bin/env bash
# Scenario 9 — answer key: install Calico from the operator manifests (kubectl create,
# no Helm), wait for tigerastatus to go Available and the nodes Ready, prove pod-to-pod
# connectivity with a cross-node ping, then apply a default-deny NetworkPolicy and prove
# the same ping now FAILS (the enforcement flannel can't do).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario9"
CTX="kind-${CLUSTER}"
K="kubectl --context ${CTX}"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }
[ -s manifests/operator-crds.yaml ] && [ -s manifests/tigera-operator.yaml ] || { echo "❌ Calico manifests missing — run ./setup.sh first"; exit 1; }

# poll until every tigerastatus item reports Available=True (they don't exist until the
# operator creates them, so `kubectl wait --all` alone would error out early). jsonpath,
# NOT column parsing: while degraded the AVAILABLE column is blank and awk misreads it.
wait_tigerastatus() {
  for i in $(seq 1 120); do
    local status
    status="$($K get tigerastatus -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Available")].status};{end}' 2>/dev/null)" || status=""
    if echo "$status" | grep -q 'calico=True' \
       && ! echo "$status" | tr ';' '\n' | grep -qE '=(False)?$'; then
      return 0
    fi
    sleep 5
  done
  echo "❌ tigerastatus never became fully Available"; $K get tigerastatus || true; return 1
}

echo "▶ Installing the operator CRDs + the Tigera operator (kubectl create — the CRD file"
echo "  is too large for kubectl apply's last-applied annotation)"
$K create -f manifests/operator-crds.yaml >/dev/null
$K create -f manifests/tigera-operator.yaml
$K wait --for condition=Established crd/installations.operator.tigera.io --timeout=60s >/dev/null
$K -n tigera-operator rollout status deploy/tigera-operator --timeout=180s
$K get pods -n tigera-operator

echo
echo "▶ Creating the Installation resource (ipPool cidr 192.168.0.0/16 = the cluster pod CIDR)"
cat manifests/custom-resources.yaml
$K create -f manifests/custom-resources.yaml

echo
echo "▶ Waiting for the operator to bring Calico up (tigerastatus Available)…"
wait_tigerastatus
$K get tigerastatus

echo
echo "▶ Verifying: calico-system pods Running, nodes Ready"
$K wait --for=condition=Ready pod --all -n calico-system --timeout=300s >/dev/null || true
$K wait --for=condition=Ready nodes --all --timeout=180s
$K -n kube-system rollout status deploy/coredns --timeout=150s || true
$K -n calico-system get pods -o wide
echo
$K get nodes

echo
echo "▶ Requirement 2 — pods must communicate: cross-node ping between two test pods"
$K apply -f manifests/connectivity-test.yaml
$K wait --for=condition=Ready pod/test1 pod/test2 --timeout=120s
$K get pods -o wide -l app=conn-test
IP2="$($K get pod test2 -o jsonpath='{.status.podIP}')"
echo "  ping test2 (${IP2}) from test1:"
$K exec test1 -- ping -c 3 "$IP2"

echo
echo "▶ Requirement 3 — NetworkPolicy enforcement: apply default-deny, same ping must FAIL"
$K apply -f manifests/deny-all.yaml
$K get networkpolicy
# give felix a moment to program the dataplane, then the ping must fail
BLOCKED=""
for i in $(seq 1 12); do
  if ! $K exec test1 -- ping -c 1 -w 3 "$IP2" >/dev/null 2>&1; then BLOCKED="yes"; break; fi
  sleep 3
done
if [ -n "$BLOCKED" ]; then
  echo "  ping test2 (${IP2}) from test1 with default-deny in place:"
  $K exec test1 -- ping -c 3 -w 5 "$IP2" || true
  echo
  echo "✅ Done: Calico installed from manifests, nodes Ready, pods talked, and the"
  echo "   default-deny NetworkPolicy is actually enforced (ping now 100% loss)."
else
  echo "❌ The ping still succeeds — Calico is not enforcing the NetworkPolicy."
  exit 1
fi
