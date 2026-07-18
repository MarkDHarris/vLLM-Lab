#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

BASE="http://localhost:${INGRESS_HOST_PORT}"

log "=== Smoke test against ${BASE} ==="

log "GET /v1/models"
curl -fsS "${BASE}/v1/models" | python3 -m json.tool

log "POST /v1/chat/completions"
curl -fsS "${BASE}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"In one sentence, what is Kubernetes?\"}],
    \"max_tokens\": 64,
    \"temperature\": 0
  }" | python3 -m json.tool

log "Smoke test passed."
