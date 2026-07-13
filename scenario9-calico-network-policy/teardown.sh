#!/usr/bin/env bash
# Scenario 9 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name cka-scenario9
