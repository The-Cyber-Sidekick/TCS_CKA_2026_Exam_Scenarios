#!/usr/bin/env bash
# Scenario 7 — answer key: create the autoscaling/v2 HorizontalPodAutoscaler that the
# task asks for (apache-server, CPU 50%, 1..4 replicas, 30s scaleDown stabilization),
# then verify it is bound to the Deployment and reading CPU.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario7"
CTX="kind-${CLUSTER}"
NS="autoscale"
K="kubectl --context ${CTX}"
docker inspect "${CLUSTER}-control-plane" >/dev/null 2>&1 || { echo "❌ cluster not found — run ./setup.sh first"; exit 1; }

echo "▶ Creating the HPA (autoscaling/v2: CPU 50%, min 1, max 4, scaleDown window 30s)"
$K apply -f manifests/hpa.yaml

echo "▶ Waiting for the HPA to bind to the Deployment and read CPU (TARGETS no longer <unknown>)"
ok=""
for i in $(seq 1 24); do
  targets="$($K -n "$NS" get hpa apache-server -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
  if [ -n "$targets" ]; then ok="yes"; break; fi
  sleep 5
done

echo
echo "▶ HPA summary:"
$K -n "$NS" get hpa apache-server
echo
echo "▶ Confirming the configured fields (the easy marks to lose):"
echo "  scaleTargetRef    : $($K -n "$NS" get hpa apache-server -o jsonpath='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}')"
echo "  min / max         : $($K -n "$NS" get hpa apache-server -o jsonpath='{.spec.minReplicas} .. {.spec.maxReplicas}')"
echo "  CPU target        : $($K -n "$NS" get hpa apache-server -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')%"
echo "  scaleDown window  : $($K -n "$NS" get hpa apache-server -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}')s"

if [ -n "$ok" ]; then
  echo
  echo "✅ Done: apache-server HPA created, bound to the Deployment, and reading CPU."
else
  echo
  echo "⚠ HPA created, but TARGETS still <unknown> — metrics-server may need another moment."
  echo "  Re-check: kubectl -n ${NS} get hpa apache-server"
fi
