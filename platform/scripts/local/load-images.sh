#!/usr/bin/env bash
set -euo pipefail

# Connect Docker client to Minikube daemon
eval $(minikube docker-env)

if [ -z "${IMAGE_LOAD_COMMANDS:-""}" ]; then
  echo "⚠️  No image load commands configured. Skipping image builds."
  exit 0
fi

echo "📦 Running project-specific image load commands..."
# Safely execute the build commands in Minikube's Docker runtime
eval "${IMAGE_LOAD_COMMANDS}"

echo "✅ Success: All Swarm container images loaded."
