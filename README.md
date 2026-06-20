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
