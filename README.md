# Architecture

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
|  |                   |     |    (Prompts) -----+-----> [ Don Erleone ]   |              |
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

# NOTE!
There may be drift between the apps microservices in this monorepo and other public microservice repos. 
You may need to search the Justfile here in the root and run the reconciliation yourself to pull from the
specific repos into this monorepo.

# About
Hermetic, deterministic, one-click Kubernetes cluster with Ollama + OpenWebUI + ArgoCD.

Microservices and applications within apps directory with their own READMEs and infrastructure documentation.

GPU integration may not work with your system - it depends on if your system mirrors the Nix settings 
as declared here: https://github.com/PudgyPigeon/nix-base

# Nix Commands to Run

```
# To enter shell
nix develop 

# To format (Uses Alejandra)
nix fmt .
```

# Gotchas with deployment
### Gitea localhost not updating
If the Nix shell isnt propagating changes to Gitea, just exit the shell, re-enter and run the sync command again

### Argo not updating
Sometimes you need to run the `up` command or just wait for ArgoCD to reconcile itself for around 5 minutes.

OR
`kubectl exec -n argocd -it deploy/argocd-repo-server -- rm -rf /tmp/_argocd-repo`
OR
`argocd cluster add $(kubectl config current-context) --name in-cluster `

Even if it fails it'll add some roles.

### MINIKUBE
```
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

### GPU operator recreation/deletion
```
# Run the following three commands

kubectl delete clusterrolebinding gpu-operator-node-feature-discovery-prune
kubectl delete clusterrole gpu-operator-node-feature-discovery-prune
# If finalizers are stuck
kubectl patch app infra-gpu-operator -n argocd \
  --type merge \
  -p '{"metadata":{"finalizers":null}}'

```

### GPU Node labeling on WSL2
```
kubectl label node sandbox-cluster-control-plane nvidia.com/gpu.deploy.container-toolkit=true --overwrite


kubectl label node sandbox-cluster-control-plane nvidia.com/gpu.present=true --overwrite

kubectl get node sandbox-cluster-control-plane -o jsonpath='{.metadata.labels.nvidia\.com/gpu\.present}'

kubectl patch deployment gpu-operator-node-feature-discovery-master -n gpu-operator --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--deny-node-feature-group=nvidia.com"}]'
```

### NFD GPU sub chart SA + RBAC
Created manually from custom template because there is a bug with the subchart deriving settings from the 
top level chart. Too much of a pain to deal with the subchart, just create it.
```
# values.yaml
node-feature-discovery:
  serviceAccountName: "node-feature-discovery"  <-- custom field
```

### Ollama Helm Chart running
For now no script. You need to run the following on startup:
```
kubectl port-forward svc/ollama-internal 11434:11434 -n ollama > /dev/null 2>&1 &
<!-- kubectl exec -it deploy/ollama-internal -n ollama -- ollama pull llama3.2:3b -->
kubectl exec -it deploy/ollama-internal -n ollama -- ollama pull llama3:latest
kubectl port-forward -n open-webui svc/open-webui 9000:8080 > /dev/null 2>&1 &

# Test openwebui to ollama kubectl exec -it -n open-webui deploy/open-webui -- curl http://ollama-internal.ollama.svc.cluster.local:11434/api/tags
```


### How to disable Apps/Charts if you run out of minikube space
Within `helm/mgmt/argocd/tempaltes/appsets.yaml`
```
# Example of disabling some charts by path and exclude key
kind: ApplicationSet
metadata:
  name: my-cluster-apps
spec:
  generators:
    - git:
        repoURL: https://github.com/your-org/infra-repo.git
        revision: HEAD
        directories:
          # 1. Include all apps in the folder
          - path: apps/*
          
          # 2. Exclude heavy apps to free up Minikube resources
          - path: apps/heavy-stack-prometheus
            exclude: true
          - path: apps/resource-hog-db
            exclude: true
```

# Resources
https://github.com/nvidia/k8s-device-plugin   < --- look into this if operator doesnt work>

https://github.com/nvidia/gpu-operator?tab=readme-ov-file

https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#prerequisites

https://github.com/NVIDIA/nvkind

https://www.reddit.com/r/kubernetes/comments/1ilb8v2/minikube_versus_kind_gpu_support/#:~:text=Some%20say%20that%20it's%20easier%20to%20gain,GPU%20operator**%20*%20**Kata%20containers**%20*%20**K3S%2DNVidia**

https://github.com/NVIDIA/gpu-operator/issues/662


# For models -> Look at Opus distill for smaller B models that replicate Claude Opus
https://huggingface.co/Jackrong/collections




http://don-erleone.don-erleone.svc.cluster.local:8080/v1
