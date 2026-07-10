#!/usr/bin/env bash
# Scenario 8 — delete the dedicated cluster.
set -euo pipefail
kind delete cluster --name cka-scenario8
