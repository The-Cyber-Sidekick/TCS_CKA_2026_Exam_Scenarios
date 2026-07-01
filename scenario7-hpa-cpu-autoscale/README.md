# Scenario 7 — Autoscale a Deployment with an HPA (the field `kubectl autoscale` can't set)

A self-contained CKA **Workloads & Scheduling** lesson, taken from a real 2025/2026 exam
question. A Deployment named `apache-server` is running in the `autoscale` namespace. Your
job is to create a **HorizontalPodAutoscaler** named `apache-server` that targets it:
**50%** average CPU utilization per pod, **min 1 / max 4** replicas, and a **scaleDown
stabilization window of 30 seconds**.

The twist is that last requirement. `kubectl autoscale` sets the target, min, and max in
one line (current kubectl even emits an **autoscaling/v2** object with the target already
in `metrics[]`), but it has **no flag for a stabilization window**. That field lives under
`spec.behavior`, so you have to finish the HPA in YAML by hand.

It runs on its **own dedicated kind cluster** (`cka-scenario7`). This is a **host-side**
lesson — plain `kubectl` from the workstation, the same style as scenarios 2, 3, 5, and 6.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario7` (no ingress/host ports — pure control-plane) |
| `manifests/apache-app.yaml` | The `apache-server` Deployment (php-apache, **CPU request 200m**) + Service |
| `manifests/hpa.yaml` | **Answer key** — autoscaling/v2 HPA (`apache-server`, CPU 50%, 1..4, 30s scaleDown window) |
| `setup.sh` | Create the cluster, install + patch metrics-server, apply the Deployment, arm the scenario |
| `solution.sh` | Answer key — apply the HPA and verify every field (ref, min/max, target, window) |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores any generated scratch output |

## Quick start

```bash
cd scenario7-hpa-cpu-autoscale
./setup.sh        # create cka-scenario7, install metrics-server, arm the Deployment
# solve it by hand, or:
./solution.sh     # apply the HPA and verify
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the armed state**: metrics-server is running
(patched with `--kubelet-insecure-tls` for kind), the `apache-server` Deployment is up with
a CPU request, and there is no HPA yet. It is re-runnable (it re-applies the Deployment and
removes any HPA from a previous solve, resetting to the unsolved state).

## The task

1. In the `autoscale` namespace, create a **HorizontalPodAutoscaler** named `apache-server`.
2. Target the existing **`apache-server` Deployment**.
3. Set the CPU target to **50% average utilization** per pod.
4. Allow **min 1 / max 4** replicas.
5. Set the **scaleDown stabilization window to 30 seconds**.

## Solving it by hand

```bash
CTX=kind-cka-scenario7 ; NS=autoscale

# 1) read the Deployment — note the CPU request (a % target needs one)
cat manifests/apache-app.yaml                     # look at resources.requests.cpu (200m)
kubectl --context $CTX -n $NS top pods            # metrics-server is the HPA's CPU source

# 2) the fast path stops short: kubectl autoscale has no flag for a behavior block
kubectl --context $CTX -n $NS autoscale deployment apache-server \
  --cpu-percent=50 --min=1 --max=4 --dry-run=client -o yaml   # v2, but no spec.behavior

# 3) author the autoscaling/v2 manifest (target in metrics[], behavior for the window).
#    Copy the object shape + the behavior block from the docs (see "Where the YAML
#    comes from" below), or take the dry-run above as the skeleton and add behavior.
kubectl --context $CTX apply -f manifests/hpa.yaml

# 4) verify every field
kubectl --context $CTX -n $NS get hpa apache-server
kubectl --context $CTX -n $NS get hpa apache-server \
  -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}' ; echo   # 30
```

## Where the YAML comes from (official docs)

There is no `kubectl create` that emits a `behavior` block, so part of this is copy-paste
from the Kubernetes docs (which you are allowed to use in the exam). Two pages cover it:

- **HorizontalPodAutoscaler Walkthrough** — the autoscaling/v2 object shape, including the
  `metrics[]` form of the CPU target. Search "HPA" on kubernetes.io, or:
  <https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/>
- **Horizontal Pod Autoscaling** (concept) → section **"Configurable scaling behavior"** →
  **"Stabilization window"** — the `spec.behavior.scaleDown.stabilizationWindowSeconds`
  block, which you lift straight into the manifest:
  <https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior>

Fastest path: generate the skeleton with `kubectl autoscale ... --dry-run=client -o yaml`,
then paste the `behavior` block from that section and set the window to `30`.

## Why it works (and the traps)

- **A CPU utilization target needs a CPU request.** 50% is a percentage *of the Pod's CPU
  request*. With no `resources.requests.cpu`, the HPA can't compute utilization and parks at
  `TARGETS <unknown>/50%` forever. The `apache-server` Pod requests `200m`, so 50% means it
  acts at ~`100m` per pod.
- **metrics-server must be running.** The HPA reads live CPU from it. On kind the kubelet
  serves metrics over a self-signed cert, so metrics-server needs `--kubelet-insecure-tls`
  (the setup script patches this) or it never becomes Available and every HPA shows
  `<unknown>`.
- **`kubectl autoscale` can't set a stabilization window.** It is the right tool for min,
  max, and the CPU target (current kubectl even emits an **autoscaling/v2** object with the
  target in `metrics[]`), but it has **no flag for `spec.behavior`**. The `scaleDown`
  stabilization window only exists there, so this task forces you to finish the HPA in YAML
  by hand.
- **In v2 the CPU target lives in `metrics[]`.** It's a `Resource` metric with
  `target.type: Utilization` and `averageUtilization: 50`, **not** the v1 top-level
  `targetCPUUtilizationPercentage`. Pasting the v1 field in next to a v2 `behavior` block is
  the `unknown field "targetCPUUtilizationPercentage"` error from the walkthrough.
- **Verify each requirement separately.** Reference to the Deployment, the 50% target, the
  1..4 range, and the 30s window are four distinct marks — `describe` plus a `jsonpath` on
  `spec.behavior.scaleDown.stabilizationWindowSeconds` confirm them all.
