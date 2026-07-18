# Kubernetes (Kind) — Production-Fidelity Inference Lab

This directory is a **learning lab** that simulates a production Kubernetes LLM inference platform on an Apple Silicon Mac using [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker).

It intentionally does **not** use Metal / `vllm-metal` and does **not** replace [`../native_metal/`](../native_metal/). Docker Desktop runs a Linux VM with **no Mac GPU**. Use this track to learn production topology; use `native_metal/` for high performance.

**VS Code:** Run and Debug → **Kubernetes: Locust (locustfile.py)** (cluster must already be deployed).

---

## Table of contents

1. [When to use this track (and when not to)](#when-to-use-this-track-and-when-not-to)
2. [How to use it for different purposes](#how-to-use-it-for-different-purposes)
3. [What you are learning](#what-you-are-learning)
4. [Big picture architecture](#big-picture-architecture)
5. [Layers of the stack (outside → inside)](#layers-of-the-stack-outside--inside)
6. [What must be running for inference to work](#what-must-be-running-for-inference-to-work)
7. [Kubernetes objects we deploy (and why)](#kubernetes-objects-we-deploy-and-why)
8. [Platform components (not our app, but required)](#platform-components-not-our-app-but-required)
9. [How traffic reaches the cluster](#how-traffic-reaches-the-cluster)
10. [Model weights & storage design](#model-weights--storage-design)
11. [Image prestaging & why Kind needs special handling](#image-prestaging--why-kind-needs-special-handling)
12. [Probes, resources, and failure modes](#probes-resources-and-failure-modes)
13. [Autoscaling (HPA) end-to-end](#autoscaling-hpa-end-to-end)
14. [Scripts walkthrough](#scripts-walkthrough)
15. [Quick start](#quick-start)
16. [Configuration reference](#configuration-reference)
17. [Exploring the live cluster (kubectl tour)](#exploring-the-live-cluster-kubectl-tour)
18. [Cloud production mapping](#cloud-production-mapping)
19. [Troubleshooting](#troubleshooting)
20. [Common design pitfalls we already fixed](#common-design-pitfalls-we-already-fixed)

---

## When to use this track (and when not to)

### Use `kubernetes/` when you want to…

| Purpose | Why this track fits |
|---|---|
| **Learn production inference topology** | Real Deployment → Service → Ingress → Pod path |
| **Practice kubectl day-2 ops** | Logs, describes, Endpoints, rollouts, HPA, Events |
| **Understand gateways vs ClusterIP** | Why clients hit Ingress (`:8080`), not pod IPs |
| **See probes gate traffic** | 503 while not Ready; Endpoints empty until `/health` passes |
| **Experiment with autoscaling concepts** | HPA + metrics-server (even if the laptop can’t fit 2 replicas) |
| **Rehearse offline/CI-style bring-up** | `prestage.sh` + image import + vendored platform manifests |
| **Prepare for cloud vLLM on k8s** | Same object shape; later swap CPU image → GPU image + PVC |
| **Debug “which layer broke?”** | Isolate Mac port vs Ingress vs Service vs Pod vs model load |

### Do **not** use `kubernetes/` when you want to…

| Purpose | Use instead |
|---|---|
| Fastest possible generation on this MacBook | [`../native_metal/`](../native_metal/) |
| Large MLX / OptiQ models at interactive speed | [`../native_metal/`](../native_metal/) |
| Metal / unified-memory GPU acceleration | [`../native_metal/`](../native_metal/) — Kind has no Metal |
| A single process with minimal moving parts | [`../native_metal/`](../native_metal/) |

**Rule of thumb:** if the question is “how is inference *operated* like production?” → `kubernetes/`. If the question is “how fast can *this laptop* generate?” → `native_metal/`.

Expect **much lower** tokens/sec here than Metal. That is not a failure of the lab — it is the cost of running Linux vLLM CPU inside Docker Desktop’s VM.

---

## How to use it for different purposes

Assume the stack is up (`./prestage.sh` → `./start_cluster.sh` → `./deploy.sh` → `./smoke_test.sh`). Entry URL: **`http://localhost:8080`**.

### 1) Learn the production request path (primary purpose)

**Goal:** Internalize Ingress → Service → Pod.

```bash
curl -i http://localhost:8080/v1/models
kubectl get ingress,svc,endpointslices,pods
kubectl -n ingress-nginx get pods,svc
```

Trace a single request using the [traffic section](#how-traffic-reaches-the-cluster). Change nothing until you can explain each hop without notes.

### 2) Platform / SRE practice (failures & recovery)

**Goal:** Operate the system when pieces break.

| Experiment | What you learn |
|---|---|
| `kubectl scale deploy/vllm-server --replicas=0` then curl | Ingress 503 / empty Endpoints |
| Break readiness probe path, apply, watch | Traffic drains before process dies |
| `kubectl delete pod -l app.kubernetes.io/name=vllm` | Deployment self-heals; brief unavailability |
| `kubectl rollout restart deploy/vllm-server` | RollingUpdate with `maxSurge: 0` on a laptop |
| Stop Docker / delete cluster / recreate | Disaster recovery via scripts |

Always `kubectl describe` + Events before guessing.

### 3) Client integration against a “gateway” URL

**Goal:** Point an app at something that looks like a cluster front door (not a raw pod).

- Base URL: `http://localhost:8080/v1`
- Model: `Qwen/Qwen2.5-1.5B-Instruct` (default)
- Same OpenAI SDK code as Metal — only host/port/model change

Use this when teaching “clients should not hardcode pod IPs.”

### 4) Load test the *platform*, not the GPU

**Goal:** Stress Ingress timeouts, queueing, readiness under load — not win a Metal benchmark.

```bash
source .venv/bin/activate
locust -f locustfile.py   # → http://localhost:8089 , host http://localhost:8080
# or VS Code: Kubernetes: Locust (locustfile.py)
```

Watch simultaneously:

- Locust failure rate / latency
- `kubectl get pods -w` (restarts? Ready flaps?)
- `kubectl get hpa vllm-hpa -w` (CPU metrics appear?)
- `kubectl logs deploy/vllm-server`

If you need “how many tok/s can M1 Ultra do?”, stop and use `native_metal/`.

### 5) Autoscaling & capacity lessons

**Goal:** See HPA react — and learn why desired replicas ≠ schedulable replicas.

```bash
kubectl get hpa vllm-hpa -w
kubectl top pods
# Drive CPU with Locust; observe whether a 2nd replica is attempted
```

On one Kind node with a 14Gi limit, a second replica may Pending/OOM. That is a **successful lesson** about cluster capacity planning.

### 6) Config / release workflow practice

**Goal:** Change model knobs without rebuilding images.

1. Edit `config.env` (`MAX_MODEL_LEN`, `GPU_MEMORY_UTILIZATION`, or `MODEL_NAME` — if you change model, prestage weights first).
2. `./deploy.sh` (rewrites ConfigMap + rolls Deployment).
3. Watch rollout: `kubectl rollout status deploy/vllm-server`.

This mirrors ConfigMap-driven releases in production (plus a real rollout).

### 7) Cloud migration rehearsal (mental model)

**Goal:** Use this lab as a checklist before EKS/GKE/AKS.

Keep: Deployment, Service, Ingress, HPA, PDB, probes, ConfigMap/Secret patterns.  
Swap later: image → GPU vLLM, resources → `nvidia.com/gpu`, hostPath → PVC, Kind port map → cloud LoadBalancer.

Work through [Cloud production mapping](#cloud-production-mapping) with that lens.

### 8) Side-by-side with Metal (teaching / decision making)

| Question | Metal | Kind |
|---|---|---|
| Fast local demo for stakeholders? | Yes | No |
| “Show me our k8s inference architecture”? | No | Yes |
| Tune prompts / models interactively? | Yes | Only with tiny models |
| Interview prep for platform/MLOps roles? | Partial | Yes |

### Purpose cheat-sheet

| If you care about… | Do this here |
|---|---|
| Architecture literacy | kubectl tour + traffic diagram |
| Reliability | Break probes / delete pods / watch heal |
| Gateway clients | SDK → `localhost:8080` |
| Load on the control/data plane | Locust + HPA + logs |
| Peak Mac GPU speed | Switch to `native_metal/` |

---

## What you are learning

In cloud production, an inference platform is rarely “one container and a port.” It is a **control plane + data plane** system:

| Production concern | What you practice here |
|---|---|
| Run N copies of a model server | `Deployment` (`vllm-server`) |
| Stable in-cluster DNS name | `Service` (`inference-api`) |
| External HTTP front door | `Ingress` + `ingress-nginx` |
| Scale replicas under load | `HorizontalPodAutoscaler` + `metrics-server` |
| Protect availability during drains | `PodDisruptionBudget` |
| Inject non-secret config | `ConfigMap` (`vllm-config`) |
| Inject secrets (HF token) | `Secret` (`hf-token-secret`) |
| Health / traffic gating | startup / liveness / readiness probes |
| CPU & memory budgeting | `resources.requests` / `limits` |
| Model artifact caching | hostPath mount of Hugging Face cache |
| OpenAI-compatible API | real **vLLM** (`vllm/vllm-openai-cpu`) |

CPU inference inside Kind will be **much slower** than native Metal. That is expected. The goal is fidelity of **shape and operations**, not tokens/sec.

---

## Big picture architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ macOS (your MacBook)                                                    │
│                                                                         │
│  Locust / curl / browser                                                │
│       │                                                                 │
│       │  http://localhost:8080                                          │
│       ▼                                                                 │
│  Docker Desktop Linux VM  (~16–24 GiB RAM recommended)                  │
│       │                                                                 │
│       │  Kind node container (kindest/node)                             │
│       │                                                                 │
│       ├─ kube-system: API server, scheduler, controller-manager, DNS… │
│       ├─ ingress-nginx: HTTP gateway (north-south)                      │
│       ├─ metrics-server: CPU/memory metrics for HPA                     │
│       └─ default:                                                       │
│            Ingress → Service → Deployment Pod (vLLM)                    │
│                 ▲                                                       │
│                 └── hostPath: ~/.cache/huggingface (read-only)          │
└─────────────────────────────────────────────────────────────────────────┘
```

Mental model:

- **Kind** = a real Kubernetes control plane + one worker (combined into the control-plane node for this lab), running as Docker containers.
- **Your app** = vLLM + the Kubernetes objects in `manifests/`.
- **Platform** = Ingress controller + metrics-server (vendored under `manifests/platform/`).
- **Host Mac** = prestages images/weights and publishes port `8080` into the Kind node.

---

## Layers of the stack (outside → inside)

Think in layers. Each layer has a job; skipping one breaks the story.

### Layer 0 — Host tools

| Tool | Role |
|---|---|
| Docker Desktop | Provides the Linux VM + container runtime Kind uses |
| `kind` | Creates/deletes the local Kubernetes cluster |
| `kubectl` | Talks to the Kubernetes API |
| `hf` / Hugging Face cache | Downloads model weights onto the Mac |
| Locust (`.venv`) | Load-tests the OpenAI HTTP API |

### Layer 1 — Kind cluster node

Kind runs a container named like `vllm-cluster-control-plane` using image `kindest/node:v1.32.2`.

That container is a **Kubernetes node**. Inside it you get:

- `kubelet` (manages pods)
- containerd (pulls/runs images)
- networking (CNI — Kind uses kindnet)
- the kube-apiserver and other control-plane components (single-node Kind)

Kind also applies our **extraPortMappings** and **extraMounts** (generated into `.kind-config.generated.yaml`).

### Layer 2 — Kubernetes platform add-ons

These are not vLLM, but production clusters almost always need equivalents:

1. **ingress-nginx** — implements `Ingress` resources (HTTP reverse proxy / L7 gateway)
2. **metrics-server** — scrapes kubelet resource metrics so HPA can scale on CPU

### Layer 3 — Application stack (our manifests)

1. ConfigMap / Secret — configuration
2. Deployment — runs vLLM pods
3. Service — stable ClusterIP + DNS
4. Ingress — public HTTP route
5. HPA — replica autoscaling
6. PDB — disruption policy

### Layer 4 — Process inside the pod

`vllm serve …` exposes OpenAI-compatible endpoints such as:

- `GET /v1/models`
- `POST /v1/chat/completions`
- `GET /health` (used by probes)

---

## What must be running for inference to work

If **any** of these are missing, clients fail in different ways:

| Component | Namespace | If missing… |
|---|---|---|
| Kind cluster | n/a | `kubectl` has no context / connection refused |
| CoreDNS | `kube-system` | Services may not resolve by DNS name |
| ingress-nginx controller Pod | `ingress-nginx` | `localhost:8080` connection refused / 502 |
| Ingress object `vllm-ingress` | `default` | nginx has no route (404) |
| Service `inference-api` | `default` | Ingress backend missing (502/503) |
| Deployment `vllm-server` Ready | `default` | Service has no Ready endpoints (503) |
| metrics-server | `kube-system` | HPA shows `<unknown>` (inference can still work) |
| HF model cache mount | host → node → pod | vLLM fails offline / cannot load weights |
| vLLM image present on node | node containerd | ImagePullBackOff (we prestage to avoid this) |

**Inference path requires:** Kind + Ingress controller + Ingress + Service + Ready Pod (+ weights + image).

**Autoscaling path additionally requires:** metrics-server + HPA.

---

## Kubernetes objects we deploy (and why)

All app manifests live under `manifests/` and share labels like:

```yaml
app.kubernetes.io/name: vllm
app.kubernetes.io/part-of: vllm-learning-lab
```

Those labels are how Services, HPAs, and PDBs select the right pods — production style.

### 1. ConfigMap — `vllm-config`

**File:** `manifests/configmap.yaml` (also regenerated by `deploy.sh` from `config.env`)

Holds non-secret knobs:

- `MODEL_NAME` — Hugging Face model id (also used as `--served-model-name`)
- `MAX_MODEL_LEN` — caps context / KV-cache size
- `GPU_MEMORY_UTILIZATION` — on the **CPU** backend this is the fraction of **host RAM** vLLM may reserve (historical flag name)

Why a ConfigMap instead of hardcoding in the image? So you can change model/len without rebuilding containers — standard 12-factor / k8s practice.

### 2. Secret — `hf-token-secret`

Created by `deploy.sh` from `HF_TOKEN` or repo-root `hf_token`.

Mounted into the pod as env `HF_TOKEN` (optional). Needed for gated models; the default Qwen 1.5B model is public.

Never commit real tokens. `hf_token` is gitignored.

### 3. Deployment — `vllm-server`

**File:** `manifests/deployment.yaml`

This is the heart of the workload.

| Setting | What it teaches |
|---|---|
| `replicas: 1` | Desired count of Pods |
| `selector` / pod labels | How Kubernetes knows which Pods belong to this Deployment |
| `RollingUpdate` with `maxSurge: 0` | On a laptop we cannot surge a second 14Gi vLLM pod |
| `enableServiceLinks: false` | Stops k8s from injecting `FOO_SERVICE_HOST` env vars into the process |
| `command` / `args` | Runs `vllm serve …` with ConfigMap-driven values |
| `imagePullPolicy: IfNotPresent` | Prefer local image (prestaged into Kind) |
| `HF_HUB_OFFLINE=1` | Fail fast if weights are missing (no silent in-cluster download) |
| Probes on `/health` | Startup vs liveness vs readiness (see below) |
| `resources.requests/limits` | Scheduler + cgroup budget |
| `hostPath` volume | Model cache from Kind node path `/var/local/huggingface` |
| `emptyDir` medium Memory for `/dev/shm` | Production-shaped shared-memory volume (critical for many GPU vLLM setups) |

**Why the Service is not named `vllm-service`:** Kubernetes injects env vars named after Services into every pod (unless disabled). A Service named `vllm-*` creates `VLLM_*` variables that confuse the vLLM process. We name it `inference-api` and also set `enableServiceLinks: false`.

### 4. Service — `inference-api`

**File:** `manifests/service.yaml`

Type: **ClusterIP**.

- Creates a stable virtual IP + DNS name: `inference-api.default.svc.cluster.local`
- Selects pods with `app.kubernetes.io/name: vllm`
- Forwards port `8000` → pod targetPort `http` (8000)

This is **east-west** networking (inside the cluster). Ingress talks to this Service. Your laptop does not.

### 5. Ingress — `vllm-ingress`

**File:** `manifests/ingress.yaml`

Declares the **north-south** HTTP route:

- `ingressClassName: nginx` → handled by ingress-nginx
- path `/` → backend Service `inference-api:8000`
- annotations raise proxy timeouts / body size for long LLM generations

An Ingress object is only a **routing rule**. The actual proxy process is the ingress-nginx controller Deployment.

### 6. HorizontalPodAutoscaler — `vllm-hpa`

**File:** `manifests/hpa.yaml`

- Watches Deployment `vllm-server`
- Scales between `minReplicas: 1` and `maxReplicas: 2`
- Target: average CPU utilization 80%
- Scale-up/down policies slow thrashing

On a single Kind node with a large memory pod, scaling to 2 may OOM — that is a useful production lesson about **capacity vs desired replicas**.

### 7. PodDisruptionBudget — `vllm-pdb`

**File:** `manifests/pdb.yaml`

Limits voluntary disruptions (node drains, some cluster upgrades). Here `maxUnavailable: 1` so a single-replica laptop lab can still be disrupted. In multi-replica cloud, you often want `minAvailable: 1` (or higher).

---

## Platform components (not our app, but required)

Installed by `start_cluster.sh` from vendored YAML under `manifests/platform/`.

### ingress-nginx

**Why required:** Without a controller, `Ingress` objects do nothing.

Key pieces:

| Object | Purpose |
|---|---|
| Deployment `ingress-nginx-controller` | nginx reverse proxy pods |
| Service `ingress-nginx-controller` | Exposes 80/443 (NodePort in Kind’s published template) |
| IngressClass `nginx` | Binds Ingress resources to this controller |
| Admission webhooks | Validates Ingress objects on apply |

Kind’s ingress-nginx template expects the node label `ingress-ready=true` (we set that in the Kind config) and listens on node ports 80/443 — which Kind then maps from the host.

### metrics-server

**Why required for HPA:** The HPA controller needs the Metrics API (`metrics.k8s.io`) to read pod CPU/memory.

Kind-specific patch (already applied in our vendored file):

- `--kubelet-insecure-tls`
- `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname`

Without those, metrics-server often cannot scrape Kind kubelets, and HPA stays `<unknown>`.

Verify:

```bash
kubectl -n kube-system get deploy metrics-server
kubectl top nodes
kubectl top pods
```

---

## How traffic reaches the cluster

`locustfile.py` uses:

```python
INGRESS_HOST_PORT = os.environ.get("INGRESS_HOST_PORT", "8080")
```

That **8080** is the **Mac host** port. It is *not* the ClusterIP `8000` on `inference-api`.

### Why `kubectl get svc` only shows ClusterIP `:8000`

```bash
kubectl get svc
# NAME            TYPE        CLUSTER-IP     PORT(S)
# inference-api   ClusterIP   10.96.x.x      8000/TCP
```

That listing is **in-cluster** Services in `default`. Your Mac never dials `10.96.x.x` directly.

External entry uses Kind port publishing + Ingress:

1. Kind maps **host `8080` → node container port `80`** (`extraPortMappings` in `.kind-config.generated.yaml`)
2. **ingress-nginx** listens on port 80 inside the node
3. Ingress `vllm-ingress` routes `/` → `inference-api:8000`
4. Service load-balances to Ready vLLM pod(s) on container port **8000**

This mirrors production: clients hit a load balancer / Ingress, not pod IPs.

### Path from browser / Locust → model

```text
Browser / Locust / curl
    │
    │  http://localhost:8080/v1/chat/completions
    ▼
Mac host port 8080
    │
    │  Kind extraPortMappings (hostPort → containerPort)
    ▼
Kind node container port 80
    │
    ▼
ingress-nginx-controller Pod   (namespace: ingress-nginx)
    │  reads Ingress rules
    │  path / → service inference-api:8000
    ▼
Service inference-api          (ClusterIP :8000, namespace: default)
    │  selects Ready pods by label
    ▼
Pod vllm-server-*              (container port 8000)
    │
    ▼
vllm OpenAI HTTP server
```

Inspect gateway pieces:

```bash
kubectl get ingress
kubectl -n ingress-nginx get svc,pods
kubectl get endpointslices -l kubernetes.io/service-name=inference-api
```

`Endpoints` / `EndpointSlice` must list the pod IP once the pod is Ready. Empty endpoints ⇒ 503 from Ingress.

---

## Model weights & storage design

### Host cache (Mac)

Weights live at:

```text
$HOME/.cache/huggingface/hub/models--Qwen--Qwen2.5-1.5B-Instruct/...
```

`prestage.sh` downloads them with the Hugging Face CLI so you see progress on the Mac.

### Kind node mount

Kind config mounts that directory into the **node** at:

```text
/var/local/huggingface   (read-only)
```

### Pod mount

The Deployment mounts the node path into the container:

```text
hostPath /var/local/huggingface  →  /root/.cache/huggingface  (readOnly)
```

With `HF_HOME=/root/.cache/huggingface` and `HF_HUB_OFFLINE=1`, vLLM loads local snapshots and will not hang on Hub downloads.

### Why not a PVC in this lab?

Cloud production usually uses a PVC/CSI volume. Kind can do PVCs (local-path provisioner), but binding your already-downloaded Mac HF cache via hostPath is:

- faster to iterate
- easier to prestage with visible progress
- durable across cluster delete/recreate (weights stay on the Mac)

When you move to cloud, keep the Deployment volumeMount path and swap the volume source to a PVC.

---

## Image prestaging & why Kind needs special handling

### Two different image stores

| Where | Runtime | What `docker images` shows |
|---|---|---|
| Docker Desktop (host) | Docker engine | Yes |
| Kind node | containerd | Separate store |

`docker pull` alone does **not** put an image into Kind.

### What our scripts do

1. **`prestage.sh`** — `docker pull` on the Mac (progress UI)
2. **`start_cluster.sh`** — import into Kind via `docker save | ctr import`  
   (`kind load docker-image` often fails on multi-arch manifests under Docker Desktop on Apple Silicon)

Images prestaged:

- `kindest/node:v1.32.2`
- `vllm/vllm-openai-cpu:latest`
- ingress-nginx controller + webhook certgen
- metrics-server

Platform YAML is **vendored** so `start_cluster.sh` does not depend on GitHub being fast at apply time.

---

## Probes, resources, and failure modes

### Three probes (all hit `GET /health`)

| Probe | Question it answers | Our settings (summary) |
|---|---|---|
| **Startup** | “Has the process finished loading weights yet?” | every 10s, up to ~10 minutes (`failureThreshold: 60`) |
| **Liveness** | “Is the process wedged? Should we restart it?” | every 20s, 3 failures → kill |
| **Readiness** | “Should this pod receive Service traffic?” | every 5s; until Ready, Endpoints stay empty |

During model load, readiness stays false → Ingress returns **503** (no endpoints). That is correct behavior, not a broken Ingress.

### Resources

```yaml
requests: { cpu: "2", memory: 8Gi }   # scheduler / HPA baseline
limits:   { cpu: "6", memory: 14Gi }  # cgroup hard cap
```

vLLM’s `--gpu-memory-utilization` on CPU backends reserves a fraction of **node RAM**. If that reservation exceeds the container **memory limit**, the kernel OOM-kills the process (`OOMKilled`, exit 137) even if Docker Desktop still has free memory overall.

We keep `GPU_MEMORY_UTILIZATION=0.35` and a 14Gi limit so the worker fits.

---

## Autoscaling (HPA) end-to-end

```text
Pod CPU usage
    │
    ▼
kubelet summary API
    │
    ▼
metrics-server  (aggregates → metrics.k8s.io)
    │
    ▼
HPA controller  (compares to target 80% CPU)
    │
    ▼
scales Deployment.spec.replicas
    │
    ▼
ReplicaSet creates/terminates Pods
    │
    ▼
Service Endpoints update automatically
```

Useful commands:

```bash
kubectl get hpa vllm-hpa -w
kubectl describe hpa vllm-hpa
kubectl get deploy vllm-server -w
```

On this laptop, treat multi-replica scale-up as an experiment in **capacity planning**, not a goal.

---

## Scripts walkthrough

| Script | Responsibility |
|---|---|
| `config.env` | Defaults (model, image, ports, memory gate) |
| `lib.sh` | Shared helpers: logging, Docker mem check, Kind config generation, image import |
| `prestage.sh` | Download model + pull images + Locust venv + generate Kind config |
| `start_cluster.sh` | `kind create`, import images, install Ingress + metrics-server, wait |
| `deploy.sh` | Secret + ConfigMap + app manifests; wait for rollout with live pod status |
| `smoke_test.sh` | `curl` `/v1/models` and `/v1/chat/completions` via localhost:8080 |
| `run_end_to_end.sh` | prestage → start → deploy → smoke → short Locust → optional teardown |
| `delete_cluster.sh` | `kind delete cluster` |
| `locustfile.py` | Locust user hitting Ingress OpenAI API |
| `kind-config.yaml` | **Reference only** — do not use `~` in hostPath |
| `.kind-config.generated.yaml` | Absolute-path config written by scripts (gitignored) |

Recommended learning loop:

```bash
./prestage.sh
./start_cluster.sh
./deploy.sh
./smoke_test.sh
# explore with kubectl (section below)
# Locust UI or VS Code "Kubernetes: Locust (locustfile.py)"
./delete_cluster.sh   # when finished
```

---

## Quick start

### Prerequisites

- Docker Desktop on Apple Silicon
- Docker Desktop → Settings → Resources → **Memory ≥ 16 GB** (24 GB recommended), Apply & Restart
- `brew install kind kubectl`
- `uv` and Hugging Face CLI (`hf`) on PATH
- Optional: repo-root `hf_token` or `HF_TOKEN` for gated models

### Bring it up

```bash
cd kubernetes

./prestage.sh        # once (or when model/images change)
./start_cluster.sh
./deploy.sh
./smoke_test.sh
```

### Call the API

```bash
curl http://localhost:8080/v1/models

curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen2.5-1.5B-Instruct",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 64
  }'
```

### Load test (Locust UI)

```bash
source .venv/bin/activate   # created by prestage.sh
locust -f locustfile.py     # open http://localhost:8089
# Host defaults to http://localhost:8080 via INGRESS_HOST_PORT
```

### One-shot lab

```bash
./run_end_to_end.sh                 # tears cluster down at the end
KEEP_CLUSTER=1 ./run_end_to_end.sh  # leave it running
```

### Tear down

```bash
./delete_cluster.sh
```

---

## Configuration reference

Edit `config.env` or export overrides before running scripts:

| Variable | Default | Meaning |
|---|---|---|
| `CLUSTER_NAME` | `vllm-cluster` | Kind cluster name / context `kind-vllm-cluster` |
| `MODEL_NAME` | `Qwen/Qwen2.5-1.5B-Instruct` | HF model id + served name |
| `VLLM_IMAGE` | `vllm/vllm-openai-cpu:latest` | ARM64 CPU vLLM image |
| `INGRESS_HOST_PORT` | `8080` | localhost → Kind node :80 → Ingress |
| `MAX_MODEL_LEN` | `2048` | caps KV-cache |
| `GPU_MEMORY_UTILIZATION` | `0.35` | CPU-backend host RAM fraction for vLLM |
| `HF_CACHE_HOST` | `$HOME/.cache/huggingface` | Mac cache (expanded to absolute path) |
| `HF_CACHE_NODE` | `/var/local/huggingface` | Path inside Kind node |
| `KIND_NODE_IMAGE` | `kindest/node:v1.32.2` | Kind node image |
| `MIN_DOCKER_MEM_GIB` | `16` | safety gate |

Override example:

```bash
export MODEL_NAME=Qwen/Qwen2.5-0.5B-Instruct
export INGRESS_HOST_PORT=8080
ALLOW_LOW_DOCKER_MEM=1 ./start_cluster.sh   # not recommended
```

---

## Exploring the live cluster (kubectl tour)

After `./deploy.sh` succeeds, walk the objects:

```bash
# Context
kubectl config current-context    # should be kind-vllm-cluster

# Namespaces & platform
kubectl get ns
kubectl -n ingress-nginx get pods,svc
kubectl -n kube-system get deploy metrics-server coredns

# App objects
kubectl get deploy,po,svc,ingress,hpa,pdb,cm,secret
kubectl describe deploy vllm-server
kubectl describe ingress vllm-ingress
kubectl get endpointslices -l kubernetes.io/service-name=inference-api

# Runtime
kubectl logs -f deploy/vllm-server
kubectl exec -it deploy/vllm-server -- ls /root/.cache/huggingface/hub | head

# Metrics (needs metrics-server)
kubectl top nodes
kubectl top pods
kubectl get hpa vllm-hpa
```

Relate labels to selection:

```bash
kubectl get pods -l app.kubernetes.io/name=vllm -o wide
kubectl get svc inference-api -o yaml | less   # look at selector:
```

---

## Repo layout

```text
kubernetes/
  README.md                  ← you are here
  config.env                 # knobs
  lib.sh                     # shared helpers
  prestage.sh
  start_cluster.sh
  deploy.sh
  smoke_test.sh
  run_end_to_end.sh
  delete_cluster.sh
  kind-config.yaml           # reference only (never use '~' in hostPath)
  locustfile.py
  manifests/
    configmap.yaml
    deployment.yaml
    service.yaml
    ingress.yaml
    hpa.yaml
    pdb.yaml
    platform/
      ingress-nginx.yaml
      metrics-server.yaml    # Kind TLS patches included
```

---

## Cloud production mapping

Keep the **shape**; swap the **substrate**:

| This Kind lab | Typical cloud production |
|---|---|
| `vllm/vllm-openai-cpu` | `vllm/vllm-openai` (CUDA) or ROCm image |
| CPU requests/limits only | + `nvidia.com/gpu: 1` (or vendor resource) |
| hostPath HF cache | PVC / CSI volume (or model cache DaemonSet / OCI) |
| Kind `extraPortMappings` :8080 | Cloud LB / Ingress Controller Service (LoadBalancer) |
| Single Kind node | Multi-node GPU pool + topology / taints |
| Optional HF Secret | ExternalSecrets / cloud secret manager |
| Locust on laptop | k6 / Locust / vegeta from CI or a load VPC |

Official reference: [vLLM on Kubernetes](https://docs.vllm.ai/en/latest/deployment/k8s/).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Refusing to continue` about Docker memory | Docker VM &lt; 16 GiB | Raise Docker Desktop Memory (≥ 16, prefer 24) |
| Pod `OOMKilled` / exit 137 | limit limit &lt; vLLM reservation | Raise memory limit and/or lower `GPU_MEMORY_UTILIZATION` |
| `localhost:8080` connection refused | Ingress controller not Ready / wrong port | `kubectl -n ingress-nginx get pods`; confirm `INGRESS_HOST_PORT` |
| HTTP 503 from Ingress | Pod not Ready / empty Endpoints | `kubectl get pods`; `kubectl logs deploy/vllm-server` |
| HTTP 404 from Ingress | Ingress missing / wrong class | `kubectl get ingress`; ensure `ingressClassName: nginx` |
| ImagePullBackOff | Image not in Kind containerd | Re-run `./prestage.sh` + `./start_cluster.sh` |
| Offline / HF errors | Weights not mounted or incomplete | Re-run `./prestage.sh`; check hub folder on Mac |
| HPA `<unknown>` | metrics-server unhealthy | `kubectl -n kube-system logs deploy/metrics-server` |
| Webhook apply errors | Admission not ready yet | `./deploy.sh` retries; or wait ~30s after start |
| vLLM warns on `VLLM_*` env | Bad Service name / service links | We use `inference-api` + `enableServiceLinks: false` |
| `kind load` digest errors | Multi-arch + Docker Desktop quirk | Scripts use `docker save \| ctr import` |

---

## Common design pitfalls we already fixed

These are worth remembering for interviews / real clusters:

1. **`~` in Kind `hostPath` does not expand** — use absolute paths only (scripts generate them).
2. **Host Docker images ≠ Kind images** — always import into the node’s containerd.
3. **Docker Desktop RAM is separate from macOS free RAM** — Kind + vLLM live inside the VM slider.
4. **Never name a Service `vllm` / `vllm-*`** if the process reads `VLLM_*` env vars — Kubernetes service discovery env injection will collide.
5. **`--gpu-memory-utilization` on CPU still reserves host memory** — size Pod limits accordingly or get `OOMKilled`.
6. **Surge during RollingUpdate can schedule a second huge pod** — laptop Kind uses `maxSurge: 0`.
7. **Ingress ≠ Service ≠ Pod** — three different objects; learn which layer failed before changing YAML at random.

---

## Suggested learning exercises

1. Break readiness: change the probe path to `/nope`, apply, watch Endpoints empty and Ingress 503, then fix.
2. Watch scale: run Locust hard, `kubectl get hpa -w`, see if a second replica is attempted (and whether the node can fit it).
3. Compare ports: curl `localhost:8080` (works) vs ClusterIP from the Mac (does not) vs `kubectl port-forward svc/inference-api 8000:8000` (bypass Ingress).
4. Delete the Ingress object only — observe that the Service/Pod still work via port-forward but localhost:8080 breaks.
5. Read `kubectl describe` on a failing pod before reading logs — Events often name the real problem (OOM, probe, mount).
