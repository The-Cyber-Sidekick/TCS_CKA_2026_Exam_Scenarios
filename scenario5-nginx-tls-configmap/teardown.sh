#!/usr/bin/env bash
# Scenario 5 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name cka-scenario5
