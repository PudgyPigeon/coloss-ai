#!/usr/bin/env bash
set -euo pipefail

# Spin up services
gitea-up
minikube-up

echo "🔗 Bridging Gitea to the Minikube network bridge..."
# Safely connect if not already connected
if ! docker network inspect minikube | grep -q "${GIT_SERVICE_NAME}"; then
  docker network connect minikube "${GIT_SERVICE_NAME}"
fi

echo "=================================================="
echo " ✅ Success: Infrastructure is up and bridged."
echo "=================================================="
