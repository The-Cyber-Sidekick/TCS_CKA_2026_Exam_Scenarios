# Scenario 6 — Migrate Ingress to the Gateway API (keep HTTPS)

A self-contained CKA **Services & Networking** lesson, taken from a real 2025/2026 exam
question. A web application is exposed over HTTPS by a classic **Ingress** named `web`
(host `gateway.web.k8s.local`). Your job is to migrate it to the **Gateway API**: create a
`Gateway` (HTTPS listener, reusing the same TLS Secret) and an `HTTPRoute` that carries
over the routing, verify HTTPS still works through the Gateway, then delete the Ingress.

It runs on its **own dedicated kind cluster** (`cka-scenario6`). This is a **host-side**
lesson — plain `kubectl` from the workstation, the same style as scenarios 2, 3, and 5.

> **Gateway implementation:** the real exam ships a GatewayClass named `nginx` (NGINX
> Gateway Fabric). This scenario uses **Envoy Gateway** (GatewayClass **`eg`**), matching
> the rest of the learning environment. The Gateway API objects you author are identical
> either way; only `gatewayClassName` differs.

## What's here

| File | Purpose |
|---|---|
| `kind-config.yaml` | Single-node cluster `cka-scenario6`, labelled `ingress-ready=true` for ingress-nginx |
| `manifests/web-app.yaml` | The `web` Deployment (http-echo, returns `WEB APP OK`) + Service + a `tester` curl pod |
| `manifests/ingress.yaml` | The **existing** Ingress `web` (TLS, host `gateway.web.k8s.local`) — the thing to migrate |
| `manifests/gateway.yaml` | **Answer key** — Gateway `web-gateway` (`gatewayClassName: eg`, HTTPS listener, TLS terminate) |
| `manifests/httproute.yaml` | **Answer key** — HTTPRoute `web-route` (same host, `/` → `web:80`) |
| `setup.sh` | Create the cluster, install ingress-nginx + Envoy Gateway, mint the TLS Secret, AND arm the prerequisites |
| `solution.sh` | Answer key — apply Gateway + HTTPRoute, verify HTTPS, delete the Ingress, re-verify |
| `teardown.sh` | Delete the cluster |
| `.gitignore` | Ignores any generated scratch output |

## Quick start

```bash
cd scenario6-ingress-to-gateway
./setup.sh        # create cka-scenario6, install controllers, arm the prerequisites
# solve it by hand, or:
./solution.sh     # apply the Gateway + HTTPRoute, verify, delete the Ingress
./teardown.sh     # when done
```

`setup.sh` brings the cluster up **already in the armed state**: ingress-nginx is serving
the existing `web` Ingress over HTTPS, the Gateway API stack is installed, and there is no
Gateway/HTTPRoute yet. It is re-runnable (it re-applies the Ingress and removes any
Gateway/HTTPRoute from a previous solve, resetting to the unsolved state).

## The task

1. Read the routing on the existing `web` Ingress (host, path, backend Service).
2. Create a **Gateway** `web-gateway` with `gatewayClassName: eg` and an **HTTPS** listener
   on 443 for `gateway.web.k8s.local`, terminating TLS with the `web-tls` Secret.
3. Create an **HTTPRoute** `web-route` for the same host that forwards `/` to `web:80`.
4. Verify HTTPS works **through the Gateway**, then **delete the `web` Ingress** (last).

## Solving it by hand

```bash
CTX=kind-cka-scenario6 ; NS=web ; HOST=gateway.web.k8s.local

# 1) inspect what exists
kubectl --context $CTX -n $NS get deploy,svc,ingress
kubectl --context $CTX get gatewayclass

# 2) author + apply the Gateway and HTTPRoute (no imperative command — copy from the docs)
kubectl --context $CTX apply -f manifests/gateway.yaml
kubectl --context $CTX -n $NS wait --for=condition=Programmed gateway/web-gateway --timeout=180s
kubectl --context $CTX apply -f manifests/httproute.yaml

# 3) verify through the Gateway (kind has no LoadBalancer, so curl the Envoy Service
#    ClusterIP from the in-cluster tester, pinning the host with --resolve)
EG_IP=$(kubectl --context $CTX -n envoy-gateway-system get svc \
  -l gateway.envoyproxy.io/owning-gateway-name=web-gateway -o jsonpath='{.items[0].spec.clusterIP}')
kubectl --context $CTX -n $NS exec deploy/tester -- \
  curl -sk --resolve $HOST:443:$EG_IP https://$HOST/        # WEB APP OK

# 4) migration verified -> delete the old Ingress
kubectl --context $CTX -n $NS delete ingress web
```

## Why it works (and the traps)

- **The Gateway API splits Ingress into three objects.** The `GatewayClass` is the
  controller (like `ingressClassName`), the `Gateway` is the listener (the port + TLS the
  Ingress owned), and the `HTTPRoute` holds the host/path rules to a backend. Map the
  Ingress onto those three and the migration is mechanical.
- **No imperative command.** There is no `kubectl create gateway`/`httproute`; you author
  both from the Gateway API docs (linked from kubernetes.io, allowed in the exam). Copy the
  templates from the [Simple Gateway](https://gateway-api.sigs.k8s.io/guides/) +
  [TLS](https://gateway-api.sigs.k8s.io/guides/tls/) and
  [HTTP routing](https://gateway-api.sigs.k8s.io/guides/http-routing/) guides, then fill in
  the values: `gatewayClassName` from `kubectl get gatewayclass`, the listener port + TLS
  Secret from the existing Ingress, and the host/path/backend from the Ingress rule.
- **Reuse the same TLS Secret.** Point the Gateway's HTTPS listener `certificateRefs` at
  the existing `web-tls` Secret so HTTPS is preserved exactly.
- **Wait for `Programmed`.** The Gateway provisions a data plane; testing before
  `PROGRAMMED=True` curls a listener that is not up yet.
- **Delete the Ingress LAST.** Only after the Gateway is verified. Deleting it first can
  cut the app off before the replacement is live.
- **kind specifics.** kind has no LoadBalancer, so the GatewayClass forces the Envoy proxy
  Service to `ClusterIP` (via an `EnvoyProxy` config), and we verify with an in-cluster
  `tester` pod + `curl --resolve`. A self-signed cert is used, hence `curl -k`.
