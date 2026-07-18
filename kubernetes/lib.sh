#!/usr/bin/env bash
# Shared helpers for the Kind / vLLM production simulation.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/config.env"

# Allow shell overrides after sourcing defaults.
CLUSTER_NAME="${CLUSTER_NAME:-vllm-cluster}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai-cpu:latest}"
MODEL_NAME="${MODEL_NAME:-Qwen/Qwen2.5-1.5B-Instruct}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.35}"
INGRESS_HOST_PORT="${INGRESS_HOST_PORT:-8080}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.32.2}"
HF_CACHE_HOST="${HF_CACHE_HOST:-${HOME}/.cache/huggingface}"
HF_CACHE_NODE="${HF_CACHE_NODE:-/var/local/huggingface}"
MIN_DOCKER_MEM_GIB="${MIN_DOCKER_MEM_GIB:-16}"

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required. Install via: $2"
}

expand_path() {
  # Expand ~ and make absolute.
  local p="$1"
  p="${p/#\~/$HOME}"
  if [[ "$p" != /* ]]; then
    p="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
  fi
  printf '%s' "$p"
}

docker_mem_gib() {
  # Docker Desktop VM total memory in GiB (integer).
  docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1024/1024/1024}'
}

check_docker() {
  require_cmd docker "brew install --cask docker (then start Docker Desktop)"
  docker info >/dev/null 2>&1 || die "Docker daemon is not reachable. Start Docker Desktop and retry."
  local mem
  mem="$(docker_mem_gib)"
  if [[ -z "$mem" || "$mem" -lt "$MIN_DOCKER_MEM_GIB" ]]; then
    warn "Docker Desktop VM has ~${mem:-0} GiB RAM; this stack needs >= ${MIN_DOCKER_MEM_GIB} GiB."
    warn "Docker Desktop → Settings → Resources → Memory → ${MIN_DOCKER_MEM_GIB} GB (24 GB recommended on a 64 GB Mac), then Apply & Restart."
    if [[ -n "${ALLOW_LOW_DOCKER_MEM:-}" ]]; then
      warn "ALLOW_LOW_DOCKER_MEM is set; continuing anyway (OOM risk)."
    else
      die "Refusing to continue. Re-run with ALLOW_LOW_DOCKER_MEM=1 to override."
    fi
  else
    log "Docker Desktop VM memory: ${mem} GiB (ok)"
  fi
}

resolve_hf_token() {
  # Preference: HF_TOKEN env → repo hf_token file → empty.
  if [[ -n "${HF_TOKEN:-}" ]]; then
    printf '%s' "$HF_TOKEN"
    return
  fi
  local token_file="${ROOT_DIR}/../hf_token"
  if [[ -f "$token_file" ]]; then
    # Support both raw token and HF_TOKEN="..." forms.
    local raw
    raw="$(tr -d '\r' < "$token_file" | head -n 1)"
    raw="${raw#HF_TOKEN=}"
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw#\'}"
    raw="${raw%\'}"
    printf '%s' "$raw"
    return
  fi
  printf ''
}

generate_kind_config() {
  local out="${1:-${ROOT_DIR}/.kind-config.generated.yaml}"
  local host_cache
  host_cache="$(expand_path "$HF_CACHE_HOST")"
  mkdir -p "$host_cache"

  cat > "$out" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  image: ${KIND_NODE_IMAGE}
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: ${INGRESS_HOST_PORT}
    protocol: TCP
  extraMounts:
  # IMPORTANT: hostPath must be an absolute path. Kind does NOT expand '~'.
  - hostPath: ${host_cache}
    containerPath: ${HF_CACHE_NODE}
    readOnly: true
EOF
  printf '%s' "$out"
}

ensure_locust_venv() {
  if [[ -n "${VIRTUAL_ENV:-}" ]] && command -v locust >/dev/null 2>&1; then
    return
  fi
  require_cmd uv "brew install uv"
  if [[ ! -d "${ROOT_DIR}/.venv" ]]; then
    log "Creating Locust virtualenv..."
    uv venv --python 3.12 "${ROOT_DIR}/.venv"
  fi
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.venv/bin/activate"
  if ! command -v locust >/dev/null 2>&1; then
    log "Installing Locust..."
    uv pip install locust
  fi
}

kind_node_name() {
  printf '%s-control-plane' "$CLUSTER_NAME"
}

# Load a host Docker image into Kind's containerd.
# NOTE: `kind load docker-image` passes --all-platforms/--digests to ctr, which
# fails on many multi-arch manifests under Docker Desktop on Apple Silicon.
# Plain `docker save | ctr import` is the reliable path here.
load_image_into_kind() {
  local img="$1"
  local node
  node="$(kind_node_name)"

  if docker exec "$node" crictl images 2>/dev/null | awk 'NR>1 {print $1":"$2}' | grep -Fqx "$img"; then
    log "Image already present in Kind: ${img}"
    return
  fi

  log "Loading image into Kind via docker save | ctr import: ${img}"
  docker save "$img" | docker exec -i "$node" ctr --namespace=k8s.io images import --snapshotter=overlayfs -
  log "Loaded: ${img}"
}
