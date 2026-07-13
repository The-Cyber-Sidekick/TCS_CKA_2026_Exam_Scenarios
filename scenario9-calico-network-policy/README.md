# Scenario 9 — Install Calico and prove NetworkPolicy enforcement

A self-contained CKA **Services & Networking** lesson, taken from a real 2025/2026 exam
question. The cluster is up but every node is **NotReady**, because no CNI is installed.
The question offers **flannel or Calico**, says install from **manifest files (no Helm)**,
and lists three requirements: the CNI is properly installed and configured, **pods can
communicate with each other**, and it **supports NetworkPolicy enforcement**. That last
requirement is the whole exam trick: **flannel does not enforce NetworkPolicy**, so only
Calico satisfies the question.

It runs on its own dedicated **two-node** kind cluster (`cka-scenario9`) built with
`disableDefaultCNI: true` and pod CIDR `192.168.0.0/16` (matching Calico's default IP
pool — the CIDR *mismatch* lesson is [scenario 8](../scenario8-cni-flannel-install/)).
This is a **host-side** lesson — plain `kubectl` from the workstation, the same style as
scenarios 2, 3, 5, 6, 7, and 8.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Two-node cluster `cka-scenario9`, **no default CNI**, pod CIDR `192.168.0.0/16` |
| `manifests/operator-crds.yaml` | Pinned Calico v3.30.3 operator CRDs (downloaded by `setup.sh`, gitignored — 2.6MB) |
| `manifests/tigera-operator.yaml` | Pinned Tigera operator deployment (downloaded by `setup.sh`, gitignored) |
| `manifests/custom-resources.yaml` | The `Installation` resource — ipPool `cidr: 192.168.0.0/16` must match the cluster |
| `manifests/connectivity-test.yaml` | `test1` (worker) + `test2` (control-plane) busybox pods for the cross-node ping |
| `manifests/deny-all.yaml` | The default-deny NetworkPolicy (straight from the k8s docs) — the enforcement proof |
| `setup.sh` | Download the pinned manifests, create the CNI-less cluster, arm the unsolved state |
| `solution.sh` | Answer key — install Calico, verify, ping OK, apply deny-all, ping blocked |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores the large downloaded Calico manifests and any generated scratch output |

## Quick start

```bash
cd scenario9-calico-network-policy
./setup.sh        # download pinned manifests + create cka-scenario9 (no CNI); nodes NotReady
# solve it by hand, or:
./solution.sh     # install Calico, verify, ping OK, deny-all, ping blocked
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the armed state**: two nodes, no CNI, nodes
NotReady, CoreDNS Pending, with the Calico operator manifests waiting in `manifests/`. It
is re-runnable: it removes any Calico install, test pods, and NetworkPolicy from a
previous solve (operator-managed teardown + node scrub), and recreates the cluster if the
in-place removal doesn't fully take.

## The task

1. Pick the CNI: **"must support NetworkPolicy enforcement" eliminates flannel** → Calico.
2. Install Calico from the manifests with **`kubectl create`** (not `apply` — see traps):
   `operator-crds.yaml` → `tigera-operator.yaml` → `custom-resources.yaml`.
3. Watch **`kubectl get tigerastatus`** until everything is `Available`, nodes go **Ready**.
4. **Prove pods can communicate**: two pods on different nodes, cross-node ping succeeds.
5. **Prove enforcement**: apply the default-deny NetworkPolicy; the **same ping now fails**.

## Solving it by hand

```bash
CTX=kind-cka-scenario9
cd manifests

# 1) confirm the symptom: no CNI -> NotReady nodes, Pending CoreDNS, no CNI pods anywhere
kubectl --context $CTX get nodes
kubectl --context $CTX get pods -A

# 2) install the operator pieces (create, NOT apply — the CRD file is too big for apply)
kubectl --context $CTX create -f operator-crds.yaml
kubectl --context $CTX create -f tigera-operator.yaml
kubectl --context $CTX get pods -n tigera-operator

# 3) hand the operator the Installation (ipPool cidr = cluster pod CIDR 192.168.0.0/16)
kubectl --context $CTX create -f custom-resources.yaml
kubectl --context $CTX get tigerastatus          # repeat until everything is Available
kubectl --context $CTX get pods -n calico-system -o wide
kubectl --context $CTX get nodes                 # Ready

# 4) requirement 2: pods must communicate (cross-node ping by POD IP, not name)
kubectl --context $CTX apply -f connectivity-test.yaml
kubectl --context $CTX wait --for=condition=Ready pod/test1 pod/test2 --timeout=120s
IP2=$(kubectl --context $CTX get pod test2 -o jsonpath='{.status.podIP}')
kubectl --context $CTX exec test1 -- ping -c 3 "$IP2"          # works

# 5) requirement 3: NetworkPolicy enforcement — the same ping must now FAIL
kubectl --context $CTX apply -f deny-all.yaml
kubectl --context $CTX exec test1 -- ping -c 3 -w 5 "$IP2"     # 100% packet loss
```

## Why it works (and the traps)

- **The choice is the question.** flannel provides pod networking but **silently ignores
  NetworkPolicy objects** (they're stored in the API and enforced by nobody). The phrase
  "must support network policy enforcement" is the tell: pick Calico and move on.
- **`kubectl create`, not `apply`.** Several Calico CRDs are individually larger than the
  256KB `last-applied-configuration` annotation `kubectl apply` attaches, so `apply -f
  operator-crds.yaml` fails with "metadata.annotations: Too long". The Calico docs use
  `create` for exactly this reason.
- **The Installation's ipPool `cidr` must match the cluster pod CIDR.** Here both are
  `192.168.0.0/16` (Calico's default), but always check `--cluster-cidr` /
  `kubeadm-config` first — a mismatch is scenario 8's lesson in a different coat.
- **`kubectl get tigerastatus` is the progress bar.** The operator installs Calico
  asynchronously; the `Installation` being created ≠ Calico being up. Wait for
  `AVAILABLE=True` on every row (`apiserver` only appears if you install the optional
  `APIServer` resource; this trimmed Installation yields `calico` + `ippools`).
- **Ping the pod IP, not the pod name.** Bare pods don't get DNS records, so
  `ping test2` fails with `bad address` even on a healthy network — an easy way to
  misdiagnose a working install. Grab the IP with
  `kubectl get pod test2 -o jsonpath='{.status.podIP}'`.
- **Verify behavior, not status.** Green pods prove nothing about enforcement. The proof
  is a **pair** of pings: the same command succeeding before the policy and failing after
  it (exit 1, 100% packet loss). `kubectl exec` still works under deny-all because exec
  traffic flows API server → kubelet → runtime, not over the pod network.
- **Felix needs a beat.** After `apply -f deny-all.yaml` the dataplane rules land within
  a few seconds; `solution.sh` retries until the ping actually fails before declaring the
  enforcement proven. Solving by hand, just re-run the ping if the first one still gets
  through.
