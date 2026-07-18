#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

log "=== Deleting Kind cluster: ${CLUSTER_NAME} ==="
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  kind delete cluster --name "$CLUSTER_NAME"
  log "Cluster deleted."
else
  log "Cluster '${CLUSTER_NAME}' does not exist."
fi
rm -f "${SCRIPT_DIR}/.kind-config.generated.yaml"
