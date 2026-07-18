# Architecture: Metal vs Kind vs Cloud

Performance and production topology are split on purpose. One process on macOS cannot do both.

## Track A — Native Metal (`native_metal/`)

```text
Locust / clients
       │
       ▼
 vllm-metal (macOS process)
       │
       ▼
 Apple Silicon GPU + Unified Memory (MLX)
```

Fastest path on this Mac. OpenAI-compatible API. MLX weights (`mlx-community/...`). No Kubernetes objects.

## Track B — Kind production simulation (`kubernetes/`)

```text
Locust / clients
       │
       ▼
 localhost:8080
       │
       ▼
 ingress-nginx
       │
       ▼
 inference-api (ClusterIP)
       │
       ▼
 vllm-server Deployment  (vllm/vllm-openai-cpu)
       │
       ▼
 Linux VM CPU  +  hostPath HF cache
```

Also: metrics-server, HPA, PDB, ConfigMap, optional HF Secret — same shape as the [vLLM Kubernetes guide](https://docs.vllm.ai/en/latest/deployment/k8s/), with CPU instead of GPU.

## What does not work on macOS

| Idea | Reality |
|---|---|
| `vllm-metal` inside a Linux container | No Metal in the Docker VM |
| Pass the Mac GPU into Kind | No supported Metal → Linux path |
| Kind CPU tok/s ≈ native Metal | Kind will be far slower |

## Cloud mapping

Keep Deployment / Service / Ingress / HPA / PDB. Switch to a GPU vLLM image, request `nvidia.com/gpu` (or equivalent), replace hostPath with a PVC.
