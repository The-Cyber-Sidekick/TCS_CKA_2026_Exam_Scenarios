#!/usr/bin/env bash
# Scenario 10 — delete the dedicated kind cluster.
set -euo pipefail
kind delete cluster --name cka-scenario10
