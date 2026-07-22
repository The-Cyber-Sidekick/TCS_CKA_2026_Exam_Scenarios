# Scenario 10 — Install Argo CD with Helm (and survive the missing-CRD trap)

A self-contained CKA **Cluster Architecture, Installation & Configuration** lesson, taken
from a real 2025/2026 exam question. Three Helm deliverables: add the official Argo CD
repository as **`argo`**, render a **`helm template`** for release `argocd` (chart version
**7.7.3**, namespace `argocd`) saved to `argo-helm.yaml`, and **`helm install`** the same
release — with **`--set crds.install=false` on both**, because the question says the Argo
CD CRDs "have already been pre-installed in the cluster".

The lab twist (same as the source walkthrough): that premise is **false** here. A fresh
cluster has no `argoproj.io` CRDs, so the CRD-less install comes up with `argocd-server`,
the application controller, the applicationset controller and the notifications controller
all crashlooping on **"the server could not find the requested resource"**. Diagnosing
that — logs → `kubectl get crd` → pin the CRDs to the chart's `appVersion` (7.7.3 →
**v2.13.0**) → `rollout restart` — is the second half of the lesson.

It runs on its own dedicated single-node kind cluster (`cka-scenario10`, default CNI).
This is a **host-side** lesson (plain `helm`/`kubectl` from the workstation), so the
on-screen terminal is branded `cka@workstation:~$`.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario10` (the trap is in the API, not the infra) |
| `manifests/crds/*.yaml` | Pinned Argo CD **v2.13.0** CRDs (downloaded by `setup.sh`, gitignored) — the fix |
| `setup.sh` | Download the pinned CRDs, create the cluster, arm the unsolved state (empty `argocd` ns, **no** argoproj CRDs, no `argo` repo) |
| `solution.sh` | Answer key — repo add, template, install, diagnose the crashloop, apply CRDs, restart, verify |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores the downloaded CRD manifests and the learner's generated `argo-helm.yaml` |

## Quick start

```bash
cd scenario10-argocd-helm-install
./setup.sh        # create cka-scenario10 + arm: empty argocd ns, NO argoproj CRDs
# solve it by hand, or:
./solution.sh     # repo add, template, install, diagnose, fix, verify
./teardown.sh     # when done
```

`setup.sh` is re-runnable: it uninstalls any previous `argocd` release, deletes the
`argoproj.io` CRDs and the `argocd` namespace (then recreates it empty), removes the
`argo` Helm repo from the host, and deletes the learner's `argo-helm.yaml` — back to the
unsolved state.

## The task (exam wording)

1. Add the official Argo CD Helm repository with the name **`argo`** to the cluster
   (URL given in the question: `https://argoproj.github.io/argo-helm`).
2. The Argo CD CRDs *"have already been pre-installed in the cluster"*.
3. Generate a Helm **template** for release `argocd`, chart version **7.7.3**, namespace
   `argocd`, saved to **`argo-helm.yaml`** — configured to **not install the CRDs**.
4. **Install** release `argocd` with the same chart/version/namespace, again **without
   CRDs**. You do **not** need to configure access to the Argo CD server UI.

…then figure out why half the pods are crashlooping.

## Solving it by hand

```bash
CTX=kind-cka-scenario10

# 1) add the repo under the exam's name (the URL is in the question)
helm repo add argo https://argoproj.github.io/argo-helm
helm repo list

# 2) render the template — pinned version, target namespace, NO CRDs
helm --kube-context $CTX template argocd argo/argo-cd --version 7.7.3 \
  --namespace argocd --set crds.install=false > argo-helm.yaml
grep -c 'kind: CustomResourceDefinition' argo-helm.yaml    # 0 = the flag worked

# 3) install with IDENTICAL values (only the verb changes)
helm --kube-context $CTX install argocd argo/argo-cd --version 7.7.3 \
  --namespace argocd --set crds.install=false
helm --kube-context $CTX ls -n argocd                      # "deployed" — Helm's view

# 4) the trap: watch the pods, read the logs
kubectl --context $CTX get pods -n argocd                  # CrashLoopBackOff
kubectl --context $CTX logs deploy/argocd-server -n argocd --tail=3
#   level=fatal msg="the server could not find the requested resource (post appprojects.argoproj.io)"

# 5) diagnose + fix: no argoproj CRDs; install the ones matching the chart's appVersion
kubectl --context $CTX get crd | grep argoproj             # (empty)
helm show chart argo/argo-cd --version 7.7.3 | grep appVersion   # v2.13.0
kubectl --context $CTX apply -f manifests/crds/
kubectl --context $CTX get crd | grep argoproj             # all three

# 6) fresh pods now instead of waiting out the backoff, then verify
kubectl --context $CTX -n argocd rollout restart deployment
kubectl --context $CTX get pods -n argocd                  # everything Running/Ready
```

## Why it works (and the traps)

- **The URL and version are in the question.** You never memorize repository links for
  the exam; you *do* have to pin `--version 7.7.3` exactly, on the template **and** the
  install.
- **`helm template` is a client-side render.** Nothing touches the cluster, which is why
  the output can be redirected to a file. The proof the flag worked is
  `grep -c 'kind: CustomResourceDefinition' argo-helm.yaml` → `0` (the chart normally
  ships 3 CRDs).
- **Template and install must carry identical values.** Same `--namespace`, same
  `--set crds.install=false`; only the verb changes. If they drift, the file you saved
  describes a different system than the one you deployed.
- **`helm ls` saying `deployed` is Helm's view, not health.** Helm submitted valid
  manifests; it has no idea the controllers need CRDs that aren't there. Always end on
  `kubectl get pods`.
- **The failure signature is worth memorizing.** A controller crashlooping with
  `the server could not find the requested resource` is asking the API server for a
  resource *type* that doesn't exist — a missing CRD. Verify in two seconds:
  `kubectl get crd | grep argoproj`.
- **Pin the CRDs to the chart's `appVersion`.** CRDs and controllers drift across
  releases. `helm show chart argo/argo-cd --version 7.7.3` says `appVersion: v2.13.0`,
  so `setup.sh` pins `manifests/crds/` to the `v2.13.0` tag of the Argo CD repo
  (applications, applicationsets, appprojects).
- **`rollout restart` beats waiting.** The crashlooped pods *would* recover on the next
  backoff retry, but a restart brings fresh pods up immediately. (The application
  controller is a StatefulSet; `rollout restart` works on it the same way.)
- **The fix never touches the Helm release.** The release was correct; the environment
  broke the premise. Don't `helm uninstall` your way out of a broken premise.
