# TCS — CKA 2026 Exam Scenarios

Hands-on, self-contained scenarios to help you prepare for the **Certified Kubernetes
Administrator (CKA)** exam. Each scenario hands you a cluster that is broken (or
misconfigured) in one specific, exam-realistic way, and you practice diagnosing and fixing
it under the same conditions you'll face on the real test.

Every scenario runs on its **own dedicated [kind](https://kind.sigs.k8s.io/) cluster**, so
breaking a control plane or wrecking a config never touches anything else on your machine.
kind nodes are real kubeadm nodes (systemd + kubelet + static pods + crictl), so you
operate them the way you would an exam node — just via `docker exec` instead of SSH.

## 📺 Watch it in action

These scenarios are designed to pair with walkthrough videos and writeups. For a visual,
narrated explanation of each fault and fix, follow along here:

- **YouTube:** [@thecybersidekick](https://www.youtube.com/@thecybersidekick)
- **dev.to:** [@thecybersidekick](https://dev.to/thecybersidekick)

## Prerequisites

You'll need these on your PATH (the scenarios are built/tested on WSL2):

- [Docker](https://docs.docker.com/get-docker/) (daemon running)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Scenarios

| # | Scenario | Exam domain | What you practice |
|---|---|---|---|
| 1 | [The etcd Endpoint Trap](scenario1-etcd-endpoint-trap/) | Troubleshooting | A migrated single-node cluster whose `kube-apiserver` points at the wrong etcd endpoint, so the control plane is down |
| 2 | [The Retained Volume](scenario2-retained-pv-recovery/) | Storage | A deleted Deployment whose Retain-policy PV kept the data — recreate the PVC, statically bind it, re-wire the Deployment, and recover with no data loss |
| 3 | [The Least-Permissive Policy](scenario3-network-policy/) | Services & Networking | A `frontend` blocked from a `backend` by a default-deny ingress policy — pick and apply only the correct, least-permissive NetworkPolicy from three candidates (on a Calico cluster that actually enforces it) |
| 4 | [Prepare a Node for kubeadm with cri-dockerd](scenario4-cri-dockerd-system-prep/) | Cluster Architecture, Installation & Configuration | A node not yet ready for `kubeadm` — install the cri-dockerd CRI shim, enable its socket, and set + load the kernel params Kubernetes networking needs, all node-side via `docker exec` |
| 5 | [Tighten nginx to TLS 1.3](scenario5-nginx-tls-configmap/) | Workloads & Scheduling | An `nginx-static` Deployment whose `nginx-config` ConfigMap allows TLS 1.2 + 1.3 — edit it down to TLS 1.3 only, then `rollout restart` so nginx re-reads it and a pinned TLS 1.2 request fails |
| 6 | [Migrate Ingress to the Gateway API](scenario6-ingress-to-gateway/) | Services & Networking | A `web` app exposed over HTTPS by a classic Ingress — migrate it to the Gateway API by authoring a `Gateway` (HTTPS listener, reusing the same TLS Secret) and an `HTTPRoute`, verify HTTPS through the Gateway, then delete the Ingress last |
| 7 | [Autoscale a Deployment with an HPA](scenario7-hpa-cpu-autoscale/) | Workloads & Scheduling | An `apache-server` Deployment to autoscale — create an **autoscaling/v2** HorizontalPodAutoscaler (CPU 50%, min 1 / max 4) and finish it in YAML by hand for the one field `kubectl autoscale` can't set: a 30s `scaleDown` stabilization window under `spec.behavior` |
| 8 | [Install a CNI (flannel)](scenario8-cni-flannel-install/) | Services & Networking | A two-node cluster with no CNI, so every node is NotReady — install the provided flannel manifest, watch it CrashLoop, fix the `net-conf.json` `Network` to match the cluster's `192.168.0.0/16` pod CIDR, and prove cross-node pod connectivity |
| 9 | [Install Calico and prove NetworkPolicy enforcement](scenario9-calico-network-policy/) | Services & Networking | The same CNI-less, NotReady cluster, but the question demands **NetworkPolicy enforcement** — which eliminates flannel. Install Calico via the Tigera operator (`kubectl create`, not `apply`), wait on `tigerastatus`, prove a cross-node ping works, then apply default-deny and prove the same ping fails |

More scenarios coming — each lives in its own directory with a `README.md` and the scripts
to set it up, break it, and tear it down.

## How a scenario works

Each scenario directory follows the same pattern:

```bash
cd scenario1-etcd-endpoint-trap
./setup.sh        # create the dedicated kind cluster and arm the fault
# ... diagnose and fix it by hand (each README walks you through it) ...
./teardown.sh     # delete the cluster when you're done
```

See the README inside each scenario directory for the full walkthrough.

## License

See [LICENSE](LICENSE).
