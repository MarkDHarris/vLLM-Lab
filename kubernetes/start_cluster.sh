#!/usr/bin/env bash
# Create the Kind cluster, load prestaged images, install Ingress + metrics-server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

log "=== Starting Kind cluster: ${CLUSTER_NAME} ==="

require_cmd kind "brew install kind"
require_cmd kubectl "brew install kubectl"
check_docker

HF_CACHE_HOST="$(expand_path "$HF_CACHE_HOST")"
model_dir="${HF_CACHE_HOST}/hub/models--${MODEL_NAME//\//--}"
if ! find "$model_dir" \( -name '*.safetensors' -o -name 'pytorch_model.bin' \) 2>/dev/null | grep -q .; then
  die "Model ${MODEL_NAME} not found in ${HF_CACHE_HOST}. Run ./prestage.sh first."
fi

cfg="$(generate_kind_config "${SCRIPT_DIR}/.kind-config.generated.yaml")"
log "Using Kind config: ${cfg}"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Cluster '${CLUSTER_NAME}' already exists."
else
  log "Creating Kind cluster (node image ${KIND_NODE_IMAGE} should already be local)..."
  kind create cluster --config "$cfg"
fi

kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# Load prestaged images so the cluster never waits on a silent registry pull.
load_image_into_kind "$VLLM_IMAGE"
load_image_into_kind "registry.k8s.io/ingress-nginx/controller:v1.12.1"
load_image_into_kind "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.2"
load_image_into_kind "registry.k8s.io/metrics-server/metrics-server:v0.7.2"

log "Installing ingress-nginx (vendored)..."
kubectl apply -f "${SCRIPT_DIR}/${INGRESS_MANIFEST}"

log "Installing metrics-server (vendored, Kind-patched)..."
kubectl apply -f "${SCRIPT_DIR}/${METRICS_SERVER_MANIFEST}"

log "Waiting for ingress-nginx controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=available deployment/ingress-nginx-controller \
  --timeout=180s

log "Waiting for ingress-nginx admission webhooks..."
# Jobs may already be Complete from a prior run; tolerate that.
kubectl wait --namespace ingress-nginx \
  --for=condition=complete job --all \
  --timeout=180s || true

# Extra readiness: webhook endpoints exist.
for i in $(seq 1 30); do
  if kubectl get validatingwebhookconfigurations ingress-nginx-admission >/dev/null 2>&1 \
     && kubectl -n ingress-nginx get endpoints ingress-nginx-controller-admission -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
    break
  fi
  log "Admission webhook not ready yet (${i}/30)..."
  sleep 2
done

log "Waiting for metrics-server..."
kubectl wait --namespace kube-system \
  --for=condition=available deployment/metrics-server \
  --timeout=180s

cat <<EOF

=== Cluster ready ===
Context: kind-${CLUSTER_NAME}
Ingress: http://localhost:${INGRESS_HOST_PORT}

Next:
  ./deploy.sh

EOF
