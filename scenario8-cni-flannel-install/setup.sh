#!/usr/bin/env bash
# Scenario 8 — create the dedicated kind cluster AND arm the scenario.
#
# Arming = the state the exam hands you: a running cluster with NO CNI installed yet, so
# the nodes are NotReady and CoreDNS is Pending. The stock flannel manifest is sitting in
# manifests/ ("the manifest the question gives you"). Its net-conf.json Network is
# 10.244.0.0/16, but this cluster's pod CIDR is 192.168.0.0/16 — so a naive apply
# CrashLoops until you reconcile the two.
#
# Your job: install a CNI (flannel), make the flannel pods healthy, get the nodes Ready,
# and prove pod-to-pod networking works. Idempotent and re-runnable (removes any flannel
# install and test pods from a previous solve, resetting to the unsolved state).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario8"
CTX="kind-${CLUSTER}"
K="kubectl --context ${CTX}"
CNI_PLUGINS_VERSION="v1.5.1"                      # reference CNI plugins (for the 'bridge' binary)

for cmd in docker kind kubectl curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

# kind node prep: flannel's CNI conflist delegates to the reference `bridge` plugin, but
# the kind node image ships only ptp/host-local/portmap/loopback (kindnet uses ptp). On a
# real kubeadm node the containernetworking-plugins package provides `bridge` already, so
# we drop it in here — otherwise pods fail sandbox creation with 'failed to find plugin
# "bridge"', an environment artifact that would mask the intended pod-CIDR lesson.
ensure_bridge_plugin() {
  local nodes arch tmp need=""
  nodes="$(kind get nodes --name "$CLUSTER" 2>/dev/null)"
  for n in $nodes; do docker exec "$n" test -f /opt/cni/bin/bridge 2>/dev/null || need="yes"; done
  [ -z "$need" ] && { echo "✓ 'bridge' CNI plugin already present on all nodes."; return; }
  arch="$(docker exec "${CLUSTER}-control-plane" uname -m)"
  case "$arch" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; esac
  echo "▶ Installing the reference 'bridge' CNI plugin on the nodes (${CNI_PLUGINS_VERSION}, ${arch})"
  tmp="$(mktemp -d)"
  curl -sSL "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${arch}-${CNI_PLUGINS_VERSION}.tgz" -o "$tmp/cni.tgz"
  tar -xzf "$tmp/cni.tgz" -C "$tmp" ./bridge
  for n in $nodes; do
    docker cp "$tmp/bridge" "$n:/opt/cni/bin/bridge"
    docker exec "$n" chmod +x /opt/cni/bin/bridge
  done
  rm -rf "$tmp"
  echo "  ✓ bridge installed on all nodes."
}

# Fully return the nodes to the no-CNI state. flannel leaves its CNI conflist and vxlan
# interface behind when its pods are deleted, which keeps the kubelet reporting Ready — so
# a reset that only deletes the namespace would still show Ready. Scrub the node-level
# artifacts so the armed state genuinely reads NotReady, like a fresh node.
reset_node_cni() {
  for n in $(kind get nodes --name "$CLUSTER" 2>/dev/null); do
    docker exec "$n" sh -c 'rm -f /etc/cni/net.d/10-flannel.conflist /run/flannel/subnet.env 2>/dev/null; ip link del flannel.1 2>/dev/null; ip link del flannel-v6.1 2>/dev/null; true' 2>/dev/null || true
    # nudge the kubelet so it re-evaluates network readiness promptly (else a node can sit
    # on the stale "Ready" for a while after the CNI config is gone).
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
}

# ── cluster (no default CNI) ─────────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER' (2 nodes, disableDefaultCNI, podSubnet 192.168.0.0/16)"
  # --wait 0s: with no CNI the nodes never reach Ready, so don't block on it.
  kind create cluster --config kind-config.yaml
fi

# ── kind node prep (see note above) ──────────────────────────────────────────
ensure_bridge_plugin

# ── reset to the UNSOLVED state ──────────────────────────────────────────────
echo "▶ Resetting to the unsolved state (remove any flannel install + test pods)"
$K delete -f manifests/connectivity-test.yaml --ignore-not-found >/dev/null 2>&1 || true
$K delete namespace kube-flannel --ignore-not-found --wait >/dev/null 2>&1 || true
reset_node_cni

echo "▶ Waiting for the API server to be Ready and the nodes to report NotReady (no CNI)"
$K wait --for=condition=Ready pod -l component=kube-apiserver -n kube-system --timeout=120s >/dev/null 2>&1 || true
wait_all_notready

echo
echo "✅ Scenario armed. The cluster is up but has NO CNI yet:"
echo
$K get nodes
echo
echo "  (nodes are NotReady and CoreDNS is Pending — expected with no CNI installed)"
$K get pods -n kube-system -o wide 2>/dev/null | grep -E 'NAME|coredns' || true
echo
echo "🧪 Task: install and configure a CNI so the cluster networks."
echo "   • The flannel manifest is at manifests/kube-flannel.yml (net-conf Network 10.244.0.0/16)."
echo "   • This cluster's pod CIDR is 192.168.0.0/16 — reconcile the flannel config to match."
echo "   • Get the flannel pods Running, the nodes Ready, then prove pod-to-pod connectivity."
echo
echo "   • ./solution.sh  — apply the answer key (install flannel, fix the CIDR, verify + ping)"
echo "   • ./run-demo.sh  — capture the lesson's real output for the video"
