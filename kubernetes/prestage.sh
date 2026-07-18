#!/usr/bin/env bash
# Pre-download models and container images so Kind bring-up has visible progress
# and does not sit silently for minutes pulling into the cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

log "=== Prestage: models + images for Kind production simulation ==="

require_cmd kind "brew install kind"
require_cmd kubectl "brew install kubectl"
require_cmd curl "comes with macOS"
check_docker

HF_CACHE_HOST="$(expand_path "$HF_CACHE_HOST")"
mkdir -p "${HF_CACHE_HOST}/hub"
log "Hugging Face cache: ${HF_CACHE_HOST}"

# ---- Model weights (host-side, with progress) ----
download_model() {
  local token model_dir
  token="$(resolve_hf_token)"
  model_dir="${HF_CACHE_HOST}/hub/models--${MODEL_NAME//\//--}"

  if find "$model_dir" \( -name '*.safetensors' -o -name 'pytorch_model.bin' \) 2>/dev/null | grep -q .; then
    log "Model already present: ${MODEL_NAME}"
    return
  fi

  log "Downloading model ${MODEL_NAME} into ${HF_CACHE_HOST} (progress below)..."
  require_cmd hf "pipx install 'huggingface_hub[cli]'  # or: uv tool install huggingface_hub"

  # HF_HOME owns the standard hub/ layout expected by the pod mount.
  if [[ -n "$token" ]]; then
    HF_HOME="$HF_CACHE_HOST" HF_TOKEN="$token" hf download "$MODEL_NAME"
  else
    HF_HOME="$HF_CACHE_HOST" hf download "$MODEL_NAME"
  fi
  log "Model download complete."
}

download_model

# ---- Container images (host Docker, with pull progress) ----
IMAGES=(
  "$KIND_NODE_IMAGE"
  "$VLLM_IMAGE"
  "registry.k8s.io/ingress-nginx/controller:v1.12.1"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.2"
  "registry.k8s.io/metrics-server/metrics-server:v0.7.2"
)

log "Pulling ${#IMAGES[@]} container images into local Docker (this is the slow step; Kind will load them locally later)..."
for img in "${IMAGES[@]}"; do
  log "→ docker pull ${img}"
  docker pull "$img"
done

# ---- Locust venv ----
ensure_locust_venv
log "Locust ready: $(command -v locust)"

# ---- Generate Kind config so you can inspect the absolute mount path ----
cfg="$(generate_kind_config "${SCRIPT_DIR}/.kind-config.generated.yaml")"
log "Generated Kind config: ${cfg}"
log "  hostPath mount: ${HF_CACHE_HOST} -> ${HF_CACHE_NODE} (read-only)"

cat <<EOF

=== Prestage complete ===
Next steps:
  1. Ensure Docker Desktop Memory >= ${MIN_DOCKER_MEM_GIB} GB (24 GB recommended).
  2. ./start_cluster.sh     # creates Kind, loads images, installs Ingress + metrics-server
  3. ./deploy.sh            # deploys vLLM + Service + Ingress + HPA
  4. ./smoke_test.sh        # curls the OpenAI-compatible endpoint

EOF
