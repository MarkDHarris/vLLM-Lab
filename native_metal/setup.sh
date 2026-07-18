#!/usr/bin/env bash
set -euo pipefail

echo "=== Native Metal vLLM Setup ==="

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools not found. Installing..."
  xcode-select --install
  echo "Finish the GUI installer, then re-run this script."
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not installed. Install with: brew install uv"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODEL_NAME="${MODEL_NAME:-mlx-community/gemma-4-31B-it-OptiQ-4bit}"
HF_HOME="${HF_HOME:-${HOME}/.cache/huggingface}"
model_dir="${HF_HOME}/hub/models--${MODEL_NAME//\//--}"

echo "Initializing Python 3.12 virtual environment..."
uv venv --python 3.12 .venv

# shellcheck disable=SC1091
source .venv/bin/activate

echo "Installing dependencies (vllm-metal, mlx-optiq, fastapi, uvicorn, locust, huggingface_hub)..."
uv pip install vllm-metal mlx-optiq fastapi uvicorn locust "huggingface_hub[cli]"

resolve_token() {
  if [[ -n "${HF_TOKEN:-}" ]]; then
    printf '%s' "$HF_TOKEN"
    return
  fi
  local token_file="${SCRIPT_DIR}/../hf_token"
  if [[ -f "$token_file" ]]; then
    local raw
    raw="$(tr -d '\r' < "$token_file" | head -n 1)"
    raw="${raw#HF_TOKEN=}"
    raw="${raw#\"}"; raw="${raw%\"}"
    raw="${raw#\'}"; raw="${raw%\'}"
    printf '%s' "$raw"
    return
  fi
  printf ''
}

echo "Prestaging model weights for ${MODEL_NAME} into ${HF_HOME}..."
if find "$model_dir" \( -name '*.safetensors' -o -name '*.npz' -o -name 'model*.msgpack' \) 2>/dev/null | grep -q .; then
  echo "Model already present — skipping download."
else
  token="$(resolve_token)"
  if [[ -n "$token" ]]; then
    HF_HOME="$HF_HOME" HF_TOKEN="$token" hf download "$MODEL_NAME"
  else
    HF_HOME="$HF_HOME" hf download "$MODEL_NAME"
  fi
  echo "Model download complete."
fi

cat <<EOF

Setup complete.

  source .venv/bin/activate
  python server.py

Locust (separate terminal):

  source .venv/bin/activate
  locust -f locustfile.py

EOF
