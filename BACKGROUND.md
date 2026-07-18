# Why two tracks (not one)

You can run a vLLM-compatible stack on Apple Silicon via **`vllm-metal`** (Metal/MLX).

You **cannot** also put that Metal path inside Kind/Docker on macOS. Docker Desktop runs a Linux VM with **no Metal device**. Cloud GPU images (`vllm/vllm-openai` + NVIDIA/AMD plugins) do not apply in that VM either.

So:

- **`native_metal/`** — high performance on the Mac
- **`kubernetes/`** — high production fidelity (real vLLM + Deployment/Service/Ingress/HPA/PDB), CPU-backed

When you move to cloud GPUs, keep the Kind manifests’ shape and swap image + GPU resources + PVC. Use `native_metal/` when you care about local latency/throughput.
