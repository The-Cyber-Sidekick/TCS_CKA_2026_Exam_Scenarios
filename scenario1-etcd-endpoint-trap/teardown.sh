#!/usr/bin/env bash
# Scenario 1 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name "cka-scenario1"
echo "✅ Scenario 1 cluster removed."
