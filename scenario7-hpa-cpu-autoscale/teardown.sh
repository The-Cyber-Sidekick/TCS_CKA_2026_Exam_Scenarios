#!/usr/bin/env bash
# Scenario 7 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name cka-scenario7
