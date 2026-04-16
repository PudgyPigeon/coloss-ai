# Localhost Agent Architecture

Welcome to the localhost_agent project. This document provides a comprehensive overview of the system's architecture, design decisions, and data flows.

Whether you are a new developer or an AI evaluating the repository, this guide will explain how the pieces fit together.

---

## 1. Core Philosophy

This project builds a **local-first, deterministic Kubernetes environment** designed for AI and LLM (Large Language Model) operations. It is built on three core pillars:

1.  **Hermetic Environments (`Nix`):** If a project works on one machine, it should work exactly the same on another. We use Nix to define all development dependencies.
2.  **GitOps Driven (`ArgoCD` & `Gitea`):** Kubernetes deployments are never applied manually. The entire state of the cluster is stored as YAML in a Git repository, and an agent (ArgoCD) continuously synchronizes the cluster to match Git.
3.  **Agentic Infrastructure (`MCP`):** The cluster isn't just hosting AI; it is manageable *by* AI. We use a custom Model Context Protocol (MCP) server to allow LLMs to natively converse with and manage the Kubernetes cluster.

---

## 2. High-Level Architecture Diagram

```text
+-----------------------------------------------------------------------------------------+
|                                    User / Developer                                     |
|                                    ( runs 'up' )                                        |
+-----------------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------------+
|                              Host OS & Nix Environment                                  |
|                                                                                         |
|  [ Nix Dev Shell ] --- (compiles Helm to YAML) ---> [ sync-helm script ]                |
|  ( flake.nix )                                              |                           |
+-----------------------------------------------------------------------------------------+
                                                              | (pushes raw YAML)
                                                              v
+-----------------------------------------------------------------------------------------+
|                              Local Docker Services                                      |
|                                                                                         |
|                                [ Local Gitea ]                                          |
|                              (Git Server / Source)                                      |
+-----------------------------------------------------------------------------------------+
                                          | (polls for changes & reconciles)
                                          v 
+=========================================================================================+
|                                Minikube Cluster                                         |
|                                                                                         |
|  +-----------------------------------------------------------------------------------+  |
|  | 1. Mgmt Tier                                                                      |  |
|  |                                                                                   |  |
|  |     [ ArgoCD ] <------- (GitOps Engine)            [ cert-manager ]               |  |
|  +-----------------------------------------------------------------------------------+  |
|            |                         |                         |                        |
|            v                         v                         v   (syncs)              |
|  +-------------------+     +-------------------+     +-------------------+              |
|  | 2. Infra Tier     |     | 4. Apps Tier      |     | 3. Agents Tier    |              |
|  |                   |     |                   |     |                   |              |
|  | [ Gateway API ]   |     |                   |     |                   |              |
|  |       |           |     |                   |     |                   |              |
|  |  (HTTPRoute) -----+-----> [ OpenWebUI ]     |     |                   |              |
|  |                   |     |        |          |     |                   |              |
|  |                   |     |    (Prompts) -----+-----> [ Rig/Swarm ]     |              |
|  |                   |     |                   |     |      |     |      |              |
|  | [ Ollama ] <------+---- (LLM Inference) ----+------------+     |      |              |
|  |                   |     |                   |     |            |      |              |
|  | [ Haskell MCP ] <-+---- (Tool Execution) ---+------------------+      |              |
|  +--------|----------+     +-------------------+     +-------------------+              |
|           |                                                                             |
|           v   (queries)                                                                 |
|     ( K8s API )                                                                         |
+=========================================================================================+
```

---

## 3. The Layers Explained

### Layer 1: The Foundation (Nix)
Normally, setting up a cluster requires installing `kubectl`, `helm`, `minikube`, Haskell compilers, and specific versions of each. 

Here, **Nix** (`flake.nix` & `shell.nix`) handles this entirely. When you run `nix develop`:
- Nix creates an isolated sub-shell and downloads the exact versions of every binary needed. 
- It injects custom bash scripts into your `$PATH` (like `up`, `minikube-up`, and `sync-helm`).
- **Hardware Acceleration:** The `minikube-up` script natively configures Docker to mount local GPUs (`--gpus=nvidia.com`), allowing local hardware to dynamically accelerate the in-cluster LLM instances. 

