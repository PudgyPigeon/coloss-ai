#!/usr/bin/env bash
set -e

if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "🎡 Starting Minikube with GPU support..."

  minikube start \
    --driver=docker \
    --container-runtime=docker \
    --gpus=nvidia.com \
    --cpus ${CPU_COUNT} \
    --memory ${MEM_COUNT} \
    --nodes ${NODE_COUNT} \
    --kubernetes-version=stable \
    --force-systemd=true

fi

echo "✅ Minikube is UP."
