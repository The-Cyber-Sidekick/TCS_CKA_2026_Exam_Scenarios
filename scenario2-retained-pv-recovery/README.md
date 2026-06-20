# Scenario 2 — The Retained Volume

A self-contained CKA **Storage** lesson: a MariaDB Deployment in the `mariadb` namespace
was deleted by accident. Its PersistentVolume uses the **Retain** reclaim policy, so the
data survived. Your job is to recreate the claim, bind it to that volume, re-wire the
Deployment, and verify it comes back up, with no data loss.

It runs on its **own dedicated kind cluster** (`cka-scenario2`).

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario2` |
| `manifests/pv.yaml` | The retained PV (`mariadb`, 250Mi, RWO, Retain, static) |
| `manifests/pvc.yaml` | The PVC answer (empty storageClass + `volumeName` for a static bind) |
| `manifests/deployment.yaml` | The "existing" Deployment you are handed — storage wiring **missing** |
| `solution/deployment.yaml` | Answer key: same Deployment with the volume + volumeMount added |
| `setup.sh` | Create the cluster AND arm the scenario (namespace + retained PV; Deployment/PVC gone) |
| `solution.sh` | Answer key — create the PVC, apply the wired Deployment, verify |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores the generated `out/` capture directory |

## Quick start

```bash
cd scenario2-retained-pv-recovery
./setup.sh        # create cka-scenario2 AND arm it (needs Docker + kind + kubectl in WSL2)
# solve it by hand, or:
./solution.sh     # apply the answer key and verify recovery
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the broken state**: the `mariadb` namespace and
the retained PV exist, but the Deployment and its PVC are gone, exactly like a deployment
someone deleted on a Retain-policy volume. It is re-runnable (it clears the PV's stale
`claimRef` so the volume returns to `Available` each time).

## The task

1. Create a PVC named `mariadb` in namespace `mariadb` (250Mi, ReadWriteOnce) **bound to the
   existing PV**.
2. Edit `manifests/deployment.yaml` to mount that PVC at `/var/lib/mysql`.
3. Apply it; the pod must be `Running` with no restarts.

## Solving it by hand

```bash
CTX=kind-cka-scenario2
kubectl --context $CTX get pv mariadb                 # Retain + Available: the data survived
kubectl --context $CTX apply -f manifests/pvc.yaml    # PVC: storageClassName "" + volumeName mariadb
kubectl --context $CTX -n mariadb get pvc             # must be Bound before the pod can run
vi manifests/deployment.yaml                          # add the volumes + volumeMount (claimName: mariadb)
kubectl --context $CTX apply -f manifests/deployment.yaml
kubectl --context $CTX -n mariadb get pods            # Running, 0 restarts
```

## Why it works (and the traps)

- **`storageClassName: ""`** on *both* the PV and PVC forces a **static** bind. Omit it and
  kind's default `standard` StorageClass would dynamically provision a brand-new, empty volume
  instead of binding the one that holds your data.
- **`volumeName: mariadb`** on the PVC targets that specific PV.
- **Retain leaves the PV `Released`, not `Available`, after the PVC is deleted** (the stale
  `claimRef` blocks rebinding). In a real recovery you'd `kubectl patch pv mariadb -p
  '{"spec":{"claimRef":null}}'` to make it bindable again. `setup.sh` does this for you so the
  scenario is reproducible.
- The `mariadb` image's entrypoint runs as root and chowns `/var/lib/mysql`, so the hostPath
  volume is writable with no `securityContext`/`fsGroup` needed.
