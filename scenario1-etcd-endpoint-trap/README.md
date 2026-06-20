# Scenario 1 — The etcd Endpoint Trap

A self-contained CKA **Troubleshooting** lesson: a migrated single-node cluster whose
control plane is down because `kube-apiserver` points at the wrong etcd endpoint.

It runs on its **own dedicated kind cluster** (`cka-scenario1`) so breaking the control
plane never touches any other cluster on your machine.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single control-plane node (this is control-plane troubleshooting) |
| `setup.sh` | Create the dedicated cluster, then arm the fault (idempotent) |
| `break.sh` | Inject the fault (wrong `--etcd-servers` endpoint) |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores the generated `out/` capture directory |

## Quick start

```bash
cd scenario1-etcd-endpoint-trap
./setup.sh        # create cka-scenario1 AND arm the fault (needs Docker + kind + kubectl in WSL2)
# ... troubleshoot by hand (see below) ...
./teardown.sh     # when done
```

`setup.sh` always brings the cluster up **already broken** in this scenario's one specific
way (it calls `break.sh`), so you are handed a broken cluster to troubleshoot, exam-style.
In ~30–60s the control plane goes down.

> `setup.sh` installs `vim` into the node (kind nodes ship without an editor), so `vi`
> works once you're inside.

## Practicing the troubleshooting by hand

```bash
./setup.sh                                   # cluster comes up already broken (~30-60s to go down)
# from inside the node (this is a single-node kubeadm box):
docker exec -it cka-scenario1-control-plane bash
  kubectl get nodes                          # connection refused
  systemctl is-active kubelet                # active — kubelet is fine
  journalctl -u kubelet -f                   # kubelet alive but stuck restarting the apiserver (Ctrl-C to stop)
  crictl logs <id> | grep etcd               # dial tcp ...:2399 connection refused
  cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep etcd-servers
  cat /etc/kubernetes/manifests/etcd.yaml | grep client-urls         # compare!
  # fix: edit the manifest in vi, the way you would on the exam
  vi /etc/kubernetes/manifests/kube-apiserver.yaml
  #   find the --etcd-servers line, change the endpoint back to
  #   https://127.0.0.1:2379, then save and quit with :wq
  systemctl restart kubelet
  exit
```

`break.sh` saves the pristine manifest to `/root/kube-apiserver.yaml.orig` inside the node
before injecting the fault, so if you want to skip straight to a recovery you can restore it:

```bash
docker exec cka-scenario1-control-plane sh -c \
  'cp /root/kube-apiserver.yaml.orig /etc/kubernetes/manifests/kube-apiserver.yaml && systemctl restart kubelet'
```

## How the fault works (and why it's reproducible)

`break.sh` rewrites `kube-apiserver.yaml`'s `--etcd-servers` to a wrong endpoint
(default `https://127.0.0.1:2399` — a closed port, for an instant, deterministic
"connection refused"). The kubelet reloads the static pod; the apiserver can't reach etcd
and crashloops. kind nodes are real kubeadm nodes (systemd + kubelet + static pods +
crictl), so this faithfully mirrors the exam environment — you operate via `docker exec`
instead of SSH.

Set `BAD_ETCD=https://10.2.0.14:2379` before running `break.sh` to reproduce the
"wrong host IP from the migration / i-o timeout" variant instead.

> **kind note:** the authentic `connection refused` only shows when `kubectl` runs **on the
> node** (via `/etc/kubernetes/admin.conf`). From the WSL host, kind's docker port-proxy
> turns it into `connection reset by peer`. Run the kubectl steps on the node for fidelity,
> which also matches how a single-node kubeadm box actually works.
