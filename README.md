# Coloss-AI - Press one button and create a whole infrastructure department

> Type 'up' in your terminal, press enter, and watch the magic unfold.

What do you get?
- Kubernetes Cluster via Minikube
- ArgoCD and Gitops
- Erlang backend for LLM messaging
- OpenWebUI for chat all hooked up to the backend
- Ollama for AI serving
- Haskell MCP server for K8S API read access
- Dashboard in Elixir to read Erlang and LLM telemetry

![Wire Dashboard GIF](wire-dashboard.gif)

[![Nix](https://img.shields.io/badge/Nix-Flake-blue?logo=nixos)](flake.nix)
[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-orange?logo=argo)](helm/)
[![Runtime](https://img.shields.io/badge/Runtime-Erlang%2FOTP%20%7C%20Haskell-red)](#subsystems)

---
## Quickstart

### Prerequisites
* Nix package manager with flakes enabled (`experimental-features = nix-command flakes`).
* Docker / Minikube container runtime.

### Getting Started
```bash
# 1. Enter the hermetic environment
nix develop

# 2. Format configuration (Alejandra)
nix fmt .

# 3. Bootstrap the cluster, local Gitea instance, and GitOps sync - why `up`? Custom shell command defined via Nix that runs all the setup
up
```
## System Architecture

```text
+-----------------------------------------------------------------------------------------+
|                                   Developer Workspace                                   |
|                          ( nix develop  |  Host Web Browser )                           |
+-----------------------------------------------------------------------------------------+
       |                                                                    ^
       |                                                                    | (Browser Access)
       v                                                                    |
+---------------------------------------------------------------------------|-------------+
|                              Host OS & Deterministic Layer                |             |
|                                                                           |             |
|   [ Flake Environment ] --- (Compiles Helm to Static Manifests) --+       |             |
+-------------------------------------------------------------------|-------|-------------+
                                                                    |       |
                                                                    | (Git) |
                                                                    v       |
+-----------------------------------------------------------------------+   |
|                            Git Repository                             |   |
|                                                                       |   |
|                           [ Gitea Server ]                            |   |
+-----------------------------------------------------------------------+   |
                                    |                                       |
                                    | (GitOps Sync)                         |
                                    v                                       |
+===========================================================================|=============+
|                              Kubernetes Cluster                           |             |
|                                                                           |             |
|  +------------------------------------------------------------------------|----------+  |
|  | Host Port Exposure / Ingress Layer                                     |          |  |
|  |     ArgoCD UI:            localhost:8888  <----------------------------+          |  |
|  |     OpenWebUI Chat:       localhost:9000  <----------------------------+          |  |
|  |     Telemetry Dashboard:  localhost:4000  <----------------------------+          |  |
|  +-----------------------------------------------------------------------------------+  |
|             |                                   |                           |           |
|             | (Manages Apps)                    |                           |           |
|             v                                   v                           v           |
|  +----------------------+            +-------------------+         +-----------------+  |
|  | GitOps Engine        |            | Application Tier  |         | Dashboard Tier  |  |
|  | [ ArgoCD Server/App ]|            | [ OpenWebUI ]     |         | [ Elixir Dash ] |  |
|  | (:8888)              |            | (:9000)           |         | (:4000)         |  |
|  +----------|-----------+            +---------|---------+         +--------^--------+  |
|             |                                  |                            |           |
|             |                                  | (Chat Requests)            |           |
|             |                                  v                            | (Reads    |
|             |                        +-------------------+                  |  RPC/     |
|             |                        | Agent Tier        | -----------------+  Telemetry|
|             v                        | [ Don Erleone ]   |                     Events)  |
|  +-------------------+ <(Inference)- | (BEAM / OTP)      |                              |
|  | Inference Tier    |               +---------|---------+                              |
|  | [ Ollama + GPU ]  |                         |                                        |
|  | (:11434 internal) |                         | (Tool Execution)                       |
|  +---------|---------+                         v                                        |
|            |                          [ Haskell MCP Server ]                            |
|            +-----------------------------------| (K8s API Queries)                      |
|                                                v                                        |
|                                       [ Cluster Substrate ]                             |
+=========================================================================================+
```

---
# Key Architectural Details

* **Exact, Reproducible Environments:**  
  No more "it works on my machine!". If you have Nix, you have Flakes, you run this thing, it works. Badda bing badda boom.
* **Air-Gapped GitOps Reconciliation:**  
  Helm charts are compiled into static manifests and synced to an in-cluster Gitea instance. ArgoCD tracks Gitea via declarative `ApplicationSet` definitions, and uses it as a local cluster level reconciler of state. This leads the way to great push-based scalability the more clusters you have within your fleet. 
* **Large Scale, Resilient Concurrency (BEAM):**  
  The AI/LLM backend messaging and routing layer (`Don Erleone`) leverages Erlang/OTP supervisor trees to isolate long-running agent workflows, retry states, and dynamic tool orchestration from network and pod failures. Basically, imagine a technology that is used specifically to power telecommunications used for your LLM messaging streams.
* **Type-Safe Model Context Protocol (MCP):**  
  Cluster inspection and tool boundaries are created with a custom Haskell MCP service, enforcing strict compile-time guarantees and deterministic validation over Kubernetes API interactions. This means that if it's proved to work once within Haskell, it will work forever. Mathematically provable and true to the end of days.
* **Zero-Egress Accelerated Inference:**  
  Local LLMs are served via an in-cluster Ollama deployment backed by container-level NVIDIA GPU passthrough.
  Setting up LLM and NVIDIA CUDA drivers is painful, but this setup does it for you.
---

## Subsystem Breakdown

| Tier | Primary Technologies | Architectural Role |
| :--- | :--- | :--- |
| **Tooling & Host Layer** | Nix Flakes, Justfile | 1-to-1 reproducible developer shell, pinned dependencies, deterministic code artifacts. |
| **Cluster Engine** | Minikube, Kubelet | Mirror your cloud setup locally, enabling faster testing and development parity |
| **GitOps Control Plane** | ArgoCD, Gitea, Helm | Declarative continuous delivery, auto-reconciliation, and drift correction. |
| **Agent Engine** | Erlang / OTP | Resilient actor model managing dynamic state machines, recursive tasks, and backoffs. |
| **Tool Execution** | Haskell (MCP) | Type-safe execution protocol querying the K8s API directly. |
| **Inference Layer** | Ollama, OpenWebUI | Local GPU-accelerated weights serving low-latency model evaluations. |

---

## Low-Level Operational Notes & Edge Case Findings

<details>
<summary><strong>Hardware-Level GPU Passthrough & Container Toolkit Configuration</strong></summary>

### NVIDIA Container Toolkit Runtime Patch
Ensure the Docker daemon is configured to expose the NVIDIA runtime:
```bash
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

### WSL2 Node Feature Discovery (NFD) Manual RBAC
When utilizing subcharts where parent RBAC bindings are dropped, apply the standalone service account configuration:
```yaml
# values.yaml
node-feature-discovery:
  serviceAccountName: "node-feature-discovery"
```

Manual cluster role and node labeling override:
```bash
kubectl label node sandbox-cluster-control-plane [nvidia.com/gpu.deploy.container-toolkit=true](https://nvidia.com/gpu.deploy.container-toolkit=true) --overwrite
kubectl label node sandbox-cluster-control-plane [nvidia.com/gpu.present=true](https://nvidia.com/gpu.present=true) --overwrite

# Patch NFD master node-feature exclusion if required
kubectl patch deployment gpu-operator-node-feature-discovery-master -n gpu-operator \
  --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--deny-node-feature-group=nvidia.com"}]'
```

### GPU Operator Stuck Finalizer Recovery
If tearing down or rebuilding operator namespaces with hanging finalizers:
```bash
kubectl delete clusterrolebinding gpu-operator-node-feature-discovery-prune
kubectl delete clusterrole gpu-operator-node-feature-discovery-prune
kubectl patch app infra-gpu-operator -n argocd \
  --type merge \
  -p '{"metadata":{"finalizers":null}}'
```
</details>

<details>
<summary><strong>ArgoCD ApplicationSet Resource Management</strong></summary>

To prevent resource exhaustion when running the full stack on constrained local nodes, selectively exclude heavy monitoring or database charts via `appsets.yaml`:

```yaml
kind: ApplicationSet
metadata:
  name: my-cluster-apps
spec:
  generators:
    - git:
        repoURL: [https://github.com/your-org/infra-repo.git](https://github.com/your-org/infra-repo.git)
        revision: HEAD
        directories:
          - path: apps/*
          # Exclude resource-intensive stacks locally
          - path: apps/heavy-stack-prometheus
            exclude: true
          - path: apps/resource-hog-db
            exclude: true
```
</details>

<details>
<summary><strong>Local In-Cluster Service Verification</strong></summary>

Verify connectivity between OpenWebUI and internal Ollama instances:
```bash
# Verify internal cluster DNS and model tag resolution
kubectl exec -it -n open-webui deploy/open-webui -- \
  curl [http://ollama-internal.ollama.svc.cluster.local:11434/api/tags](http://ollama-internal.ollama.svc.cluster.local:11434/api/tags)
```
</details>
