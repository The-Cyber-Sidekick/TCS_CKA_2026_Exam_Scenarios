# Scenario 4 — Prepare a Node for kubeadm with cri-dockerd

A self-contained CKA **Cluster Architecture, Installation & Configuration** lesson, built
from the kind of exam question that has **no copy-paste manifest in the docs** — it is pure
Linux system administration. You prepare a node so `kubeadm` can use Docker as the container
runtime: install the **cri-dockerd** CRI shim, enable and start its service, set the kernel
parameters Kubernetes networking needs, and load them without a reboot.

It runs on its **own dedicated kind cluster** (`cka-scenario4`). The kind control-plane node is
a throwaway **Debian** box, and because this is node/system-level work we drive it with
`docker exec` (node-side), not `kubectl` — the same style as Scenario 1.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario4` (the Debian "exam box") |
| `setup.sh` | Create the cluster AND arm the lesson (unprepared node) |
| `solution.sh` | Answer key — install cri-dockerd, enable it, set + load sysctl, verify |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores any generated scratch output |

## Quick start

```bash
cd scenario4-cri-dockerd-system-prep
./setup.sh        # create cka-scenario4, stage config, AND arm it (needs Docker + kind in WSL2)
# prep it by hand, or:
./solution.sh     # install cri-dockerd, enable it, set + load the sysctl params, verify
./teardown.sh     # when done
```

`setup.sh` brings the box up in the **BEFORE** state: cri-dockerd is **not** installed and the
`k8s` sysctl/modules files are **absent**. It is re-runnable (it purges cri-dockerd and removes
the files, so the node starts unprepared again).

## The task

1. Install the **cri-dockerd** package with `dpkg -i` (on a real exam box the `.deb` is staged
   for you; here `solution.sh` fetches it from the releases page).
2. **Enable and start** cri-docker. The kubelet connects through the socket unit, so
   `systemctl enable --now cri-docker.socket`, and `enable` the service so it survives a reboot.
3. Create a persistent sysctl file (`/etc/sysctl.d/k8s.conf`) with the four required parameters:

   ```
   net.bridge.bridge-nf-call-iptables  = 1
   net.bridge.bridge-nf-call-ip6tables = 1
   net.ipv4.ip_forward                 = 1
   net.netfilter.nf_conntrack_max      = 131072
   ```
4. Load the settings **without rebooting** (`sysctl --system`) and **verify** each value.

## Solving it by hand

```bash
NODE=cka-scenario4-control-plane
docker exec -it $NODE bash         # drop into the Debian box

# 1) install the CRI shim
wget -q https://github.com/Mirantis/cri-dockerd/releases/download/v0.4.3/cri-dockerd_0.4.3.3-0.debian-bookworm_amd64.deb -O cri-dockerd.deb
dpkg -i cri-dockerd.deb            # also installs cri-docker.service + cri-docker.socket

# 2) enable + start it (the kubelet uses the SOCKET)
systemctl enable --now cri-docker.socket
systemctl enable cri-docker.service

# 3) kernel params (load the modules first, then persist the params)
modprobe br_netfilter nf_conntrack
printf 'br_netfilter\nnf_conntrack\n' > /etc/modules-load.d/k8s.conf
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.netfilter.nf_conntrack_max      = 131072
EOF

# 4) load without rebooting + verify
sysctl --system
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward net.netfilter.nf_conntrack_max
```

## Why these steps (and the traps)

- **`dpkg -i`, not `apt install`.** The package is given to you, so install it directly. If `dpkg`
  reports missing dependencies, run `apt-get install -f`; a single static package like cri-dockerd
  usually needs nothing.
- **The kubelet talks to the socket.** Enable `cri-docker.socket`, not just the service. The socket
  comes up `active (listening)` immediately; the service is socket-activated, so it starts the first
  time the kubelet connects. Enabling only the `.service` is the classic miss.
- **`br_netfilter` must be loaded first.** `net.bridge.bridge-nf-call-*` keys do not exist until the
  `br_netfilter` module is loaded (and `nf_conntrack_max` needs `nf_conntrack`). Writing the sysctl
  file without loading the modules makes `sysctl --system` silently skip those keys.
- **Persist in the right places.** `/etc/sysctl.d/` for params and `/etc/modules-load.d/` for modules
  survive a reboot; setting values only with `sysctl -w` does not.
- **Always verify.** A config file that is never loaded scores zero — finish with `sysctl --system`
  and read each value back.

> **On the kind node (faithful-reproduction notes):** a kind node already runs `containerd` and has no
> Docker, so `setup.sh` first recreates the exam's *"Docker is already installed"* premise — it creates
> the `docker` group (so `cri-docker.socket` can resolve its group and come up `active (listening)`) and
> registers the already-present containerd with dpkg via a tiny `equivs` dummy (so the lesson's plain
> `dpkg -i cri-dockerd.deb` resolves its dependency, exactly as Docker's `containerd.io` would on a real
> node — no `--force` flags on screen). We install cri-dockerd to practise the install/enable/sysctl
> drill; we do not point the kubelet at it or re-`kubeadm init` the node. One environment limit:
> `net.netfilter.nf_conntrack_max` is **read-only inside a container's network namespace**, so
> `sysctl --system` cannot *apply* that one key on the kind node (it still lands in the graded
> `/etc/sysctl.d/k8s.conf` artifact). The other three keys apply and verify live; on a real exam node
> the conntrack value applies too.
