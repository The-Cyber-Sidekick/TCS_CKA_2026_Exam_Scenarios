# Scenario 8 — Install a CNI (flannel) and fix the pod-CIDR mismatch

A self-contained CKA **Services & Networking** lesson, taken from a real 2025/2026 exam
question. The cluster is up but every node is **NotReady**, because no CNI is installed.
You're handed a flannel manifest and told to install a network plugin. The catch: a
straight `kubectl apply` **CrashLoops**, because the manifest ships `net-conf.json` with
`Network: 10.244.0.0/16` while this cluster's pod CIDR is `192.168.0.0/16`. You have to
read the error, reconcile flannel's `Network` to the cluster CIDR, restart the pods, and
prove pods can talk across nodes.

It runs on its own dedicated **two-node** kind cluster (`cka-scenario8`) built with
`disableDefaultCNI: true`. This is a **host-side** lesson — plain `kubectl` from the
workstation, the same style as scenarios 2, 3, 5, 6, and 7.

> **Which CNI?** The exam lets you pick (flannel or Calico). This scenario does flannel,
> the shorter path. The lesson isn't really about flannel; it's about the pod-CIDR vs
> plugin-Network mismatch, which bites the same way whichever plugin you choose.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Two-node cluster `cka-scenario8`, **no default CNI**, pod CIDR `192.168.0.0/16` |
| `manifests/kube-flannel.yml` | The provided flannel manifest (v0.28.5), `Network: 10.244.0.0/16` — the mismatch |
| `manifests/connectivity-test.yaml` | `test1` (worker) + `test2` (control-plane) busybox pods for a cross-node ping |
| `setup.sh` | Create the CNI-less cluster and arm the unsolved state (nodes NotReady) |
| `solution.sh` | Answer key — install flannel, fix the CIDR, restart, verify Ready + cross-node ping |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores any generated scratch output |

## Quick start

```bash
cd scenario8-cni-flannel-install
./setup.sh        # create cka-scenario8 (no CNI); nodes come up NotReady
# solve it by hand, or:
./solution.sh     # install flannel, fix the CIDR, verify + ping
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the armed state**: two nodes, no CNI, so
nodes are NotReady and CoreDNS is Pending, with the flannel manifest waiting in
`manifests/`. It is re-runnable (it removes any flannel install and test pods from a
previous solve, resetting to the unsolved state).

## The task

1. Install a CNI plugin from the provided **`manifests/kube-flannel.yml`**.
2. The flannel pods **CrashLoop** — read the logs to find out why.
3. Reconcile flannel's `net-conf.json` `Network` to the cluster pod CIDR (`192.168.0.0/16`).
4. Restart the flannel pods, get all nodes **Ready**, and **prove pod-to-pod connectivity**.

## Solving it by hand

```bash
CTX=kind-cka-scenario8 ; NS=kube-flannel

# 1) confirm the symptom: no CNI -> NotReady nodes, Pending CoreDNS
kubectl --context $CTX get nodes
kubectl --context $CTX get pods -n kube-system

# 2) install flannel; the pods CrashLoop
kubectl --context $CTX apply -f manifests/kube-flannel.yml
kubectl --context $CTX -n $NS get pods -o wide

# 3) read WHY: pod subnet (192.168.x.0/24) not in flannel's Network (10.244.0.0/16)
kubectl --context $CTX -n $NS logs -l app=flannel --tail=20

# 4) fix the ConfigMap so Network matches the cluster pod CIDR, then restart the pods
kubectl --context $CTX -n $NS edit configmap kube-flannel-cfg   # Network -> 192.168.0.0/16
kubectl --context $CTX -n $NS delete pod -l app=flannel
kubectl --context $CTX wait --for=condition=Ready nodes --all --timeout=150s

# 5) prove it: two pods on different nodes, ping across the overlay
kubectl --context $CTX apply -f manifests/connectivity-test.yaml
kubectl --context $CTX wait --for=condition=Ready pod/test1 pod/test2 --timeout=120s
kubectl --context $CTX get pods -o wide -l app=conn-test
kubectl --context $CTX exec test1 -- ping -c 3 "$(kubectl --context $CTX get pod test2 -o jsonpath='{.status.podIP}')"
```

## Why it works (and the traps)

- **NotReady nodes + Pending CoreDNS = no CNI.** The kubelet marks a node NotReady until a
  network plugin is providing pod networking, and CoreDNS can't schedule onto a network
  that doesn't exist yet. Installing a CNI is step one.
- **`apply` is necessary but not sufficient.** Always check the plugin's pods actually
  reach `Running`. Here they don't, and assuming the apply "worked" is the trap.
- **`failed to acquire lease` is a CIDR mismatch.** flannel runs with `--kube-subnet-mgr`,
  so it reads each node's `spec.podCIDR` (a slice of the cluster's `192.168.0.0/16`) and
  refuses to start when that subnet isn't inside its configured `Network`
  (`10.244.0.0/16`). The cluster CIDR is fixed at `kubeadm init` time, so **flannel** is
  what changes: set `net-conf.json` `Network` to `192.168.0.0/16`.
- **A ConfigMap edit doesn't restart pods.** The DaemonSet keeps running the old config
  until you cycle the pods (`delete pod -l app=flannel`, or `rollout restart ds`), so they
  re-read the corrected `Network`.
- **Verify networking, not just pod status.** Green flannel pods aren't proof. Two pods on
  different nodes plus a successful ping shows the vxlan overlay actually carries traffic
  between hosts.
- **kind specifics.** flannel's CNI conflist delegates to the reference `bridge` plugin, but
  the kind node image ships only `ptp/host-local/portmap/loopback` (kindnet uses `ptp`). A
  real kubeadm node has `bridge` from the `containernetworking-plugins` package, so `setup.sh`
  drops the `bridge` binary into `/opt/cni/bin` on each node. Without it pods fail with
  `failed to find plugin "bridge"` — an environment artifact unrelated to the CIDR lesson.
