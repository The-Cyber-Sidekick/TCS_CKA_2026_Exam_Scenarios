#!/usr/bin/env bash
# Scenario 3 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name cka-scenario3
