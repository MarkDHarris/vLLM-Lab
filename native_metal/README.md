# Native Metal — High-Performance Inference Lab

This directory runs **`vllm-metal`** directly on macOS so inference uses Apple Silicon’s **Metal GPU** and **unified memory** through the **MLX** stack. It is the **high-performance** track in this repo.

For a **production-shaped Kubernetes** lab on the same Mac (CPU inside Kind — slower by design), see [`../kubernetes/`](../kubernetes/).

These tracks are complementary. Kind/Docker cannot access Metal on macOS, so one directory cannot be both “max tok/s” and “in-cluster production topology.”

**VS Code:** Run and Debug → **Native Metal: Server + Locust** (starts `server.py` + `locustfile.py`).

---

## Table of contents

1. [When to use this track (and when not to)](#when-to-use-this-track-and-when-not-to)
2. [How to use it for different purposes](#how-to-use-it-for-different-purposes)
3. [What you are learning](#what-you-are-learning)
4. [Why Metal must run on the host](#why-metal-must-run-on-the-host)
5. [Big picture architecture](#big-picture-architecture)
6. [Components & what each file does](#components--what-each-file-does)
7. [How a request travels](#how-a-request-travels)
8. [Unified memory, models, and sizing](#unified-memory-models-and-sizing)
9. [What `setup.sh` installs and prestages](#what-setupsh-installs-and-prestages)
10. [How `server.py` boots the engine](#how-serverpy-boots-the-engine)
11. [Load testing with Locust](#load-testing-with-locust)
12. [Observing GPU & memory](#observing-gpu--memory)
13. [Quick start](#quick-start)
14. [Configuration](#configuration)
15. [Comparison to the Kubernetes track](#comparison-to-the-kubernetes-track)
16. [Troubleshooting](#troubleshooting)
17. [Suggested learning exercises](#suggested-learning-exercises)

---

## When to use this track (and when not to)

### Use `native_metal/` when you want to…

| Purpose | Why this track fits |
|---|---|
| **Maximize tokens/sec on this Mac** | Metal + MLX; no Linux VM, no container overhead |
| **Try large local models** | Unified memory + 4-bit/OptiQ MLX weights (e.g. ~31B default) |
| **Prototype an app against a fast OpenAI API** | Point any OpenAI-compatible client at `http://127.0.0.1:8000` |
| **Study unified-memory behavior** | Watch RAM/Swap vs concurrency with Activity Monitor |
| **Benchmark quantization / model choices** | Swap `MODEL_NAME`, re-run Locust, compare latency & memory |
| **Learn in-process engine wiring** | `server.py` shows `create_engine()` + FastAPI, not only the CLI |
| **Iterate quickly** | Edit Python → restart process; no image rebuild / cluster rollout |

### Do **not** use `native_metal/` when you want to…

| Purpose | Use instead |
|---|---|
| Learn Deployments, Services, Ingress, HPA, probes | [`../kubernetes/`](../kubernetes/) |
| Model a cloud GPU/CPU inference platform topology | [`../kubernetes/`](../kubernetes/) (then map to real cloud GPUs) |
| Practice CI-like image prestaging / offline cluster bring-up | [`../kubernetes/`](../kubernetes/) |
| Run Metal *inside* Docker/Kind | **Not possible** on macOS — keep this host path |

**Rule of thumb:** if the question is “how fast can *this laptop* generate?” → `native_metal/`. If the question is “how is inference *operated* in Kubernetes?” → `kubernetes/`.

---

## How to use it for different purposes

Each purpose below is a concrete workflow. Start from a working setup (`./setup.sh` + `source .venv/bin/activate`).

### 1) Personal / local chatbot backend (developer productivity)

**Goal:** Fast completions for Cursor, scripts, notebooks, or a small UI.

```bash
python server.py
# Client base URL: http://127.0.0.1:8000/v1
# Model id: mlx-community/gemma-4-31B-it-OptiQ-4bit  (or whatever you set)
```

- Keep `HOST = "127.0.0.1"` so the API is not exposed on your LAN.
- Prefer a model that leaves headroom for the IDE and browser (if the 31B default swaps, drop to a 3B–8B MLX instruct model).

### 2) Model bake-off (quality vs speed vs memory)

**Goal:** Decide which MLX model fits your Mac and your latency budget.

1. Change `MODEL_NAME` in `server.py` and the `"model"` field in `locustfile.py`.
2. Restart the server; confirm with `curl …/v1/models`.
3. Run a short Locust swarm (fixed users / `max_tokens`).
4. Record: peak Memory, Swap, Locust p95, subjective answer quality.

Repeat for 2–3 `mlx-community/…` candidates. This is the right track because Kind CPU numbers would mislead you about Metal performance.

### 3) Concurrency / KV-cache stress test

**Goal:** See how PagedAttention-style serving behaves as users pile on.

1. Start server; open Activity Monitor → Memory.
2. Locust: start at 5 users, then 10 → 20 → 50 (spawn rate 2).
3. Watch for Swap onset — that is your practical concurrency ceiling on unified memory.
4. Optionally shorten `max_tokens` or the prompt to separate “prefill heavy” vs “decode heavy” load.

### 4) Prompt / product experimentation

**Goal:** Iterate on system prompts, tools-shaped JSON, or RAG snippets with low friction.

- Hit `/v1/chat/completions` from a notebook or `httpx`/`openai` SDK.
- No Ingress timeouts, no probe restarts — failures are just Python logs.
- When the prompt design stabilizes, you can later point the *same* OpenAI client at the Kind Ingress URL to test “client → gateway” behavior (different host/port/model).

### 5) Teaching “why Docker isn’t always faster on Mac”

**Goal:** Demonstrate the Metal vs Linux-VM gap.

1. Run the same style of Locust chat workload here (note p95).
2. Run [`../kubernetes/`](../kubernetes/) Locust against `localhost:8080` (note p95).
3. Discuss: Kind is slower because of **CPU-in-VM**, not because “Kubernetes is broken.”

### 6) Embedding the engine in a larger Python app

**Goal:** Learn programmatic lifecycle (what `server.py` teaches).

- Reuse the `create_engine` + module wiring pattern to bolt inference into a custom FastAPI app, batch job, or evaluation harness.
- Kind teaches *ops* packaging; this track teaches *in-process* integration.

### Purpose cheat-sheet

| If you care about… | Do this here |
|---|---|
| Raw speed | Largest model that fits without Swap; few concurrent users |
| Multi-user realism | Locust with rising user count; watch Swap |
| App integration | OpenAI SDK → `127.0.0.1:8000` |
| Model selection | A/B `MODEL_NAME` + fixed Locust recipe |
| K8s / Ingress / HPA | Stop — switch to `kubernetes/` |

---

## What you are learning

| Concept | What you practice here |
|---|---|
| Apple Silicon inference | Metal + MLX via community `vllm-metal` |
| Unified memory | Weights + KV-cache share system RAM (no discrete VRAM pool) |
| OpenAI-compatible serving | FastAPI/Uvicorn app exposing `/v1/chat/completions` |
| Programmatic engine lifecycle | `create_engine()` instead of only the CLI |
| Concurrent load | Locust users hitting a real local server |
| Quantization for laptops | OptiQ / 4-bit MLX weights to fit 64 GB machines |
| What Docker cannot do on Mac | Why this path stays **outside** Kind |

You are **not** practicing Ingress, HPA, or cluster networking here — that is `kubernetes/`.

---

## Why Metal must run on the host

```text
macOS process  →  Metal / MLX frameworks  →  Apple GPU + unified memory   ✅

Linux container (Docker/Kind)
       →  no Metal device, no macOS frameworks
       →  CPU-only (or cloud GPUs in real Linux clusters)                 ❌ for Metal
```

Docker Desktop on Mac runs a **Linux VM**. That VM cannot call into the host Metal stack. Therefore:

- `native_metal/` = host Python process (fast)
- `kubernetes/` = Linux vLLM CPU image in Kind (production shape, slower)

---

## Big picture architecture

```text
┌────────────────────────────────────────────────────────────────┐
│ macOS (Apple Silicon)                                          │
│                                                                │
│  Locust UI (localhost:8089)                                    │
│       │                                                        │
│       │  HTTP  http://127.0.0.1:8000/v1/chat/completions       │
│       ▼                                                        │
│  Uvicorn  ←→  FastAPI app (from vllm_metal.server)             │
│                    │                                           │
│                    ▼                                           │
│              vllm-metal engine (create_engine)                 │
│                    │                                           │
│                    ▼                                           │
│         MLX tensors on unified memory / Metal GPU              │
│                    │                                           │
│                    ▼                                           │
│   ~/.cache/huggingface/hub/models--mlx-community--...          │
└────────────────────────────────────────────────────────────────┘
```

There is **no** Service, Ingress, or kube-proxy. The “front door” is simply the process bound to `127.0.0.1:8000`.

---

## Components & what each file does

| File | Role |
|---|---|
| `setup.sh` | Creates `.venv`, installs deps, prestages MLX model weights |
| `server.py` | Boots the MLX engine and serves OpenAI HTTP on `:8000` |
| `locustfile.py` | Locust user class that POSTs chat completions for load tests |
| `.venv/` | Local Python 3.12 environment (gitignored — recreate with setup) |
| `README.md` | This learning guide |

Optional (repo root, gitignored):

| File | Role |
|---|---|
| `../hf_token` | Hugging Face token for gated/private downloads |
| `../hf_token.example` | Safe template you *can* commit |

### Runtime dependencies (installed by setup)

| Package | Why |
|---|---|
| `vllm-metal` | Community vLLM plugin; MLX/Metal backend + OpenAI server helpers |
| `mlx-optiq` | OptiQ quantization support used by some MLX community models |
| `fastapi` / `uvicorn` | HTTP server stack used by `server.py` |
| `locust` | Load generation |
| `huggingface_hub[cli]` | `hf download` for model prestaging |

---

## How a request travels

Much simpler than Kind — intentionally:

```text
Locust / curl / browser client
    │
    │  POST http://127.0.0.1:8000/v1/chat/completions
    ▼
Uvicorn (ASGI server in this process)
    │
    ▼
FastAPI routes from vllm_metal.server.app
    │
    ▼
vllm-metal engine (continuous batching / PagedAttention-style scheduling
                   on the MLX backend — implementation lives in the plugin)
    │
    ▼
MLX executes matmuls / attention on Metal
    │
    ▼
JSON chat.completion response
```

Useful endpoints once the server is up:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/models` | List served model(s) |
| `POST` | `/v1/chat/completions` | Chat generation (what Locust hits) |
| `GET` | `/health` or similar | Health (if exposed by the plugin version) |

Exact aux routes can vary by `vllm-metal` version; chat completions are the learning focus.

---

## Unified memory, models, and sizing

Apple Silicon has **no separate GPU VRAM pool**. System RAM *is* the memory budget for:

- model weights
- KV-cache (grows with concurrent users × context length)
- macOS + your other apps

Rough 4-bit MLX sizing (see also [`../docs/hardware_sizing.md`](../docs/hardware_sizing.md)):

| Scenario | Comfortable model class on 64 GB |
|---|---|
| 1 replica | up to ~70B 4-bit (with OS headroom) |
| 2 replicas | ~30–35B 4-bit each |

**Default lab model** (in `server.py`):

```text
mlx-community/gemma-4-31B-it-OptiQ-4bit
```

Why this default:

- MLX-community format (required for `vllm-metal`)
- OptiQ 4-bit → fits a single-replica 64 GB workflow
- Large enough to feel “real,” small enough to avoid immediate OOM for one server

Change `MODEL_NAME` in **both** `server.py` and `locustfile.py` (Locust sends `"model": "..."` in the JSON body — it should match what the server serves).

### Weight format warning

| Works with `vllm-metal` | Does **not** (usually) |
|---|---|
| `mlx-community/...` MLX / OptiQ repos | Raw CUDA vLLM FP16/BF16 trees |
| MLX converted / quantized checkpoints | GGUF meant for llama.cpp |

The Kind track uses a different model (`Qwen/Qwen2.5-1.5B-Instruct` safetensors) because that path runs **Linux vLLM CPU**, not MLX.

---

## What `setup.sh` installs and prestages

```bash
./setup.sh
```

Step by step:

1. **Xcode CLT check** — compilers needed to build native bits
2. **`uv` check** — fast Python env/package manager
3. **`uv venv --python 3.12 .venv`** — isolated arm64 environment  
   (Rosetta/x86_64 Python will underperform or fail — use native arm64)
4. **`uv pip install …`** — vllm-metal, mlx-optiq, fastapi, uvicorn, locust, huggingface_hub
5. **Model prestage** — if weights are missing under `$HF_HOME/hub/...`, runs `hf download`  
   - Token from `HF_TOKEN` env, else `../hf_token`, else anonymous (public models)

After setup:

```bash
source .venv/bin/activate
```

Re-run `./setup.sh` after pulling repo changes that bump dependencies, or if you delete `.venv`.

---

## How `server.py` boots the engine

`server.py` is deliberately small and educational. It does **not** shell out to `vllm serve`; it wires the engine in-process:

1. Sets logging
2. Chooses `MODEL_NAME`, `HOST` (`127.0.0.1`), `PORT` (`8000`)
3. Calls `create_engine(MODEL_NAME)` from `vllm_metal`
4. Assigns the engine onto `vllm_metal.server` module globals so the packaged FastAPI `app` can serve it
5. Starts Uvicorn on that `app`

Why bind `127.0.0.1` instead of `0.0.0.0`?

- Local lab only — not exposed on your LAN by default
- Change to `0.0.0.0` only if you intentionally want other devices to reach the server

First start after a download can take a while: weights map into unified memory and the engine warms up. Wait for the log line that the API is listening before running Locust.

---

## Load testing with Locust

`locustfile.py` defines an `HttpUser` that:

- Targets `http://127.0.0.1:8000`
- Waits 1–3 seconds between tasks
- POSTs `/v1/chat/completions` with a fixed prompt and `max_tokens: 150`
- Records success/failure under the name `"Chat Completion"`

### VS Code (recommended)

1. `Cmd+Shift+D` → **Native Metal: Server + Locust**
2. `F5`
3. Open [http://localhost:8089](http://localhost:8089)
4. Host: `http://127.0.0.1:8000`
5. Start with ~10 users, spawn rate 2 — raise carefully while watching memory

### Terminals

**Terminal 1**

```bash
cd native_metal
source .venv/bin/activate
python server.py
```

**Terminal 2**

```bash
cd native_metal
source .venv/bin/activate
locust -f locustfile.py
```

### What to watch in Locust

| Metric | Meaning |
|---|---|
| Requests/s | Throughput under concurrency |
| p95 / p99 latency | Tail latency as KV-cache + batching contend |
| Failures | Timeouts / 5xx when the machine swaps or the server is overloaded |

`stream: False` keeps the load test simple (full-response latency). For TTFT experiments, switch to streaming and custom client metrics.

---

## Observing GPU & memory

Because unified memory is shared, **Activity Monitor → Memory** is your primary dashboard:

- **Memory Used** climbing as the model loads
- **Swap Used** rising ⇒ you oversized the model or concurrency — generation will crawl

Optional GPU power samples:

```bash
sudo powermetrics --samplers gpu_power -i 1000
```

Optional wired-memory headroom (resets on reboot; advanced):

```bash
# Example: allow GPU roughly 58 GB wired (leaves ~6 GB for macOS) on a 64 GB Mac
sudo sysctl iogpu.wired_limit_mb=59392
```

See [`../docs/hardware_sizing.md`](../docs/hardware_sizing.md) before using that.

---

## Quick start

### Prerequisites

- Apple Silicon Mac (lab sized for M1 Ultra 64 GB)
- Xcode Command Line Tools (`xcode-select --install`)
- `brew install uv`
- Python 3.12 **arm64** (not Rosetta)
- Optional: copy `../hf_token.example` → `../hf_token` with a real token

### Setup & run

```bash
cd native_metal
./setup.sh
source .venv/bin/activate
python server.py
```

Smoke test (another terminal, venv active):

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/gemma-4-31B-it-OptiQ-4bit",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 64
  }'
```

Load test: VS Code compound **Native Metal: Server + Locust**, or `locust -f locustfile.py`.

---

## Configuration

| Knob | Where | Default |
|---|---|---|
| Model id | `server.py` → `MODEL_NAME` | `mlx-community/gemma-4-31B-it-OptiQ-4bit` |
| Bind address | `server.py` → `HOST` | `127.0.0.1` |
| Port | `server.py` → `PORT` | `8000` |
| Locust host | `locustfile.py` → `host` | `http://127.0.0.1:8000` |
| Locust model field | `locustfile.py` payload `"model"` | must match server |
| HF cache | env `HF_HOME` / setup default | `~/.cache/huggingface` |
| HF token | env `HF_TOKEN` or `../hf_token` | optional |

Override model at setup/download time:

```bash
MODEL_NAME=mlx-community/Llama-3.2-3B-Instruct-4bit ./setup.sh
```

Remember to edit `server.py` / `locustfile.py` to match if you change the running model.

---

## Comparison to the Kubernetes track

| | `native_metal/` | `kubernetes/` |
|---|---|---|
| Goal | Max performance on this Mac | Production control-plane fidelity |
| Compute | Metal / MLX | Linux CPU vLLM in Kind |
| Entry URL | `http://127.0.0.1:8000` | `http://localhost:8080` (Ingress) |
| Orchestration | None (one process) | Deployment, Service, Ingress, HPA, PDB |
| Default model | MLX OptiQ ~31B | Qwen 1.5B safetensors |
| Front door | Uvicorn bind | Kind port map → ingress-nginx |
| When to use | Latency / tok/s / memory experiments | Learning k8s inference topology |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Import / build errors for vllm-metal | Missing CLT or x86 Python | `xcode-select --install`; confirm `python` is arm64 (`uname -m` / `file $(which python)`) |
| Download 401 / gated model | Missing HF token | Set `HF_TOKEN` or create `../hf_token` from `hf_token.example` |
| Slow as mud + Swap rising | Model / concurrency too large | Smaller model, fewer Locust users, shorter `max_tokens` |
| Locust connection refused | Server not up yet | Wait for Uvicorn listen log; check port 8000 |
| Locust 4xx on model name | Payload model ≠ loaded model | Align `locustfile.py` `"model"` with `server.py` |
| “Works in Kind but not here” (or reverse) | Different backends/formats | MLX weights ≠ Linux vLLM safetensors trees |
| Want this inside Docker for speed | Not available with Metal | Keep dual tracks |

---

## Suggested learning exercises

1. **Memory ceiling:** Load the default 31B OptiQ model, note Activity Monitor, then raise Locust users until Swap appears — correlate with latency.
2. **Smaller model A/B:** Switch to `mlx-community/Llama-3.2-3B-Instruct-4bit` in server + locustfile; compare tok/s and memory.
3. **Streaming:** Set `"stream": true` and inspect chunked responses with `curl -N` (then decide how you’d measure TTFT).
4. **Bind address:** Temporarily use `HOST = "0.0.0.0"` and call from another device on your LAN — then revert (security awareness).
5. **Contrast with Kind:** Run the same Locust shape against `kubernetes/` (`localhost:8080`) and write down latency differences — attribute them to CPU-in-VM vs Metal, not to “broken k8s.”

---

## Security notes

- Do **not** commit `hf_token` or real API keys (gitignored; use `hf_token.example` as a template).
- Default bind is localhost-only; exposing `0.0.0.0` shares an unauthenticated OpenAI-compatible API on your network.
- Model weights under `~/.cache/huggingface` stay on your machine; they are not part of this git repo.
