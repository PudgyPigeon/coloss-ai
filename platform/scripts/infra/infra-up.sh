#!/usr/bin/env bash
set -e
gitea-up
minikube-up

echo "🔗 Bridging Gitea to the Minikube network..."
docker network connect minikube ${GIT_SERVICE_NAME}

echo "✅ Infrastructure is bridged."
