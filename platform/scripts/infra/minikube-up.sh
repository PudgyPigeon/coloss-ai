#!/usr/bin/env bash
set -euo pipefail

if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "=================================================="
  echo " 🎡 Starting Minikube ${ENV_NAME} environment..."
  echo "=================================================="

  minikube start \
    --driver=docker \
    --container-runtime=docker \
    --gpus=nvidia.com \
    --cpus "${CPU_COUNT}" \
    --memory "${MEM_COUNT}" \
    --nodes "${NODE_COUNT}" \
    --kubernetes-version=stable \
    --force-systemd=true
else
  echo "🎡 Minikube is already running."
fi

echo "✅ Success: Minikube is active."
