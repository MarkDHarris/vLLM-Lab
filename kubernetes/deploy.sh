#!/usr/bin/env bash
# Apply production-shaped vLLM manifests and wait with live feedback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

log "=== Deploying vLLM inference stack ==="

require_cmd kubectl "brew install kubectl"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME" || die "Cluster '${CLUSTER_NAME}' not found. Run ./start_cluster.sh first."
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# Sync ConfigMap values from config.env so docs/scripts stay the source of truth.
tmp_cm="$(mktemp)"
cat > "$tmp_cm" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: vllm-config
  labels:
    app.kubernetes.io/name: vllm
    app.kubernetes.io/component: inference
    app.kubernetes.io/part-of: vllm-learning-lab
data:
  MODEL_NAME: "${MODEL_NAME}"
  MAX_MODEL_LEN: "${MAX_MODEL_LEN}"
  GPU_MEMORY_UTILIZATION: "${GPU_MEMORY_UTILIZATION}"
  VLLM_ARGS: "--host 0.0.0.0 --port 8000 --dtype float16 --max-model-len ${MAX_MODEL_LEN} --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION} --served-model-name ${MODEL_NAME} --enforce-eager"
EOF
kubectl apply -f "$tmp_cm"
rm -f "$tmp_cm"

token="$(resolve_hf_token)"
if [[ -n "$token" ]]; then
  log "Applying Hugging Face token Secret (from HF_TOKEN or ../hf_token)..."
  kubectl create secret generic hf-token-secret \
    --from-literal=token="$token" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  warn "No HF token found. Fine for public models like ${MODEL_NAME}."
fi

log "Applying Service / Ingress / HPA / PDB / Deployment..."
# Retry briefly: ingress admission webhook can race right after cluster start.
for i in $(seq 1 20); do
  if kubectl apply -f "${SCRIPT_DIR}/manifests/service.yaml" \
                 -f "${SCRIPT_DIR}/manifests/ingress.yaml" \
                 -f "${SCRIPT_DIR}/manifests/hpa.yaml" \
                 -f "${SCRIPT_DIR}/manifests/pdb.yaml" \
                 -f "${SCRIPT_DIR}/manifests/deployment.yaml"; then
    break
  fi
  if [[ "$i" -eq 20 ]]; then
    die "kubectl apply failed after retries (ingress webhook still unavailable?)"
  fi
  warn "kubectl apply failed (likely webhook race). Retry ${i}/20 in 3s..."
  sleep 3
done

log "Waiting for Deployment rollout (streaming pod status)..."
# Background status printer for feedback during long CPU model load.
(
  while true; do
    phase="$(kubectl get pods -l app.kubernetes.io/name=vllm -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" ready="}{.status.containerStatuses[0].ready}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null || true)"
    if [[ -n "$phase" ]]; then
      log "Pod status: ${phase}"
    else
      log "Pod status: (pending create)"
    fi
    sleep 10
  done
) &
STATUS_PID=$!
cleanup_status() { kill "$STATUS_PID" 2>/dev/null || true; wait "$STATUS_PID" 2>/dev/null || true; }
trap cleanup_status EXIT

if ! kubectl rollout status deployment/vllm-server --timeout=600s; then
  cleanup_status
  trap - EXIT
  warn "Rollout did not become ready in time. Recent logs:"
  kubectl logs -l app.kubernetes.io/name=vllm --tail=80 || true
  kubectl describe pod -l app.kubernetes.io/name=vllm | tail -60 || true
  die "Deployment failed. See logs above."
fi

cleanup_status
trap - EXIT

log "vLLM is Ready."
log "Smoke test: ./smoke_test.sh"
log "Endpoint:  http://localhost:${INGRESS_HOST_PORT}/v1/models"
