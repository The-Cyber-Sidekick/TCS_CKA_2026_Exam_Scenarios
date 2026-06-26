#!/usr/bin/env bash
# Scenario 4 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name "cka-scenario4"
echo "✅ Scenario 4 cluster removed."