### Layer 2: The GitOps Loop (Gitea -> ArgoCD)
Most Kubernetes tutorials tell you to run `helm install`. **We do not do that here.** We use a strict GitOps pattern:

1.  **Rendering (`nix/helm.nix`):** When you run `sync-helm`, Nix treats Helm merely as a templating engine. It compiles the `helm/` directory into flat `.yaml` manifest files safely inside a Nix read-only sandbox.
2.  **Storage (`Gitea`):** The `up` script spawns a local Gitea instance via Docker. The rendered YAML is pushed to a repository on this local Git server.
3.  **Synchronization (`ArgoCD`):** ArgoCD runs inside the Minikube cluster. It is configured to continuously watch the local Gitea repository. When it sees new YAML files, it applies them natively.

This guarantees that the Git repository is the absolute, unimpeachable source of truth for the cluster.

### Layer 3: Cluster Tiers (`helm/` directory)
The cluster applications are split into logical tiers:

*   **`mgmt/` (Management):** Contains ArgoCD itself. It is bootstrapped first so it can manage everything else.
*   **`infra/` (Infrastructure):** Foundational services.
    *   `ollama`: Responsible for loading and running open-source LLMs (like Llama 3) locally on your hardware.
    *   `metrics-server`: Required for autoscaling (HPA) and running `kubectl top`.
    *   `ingress-nginx`: Maps internal UI services safely out of the cluster.
    *   `cert-manager`: Issues internal TLS certificates.
*   **`apps/` (Applications):** The actual logic and user-facing workloads.
    *   `open-webui`: A ChatGPT-style frontend for talking to Ollama.
    *   `kubernetes-mcp`: Our custom integration agent.

---

## 4. The Kubernetes MCP Server (In-depth)

Located in `apps/kubernetes-mcp`, this is the most unique piece of the project. It is a custom microservice written in **Haskell**.

### What is MCP?
The Model Context Protocol (MCP) is an open standard that allows LLMs to interact with external data sources and execution environments. By providing an MCP server, an AI like Claude inherently "knows" how to use the specific tools we expose.

### Architecture & Security
Instead of forcing LLMs to write raw bash commands, this microservice exposes cluster telemetry as strongly-typed functions (e.g., `list_pods`, `get_pod_logs`, `describe_deployment`).

1.  **Template Haskell & ADTs:** The operations are defined as Algebraic Data Types (ADTs) in `Types.hs`. At compile time, Template Haskell inspects these types and automatically generates the JSON Schema advertised to the LLM via MCP. This ensures API consistency without manually updating spec files.
2.  **Execution (`kubectl` Subprocesses):** To avoid the massive overhead of linking against the official Kubernetes client libraries, the server relies on typed `kubectl` subprocesses.
3.  **In-Cluster Authentication (RBAC):** When deployed via Helm, the MCP pod mounts a Kubernetes `ServiceAccount`. We define a `ClusterRole` granting this account strictly read-only access to vital namespaces. `kubectl` inherently uses this service account token, ensuring the LLM agent is safely bounded by Kubernetes RBAC rules.
4.  **Health Sidecar:** Standard Kubernetes probes expect standard HTTP responses, but the primary transport here is an MCP stream (`Stdio` or `HTTP`). The Haskell app forks a lightweight HTTP server (`WAI/Warp`) running on port `30091` uniquely serving `/health` and `/status` to keep the deployment stable inside the cluster.

---

## 5. Overlay Configuration (Values)

In the `helm/values/` directory, you will find environment folders like `sandbox/` and `prod/`.

This pattern allows us to reuse the *same* base Helm templates across different potential environments (like ephemeral test clusters or local development). When `sync-helm` runs, it:
1. Loads the base `values.yaml` from the component directory.
2. Combines it with the environment-specific values overlay (e.g., `helm/values/sandbox/kubernetes-mcp.yaml`).

This guarantees that dev, staging, and production environments execute the exact same logic, differing exclusively in configuration state.
