#!/usr/bin/env bash
# Full path: prestage → cluster → deploy → smoke → short Locust run → teardown.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

KEEP_CLUSTER="${KEEP_CLUSTER:-0}"
LOCUST_USERS="${LOCUST_USERS:-5}"
LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE:-1}"
LOCUST_RUNTIME="${LOCUST_RUNTIME:-30s}"

log "========================================"
log " End-to-End Kubernetes Inference Lab"
log "========================================"

"${SCRIPT_DIR}/prestage.sh"
"${SCRIPT_DIR}/start_cluster.sh"
"${SCRIPT_DIR}/deploy.sh"
"${SCRIPT_DIR}/smoke_test.sh"

ensure_locust_venv
log "Running Locust headless: users=${LOCUST_USERS} spawn=${LOCUST_SPAWN_RATE} time=${LOCUST_RUNTIME}"
locust -f "${SCRIPT_DIR}/locustfile.py" \
  --headless \
  -u "$LOCUST_USERS" \
  -r "$LOCUST_SPAWN_RATE" \
  --run-time "$LOCUST_RUNTIME" \
  --host "http://localhost:${INGRESS_HOST_PORT}"

if [[ "$KEEP_CLUSTER" == "1" ]]; then
  log "KEEP_CLUSTER=1 set; leaving cluster running."
  log "Tear down later with: ./delete_cluster.sh"
else
  "${SCRIPT_DIR}/delete_cluster.sh"
fi

log "========================================"
log " End-to-End run finished successfully"
log "========================================"
