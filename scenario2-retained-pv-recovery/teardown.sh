#!/usr/bin/env bash
# Scenario 2 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name cka-scenario2
