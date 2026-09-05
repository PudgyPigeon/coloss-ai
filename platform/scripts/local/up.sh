#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " 🌐 Swarm Cockpit Local Sandbox Setup Initializing"
echo "=================================================="

# 1. Start Gitea & Minikube
infra-up

# 2. Compile and load local Nix images into Minikube
load-images

# 3. Provision ArgoCD control plane
argocd-up

# 4. Push hydrated Helm manifests to Gitea
sync-helm

# 5. Open local networking tunnels
expose

echo "=================================================="
echo " 🎉 Swarm Sandbox Deck is completely operational!"
echo "=================================================="
