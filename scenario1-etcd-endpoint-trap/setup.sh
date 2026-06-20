#!/usr/bin/env bash
# Scenario 1 — create the dedicated kind cluster (idempotent).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER="cka-scenario1"

for cmd in docker kind kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ '$cmd' not found in PATH"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "❌ Docker daemon not running"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "✓ Cluster '$CLUSTER' already exists — leaving it as-is."
else
  echo "▶ Creating kind cluster '$CLUSTER'"
  kind create cluster --config kind-config.yaml --wait 120s
fi

# kind nodes ship without an editor. Install vim so the fix can be done in vi,
# the way you would on a real exam node (best-effort; needs network).
NODE="${CLUSTER}-control-plane"
if ! docker exec "$NODE" sh -c 'command -v vim' >/dev/null 2>&1; then
  echo "▶ Installing vim into ${NODE} (so you can vi the manifests)"
  docker exec "$NODE" sh -c 'apt-get update -qq && apt-get install -y -qq vim' >/dev/null 2>&1 \
    && echo "  ✓ vim installed" \
    || echo "  ⚠️ vim install failed (offline?) — run-demo.sh will fall back to a non-interactive edit"
fi

echo
echo "✅ Cluster up. Baseline (about to be broken on purpose):"
kubectl --context "kind-${CLUSTER}" get nodes || true

# Arm the scenario: this cluster should always come up broken in the one specific
# way this lesson teaches. break.sh stays the single definition of the fault
# (run-demo.sh reuses it); setup just invokes it so one command hands you a
# broken cluster.
echo
echo "▶ Arming the scenario (break.sh)"
./break.sh

echo
echo "🧪 Scenario armed. In ~30-60s the control plane goes down. Then:"
echo "   • Troubleshoot by hand   — see README (docker exec -it ${CLUSTER}-control-plane bash)"
echo "   • ./solution.sh          — apply the answer-key fix and recover"
echo "   • ./run-demo.sh          — capture the full lesson's real output for the video"
