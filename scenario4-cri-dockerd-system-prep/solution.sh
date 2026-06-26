#!/usr/bin/env bash
# Scenario 4 — answer key: install cri-dockerd, enable it, set + load the sysctl
# params, and verify. Runs node-side via `docker exec`.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="${CLUSTER:-cka-scenario4}"
NODE="${CLUSTER}-control-plane"
CRI_VER="${CRI_VER:-0.4.3}"
ARCH="$(docker exec "$NODE" dpkg --print-architecture 2>/dev/null || echo amd64)"
DEB="cri-dockerd_${CRI_VER}.3-0.debian-bookworm_${ARCH}.deb"
URL="https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_VER}/${DEB}"

docker inspect "$NODE" >/dev/null 2>&1 || { echo "❌ node '$NODE' not found — run ./setup.sh first"; exit 1; }

echo "▶ Installing cri-dockerd (${DEB})"
# Ensure the exam premise (docker group + dpkg-registered containerd) so plain
# `dpkg -i` resolves, the same as on a node with Docker already installed.
docker exec "$NODE" bash -c '
  groupadd -f docker
  if ! dpkg -l containerd 2>/dev/null | grep -q "^ii"; then
    apt-get install -y -qq equivs >/dev/null 2>&1
    cd /tmp
    printf "Package: containerd\nVersion: 1.7.0\nProvides: containerd\nDescription: registers the kind-shipped containerd with dpkg\n" > c.ctl
    equivs-build c.ctl >/dev/null 2>&1 && dpkg -i containerd_1.7.0_all.deb >/dev/null 2>&1
  fi
'
docker exec -w /root "$NODE" bash -euo pipefail -c "
  wget -q '${URL}' -O cri-dockerd.deb
  dpkg -i cri-dockerd.deb

  echo '▶ Enabling cri-docker (socket + service)'
  systemctl enable --now cri-docker.socket
  systemctl enable cri-docker.service

  echo '▶ Loading kernel modules + persisting them'
  modprobe br_netfilter nf_conntrack
  cat <<'MODS' | tee /etc/modules-load.d/k8s.conf
br_netfilter
nf_conntrack
MODS

  echo '▶ Writing + loading sysctl params'
  cat <<'SYSCTL' | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.netfilter.nf_conntrack_max      = 131072
SYSCTL
  sysctl --system >/dev/null
"

echo
echo "✅ Verifying:"
docker exec "$NODE" bash -c "
  systemctl is-enabled cri-docker.socket cri-docker.service
  systemctl is-active cri-docker.socket
  sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward net.netfilter.nf_conntrack_max
"
echo "✅ Node prepared for kubeadm."
