#!/usr/bin/env bash
# Scenario 4 — create the dedicated kind cluster and ARM the lesson (idempotent).
#
# The kind control-plane node is our throwaway Debian-bookworm "exam box". This
# lesson is node/system-level prep, so we operate on it with `docker exec`, not
# kubectl. setup.sh leaves the box in the BEFORE state: cri-dockerd NOT installed
# and the k8s sysctl/modules files absent, so one command hands you an unprepared
# node to fix (re-runnable: it undoes any previous solve).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario4"
NODE="${CLUSTER}-control-plane"

for cmd in docker kind kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER'"
  kind create cluster --config kind-config.yaml --wait 120s
fi

# kind nodes are minimal: make sure the tools the lesson uses are present
# (best-effort; needs network). wget downloads the .deb, kmod gives modprobe,
# vim is there if you want to edit the sysctl file by hand instead of cp.
echo "▶ Ensuring node tools (wget, kmod, vim, ca-certificates)"
docker exec "$NODE" bash -c '
  command -v wget >/dev/null 2>&1 && command -v modprobe >/dev/null 2>&1 && command -v vim >/dev/null 2>&1 && exit 0
  apt-get update -qq && apt-get install -y -qq wget kmod vim ca-certificates >/dev/null 2>&1
' && echo "  ✓ tools present" \
  || echo "  ⚠️ tool install failed (offline?) — run-demo.sh may not be able to wget the .deb"

# Mirror the EXAM PREMISE ("Docker is already installed on this node"). A real exam
# box has Docker Engine, which (a) creates the `docker` group the cri-docker socket
# runs under and (b) registers `containerd.io` in dpkg, satisfying the cri-dockerd
# package's runtime dependency. A kind node instead ships containerd as a binary
# (not via apt) and has no Docker, so we recreate that premise cleanly:
#   • create the `docker` group  -> cri-docker.socket can resolve its SocketGroup
#   • register the already-present containerd with dpkg via an equivs dummy
#     -> the lesson's plain `dpkg -i cri-dockerd.deb` resolves its dependency
# This keeps the captured lesson focused on the task (install the shim + sysctl),
# exactly as it would run on an exam box, with no --force flags on screen.
echo "▶ Establishing the exam premise (docker group + dpkg-registered containerd)"
docker exec "$NODE" bash -c '
  groupadd -f docker
  if ! dpkg -l containerd 2>/dev/null | grep -q "^ii"; then
    apt-get install -y -qq equivs >/dev/null 2>&1
    cd /tmp
    cat > containerd-present.ctl <<EOF
Section: misc
Priority: optional
Standards-Version: 3.9.2
Package: containerd
Version: 1.7.0
Provides: containerd
Description: Registers the container runtime this node already ships.
 The kind node runs containerd as a binary (not via apt); this records it in
 dpkg so the cri-dockerd package dependency resolves, the same way Dockers
 containerd.io would on a real exam node.
EOF
    equivs-build containerd-present.ctl >/dev/null 2>&1 && dpkg -i containerd_1.7.0_all.deb >/dev/null 2>&1
  fi
' && echo "  ✓ premise in place (docker group + containerd registered)" \
  || echo "  ⚠️ premise step failed (offline?) — dpkg -i may report a containerd dependency"

# ARM: return the box to the BEFORE state so the scenario is re-runnable.
echo "▶ Arming the scenario (unprepared node: no cri-dockerd, no k8s sysctl)"
docker exec "$NODE" bash -c '
  systemctl disable --now cri-docker.socket cri-docker.service >/dev/null 2>&1 || true
  dpkg --purge cri-dockerd >/dev/null 2>&1 || true
  rm -f /etc/sysctl.d/k8s.conf /etc/modules-load.d/k8s.conf
  sysctl --system >/dev/null 2>&1 || true
  rm -f /root/cri-dockerd.deb
'

echo
echo "🧪 Scenario armed. The node is unprepared. Then:"
echo "   • Prep it by hand   — docker exec -it ${NODE} bash   (see README for the task)"
echo "   • ./solution.sh     — apply the answer-key prep and verify"
