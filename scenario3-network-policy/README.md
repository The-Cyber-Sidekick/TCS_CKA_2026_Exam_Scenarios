# Scenario 3 — The Least-Permissive Policy

A self-contained CKA **Services & Networking** lesson: a `frontend` Deployment must reach a
`backend` Deployment in another namespace, but the backend is locked down by a **default-deny**
ingress NetworkPolicy. Three candidate policies sit in `netpol/`. Your job is to apply **only**
the one that restores communication **and** is the least permissive, without touching the
existing default-deny.

It runs on its **own dedicated kind cluster** (`cka-scenario3`) with **Calico** as the CNI,
because kind's bundled `kindnet` does not reliably enforce NetworkPolicies.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario3` (default CNI disabled, podSubnet `192.168.0.0/16`) |
| `manifests/backend.yaml` | `backend` Deployment (nginx) + Service in the `backend` namespace |
| `manifests/frontend.yaml` | `frontend` Deployment (busybox, used to probe with `wget`) |
| `manifests/default-deny.yaml` | The "existing" deny-all ingress policy you must **not** modify |
| `netpol/netpol1-allow-namespace.yaml` | Candidate 1 — whole namespace allowed (**too permissive**) |
| `netpol/netpol2-allow-frontend.yaml` | Candidate 2 — pod label + port (**correct, least permissive**) |
| `netpol/netpol3-empty-ingress.yaml` | Candidate 3 — empty ingress, allows nothing (**wrong**) |
| `setup.sh` | Create the cluster, install Calico, AND arm the scenario (idempotent) |
| `solution.sh` | Answer key — apply netpol2 and verify the frontend reaches the backend |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores the generated `out/` capture directory |

## Quick start

```bash
cd scenario3-network-policy
./setup.sh        # create cka-scenario3, install Calico, AND arm it (needs Docker + kind + kubectl in WSL2)
# solve it by hand, or:
./solution.sh     # apply the answer key (netpol2) and verify connectivity
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the broken state**: both namespaces and
workloads exist, the `backend` namespace has only the default-deny policy, and the three
candidate policies are left **unapplied** in `netpol/`. It is re-runnable (it removes any
candidate policy a previous solve applied, so the backend starts blocked again).

## The task

1. Read the existing `default-deny` policy in the `backend` namespace. Do **not** change it.
2. Review the three candidates in `netpol/` and choose the correct, least-permissive one.
3. Apply only that policy.
4. Verify the `frontend` pod can reach `http://backend.backend.svc.cluster.local`.

## Solving it by hand

```bash
CTX=kind-cka-scenario3
kubectl --context $CTX -n backend get networkpolicy                 # only default-deny is present
kubectl --context $CTX -n frontend exec deploy/frontend -- \
  wget -T 5 -qO- http://backend.backend.svc.cluster.local          # times out: blocked
ls netpol/ && cat netpol/netpol2-allow-frontend.yaml               # the least-permissive answer
kubectl --context $CTX apply -f netpol/netpol2-allow-frontend.yaml # add it alongside default-deny
kubectl --context $CTX -n frontend exec deploy/frontend -- \
  wget -T 5 -qO- http://backend.backend.svc.cluster.local          # now returns the nginx page
```

## Why netpol2 (and the traps)

- **Policies are additive.** You add an allow policy next to the default-deny; you never edit
  the deny. Both stay in place and combine.
- **netpol1 works but is too permissive** — a bare `namespaceSelector` lets *every* pod in the
  `frontend` namespace in. **netpol3 is wrong** — an empty `ingress: []` allows nothing.
- **netpol2 is least permissive**: `namespaceSelector` **and** `podSelector` in the **same**
  `from` entry are ANDed, so only pods labelled `app=frontend` *in the frontend namespace* are
  allowed, and only on TCP 80. Splitting them into two `from` entries would OR them, which is
  looser.
- **The namespace label** `kubernetes.io/metadata.name=frontend` is added automatically by
  Kubernetes, so the `namespaceSelector` matches with no manual labelling.
- **Calico, not kindnet.** `setup.sh` disables kind's default CNI and installs Calico; without
  an enforcing CNI the policies would parse but never actually block anything, and the lesson's
  before/after would be identical.
