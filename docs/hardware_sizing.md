# Hardware Sizing & Memory Limits (64 GB Macs)

Apple Silicon uses **Unified Memory**: the same 64 GB pool backs CPU and GPU. macOS typically leaves headroom for the OS, so GPU-heavy workloads often see on the order of **~48 GB** usable before the system starts paging hard.

A 4-bit quantized MLX model is roughly **0.6–0.7 GB per 1B parameters**, plus KV-cache for context.

## Track A — Native Metal (`native_metal/`)

### One replica (max model size)

* **Max model size:** ~70B (4-bit)
* **Examples:** `mlx-community/Meta-Llama-3-70B-Instruct-4bit`, `mlx-community/Qwen2.5-72B-Instruct-4bit`
* **Why:** ~40–42 GB weights, still room for a modest context window inside ~48 GB

Default lab model in `native_metal/server.py` is `mlx-community/gemma-4-31B-it-OptiQ-4bit` (single replica). Two concurrent Metal replicas roughly double weight memory — size carefully on a 64 GB Mac.

> **Optional (resets on reboot):** allow the GPU a larger wired limit:
> ```bash
> sudo sysctl iogpu.wired_limit_mb=59392   # ~58 GB, leaves ~6 GB for macOS
> ```

## Track B — Kind / Docker Desktop (`kubernetes/`)

Kind runs inside the **Docker Desktop Linux VM**. That VM’s memory slider is separate from macOS free RAM.

| Docker Desktop Memory | Result |
|---|---|
| ~8 GB (common default) | **Too small** — Kind + Ingress + vLLM will OOM or thrash |
| 16 GB | Minimum for the default `Qwen/Qwen2.5-1.5B-Instruct` lab |
| 24 GB | Recommended on a 64 GB Mac |
| 32 GB+ | Comfortable if you raise `MAX_MODEL_LEN` or try 2 HPA replicas |

Default Kind lab model is intentionally small (**1.5B**, `float16`, `max-model-len=2048`) so the production topology fits a laptop VM. Do not compare its tok/s to `native_metal/`.

### Resource requests in the Deployment

The vLLM Deployment requests **2 CPU / 8 Gi** and limits **6 CPU / 14 Gi**, with `--gpu-memory-utilization 0.35` (on the CPU backend this flag is the fraction of **host RAM** reserved). Undersizing the Pod limit relative to that reservation causes `OOMKilled` even when Docker Desktop itself has free RAM.

## Practical rules

1. **Native Metal:** size models against unified memory + Activity Monitor.
2. **Kind:** size models against the Docker Desktop VM slider first, then against Pod limits.
3. **Never** assume a model cached for MLX will run in the Kind vLLM CPU image (different weight formats / runtimes).
4. Prestage weights and images on the host (`kubernetes/prestage.sh`) so the cluster does not download multi‑GB artifacts with no progress UI.
