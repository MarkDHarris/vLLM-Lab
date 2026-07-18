# Local vLLM Learning Lab (Apple Silicon)

Two complementary tracks on a MacBook Pro (M1 Ultra / 64 GB). **You need both** — Kind cannot use Metal, so one stack cannot be both maximum performance and in-cluster production shape on macOS.

| Track | Directory | Goal | Compute |
|---|---|---|---|
| High performance | [`native_metal/`](native_metal/) | Max tokens/sec on this Mac | Metal / MLX (`vllm-metal`) |
| High production fidelity | [`kubernetes/`](kubernetes/) | Model a cloud k8s inference platform | Official vLLM CPU image in Kind |

Kind is **not** a replacement for `native_metal/`. It is the accurate production control-plane lab. Expect much lower tok/s than native Metal — that tradeoff is intentional.

## Which track for which purpose?

| Purpose | Use |
|---|---|
| Fastest local generation / large MLX models / Metal GPU | [`native_metal/`](native_metal/) |
| Prototype an app against a quick OpenAI-compatible server | [`native_metal/`](native_metal/) |
| Study unified memory, quantization, concurrency ceilings | [`native_metal/`](native_metal/) |
| Learn Deployment / Service / Ingress / HPA / probes | [`kubernetes/`](kubernetes/) |
| Practice kubectl ops, rollouts, 503s, Endpoints | [`kubernetes/`](kubernetes/) |
| Rehearse production-shaped bring-up (prestage → deploy) | [`kubernetes/`](kubernetes/) |
| Prepare mental model for cloud GPU vLLM on k8s | [`kubernetes/`](kubernetes/) |
| Compare “laptop speed” vs “cluster shape” for teaching | Run **both**, same Locust-style client |

Details and step-by-step purpose workflows live in each directory’s README.

## Quick start

### A — High performance (Metal)

```bash
cd native_metal
./setup.sh
source .venv/bin/activate
python server.py          # http://127.0.0.1:8000
# VS Code: Run "Native Metal: Server + Locust"
# or: locust -f locustfile.py  → http://localhost:8089
```

### B — Production fidelity (Kind)

```bash
cd kubernetes
./prestage.sh             # model + images with progress
./start_cluster.sh
./deploy.sh
./smoke_test.sh           # http://localhost:8080
# VS Code: Run "Kubernetes: Locust (locustfile.py)"
```

Docker Desktop → **Memory ≥ 16 GB** (24 GB recommended).

## VS Code

**Run and Debug** (`Cmd+Shift+D`):

- `Native Metal: Server + Locust` — starts Metal server + Locust UI
- `Native Metal: Locust (locustfile.py)` — Locust only (server already up)
- `Kubernetes: Locust (locustfile.py)` — Locust against Kind Ingress `:8080`

**Tasks** (`Cmd+Shift+P` → *Tasks: Run Task*): setup / prestage / start / deploy / smoke / delete.

## Docs

- [Architecture: Metal vs Kind vs cloud](docs/architecture.md)
- [Hardware sizing (64 GB Macs)](docs/hardware_sizing.md)
- [Resources & pro-tips](docs/resources.md)
- [Background: why two tracks](BACKGROUND.md)

## Security

Do not commit tokens or personal paths.

- Copy [`hf_token.example`](hf_token.example) → `hf_token` (gitignored), or export `HF_TOKEN`
- Never commit `hf_token`, `.env`, kubeconfigs, or `kubernetes/.kind-config.generated.yaml` (contains your absolute home path)
