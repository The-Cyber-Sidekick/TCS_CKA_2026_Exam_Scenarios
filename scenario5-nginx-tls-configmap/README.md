# Scenario 5 — Tighten nginx to TLS 1.3 (ConfigMap edit + rolling restart)

A self-contained CKA **Workloads & Scheduling** lesson, taken from a real 2025/2026 exam
question. An `nginx-static` Deployment serves HTTPS, and its server config lives in a
ConfigMap named `nginx-config` that currently allows **both TLS 1.2 and TLS 1.3**. Your
job is to update the ConfigMap so only **TLS 1.3** is allowed, then roll the Deployment so
nginx re-reads it. A TLS 1.2 request to the Service must then fail.

It runs on its **own dedicated kind cluster** (`cka-scenario5`, default kindnet CNI is
fine). This is a **host-side** lesson — plain `kubectl` from the workstation, the same
style as scenarios 2 and 3.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario5` |
| `manifests/configmap.yaml` | **Armed** state — `ssl_protocols TLSv1.2 TLSv1.3;` (the thing to fix) |
| `manifests/configmap-tls13.yaml` | **Answer key** — same config, `ssl_protocols TLSv1.3;` only |
| `manifests/deployment.yaml` | `nginx-static` Deployment (mounts the ConfigMap + TLS Secret) + Service on 443 |
| `manifests/tester.yaml` | A `curlimages/curl` pod used to probe the Service and pin the client TLS version |
| `setup.sh` | Create the cluster, mint a self-signed cert Secret, AND arm the scenario |
| `solution.sh` | Answer key — apply the TLS 1.3 ConfigMap, roll, and verify |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores any generated scratch output |

## Quick start

```bash
cd scenario5-nginx-tls-configmap
./setup.sh        # create cka-scenario5, mint the cert Secret, AND arm it
# solve it by hand, or:
./solution.sh     # apply the TLS 1.3 ConfigMap, roll the Deployment, verify
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the armed state**: nginx is serving HTTPS
and accepts TLS 1.2 and 1.3. It is re-runnable (it re-applies the baseline ConfigMap and
re-rolls the Deployment, so a previous solve is reset back to TLS 1.2 + 1.3).

## The task

1. Find the `nginx-config` ConfigMap in the `nginx-static` namespace and the
   `ssl_protocols` line in its server config.
2. Change it so **only TLS 1.3** is allowed (`ssl_protocols TLSv1.3;`).
3. **Roll the Deployment** so nginx re-reads the ConfigMap (`kubectl rollout restart`).
4. Verify a TLS 1.2 request now fails, while TLS 1.3 still serves the page.

## Solving it by hand

```bash
CTX=kind-cka-scenario5 ; NS=nginx-static
SVC=https://nginx-static.$NS.svc.cluster.local

# 1) baseline: TLS 1.2 is currently accepted (returns "TLS OK")
kubectl --context $CTX -n $NS exec deploy/tester -- curl -sk --tlsv1.2 --tls-max 1.2 $SVC

# 2) edit the ConfigMap — change ssl_protocols to TLSv1.3 only
kubectl --context $CTX -n $NS edit configmap nginx-config

# 3) roll the Deployment so nginx picks up the change
kubectl --context $CTX -n $NS rollout restart deploy/nginx-static
kubectl --context $CTX -n $NS rollout status  deploy/nginx-static

# 4) verify: TLS 1.2 now fails; TLS 1.3 still works
kubectl --context $CTX -n $NS exec deploy/tester -- curl -sk --tlsv1.2 --tls-max 1.2 $SVC   # error
kubectl --context $CTX -n $NS exec deploy/tester -- curl -sk $SVC                            # TLS OK
```

## Why it works (and the traps)

- **ConfigMaps are not live-reloaded by the app.** Editing the ConfigMap changes the
  mounted file, but nginx only reads `ssl_protocols` at startup. Without a
  `kubectl rollout restart` (or deleting the pod) the change does nothing — this is the
  step people forget and lose the marks on.
- **`ssl_protocols` is a hard allow-list.** With only `TLSv1.3`, nginx sends a TLS alert
  for any 1.2 (or lower) ClientHello, so the handshake fails before any HTTP happens.
- **Pin the client to prove it.** `curl --tlsv1.2 --tls-max 1.2` forces the client to
  offer at most TLS 1.2. Against the fixed server it fails; without `--tls-max` curl
  happily negotiates 1.3, so always pin the version when you test.
- **A self-signed cert** is used, hence `curl -k`. The cert is minted by `setup.sh` into
  a TLS Secret (`nginx-tls`); the private key is never committed.
- **The Service is the contract.** Verify against
  `https://nginx-static.nginx-static.svc.cluster.local`, not just the pod, because that is
  what the grader (and real clients) hit.
