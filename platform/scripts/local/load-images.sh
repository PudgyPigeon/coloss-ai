#!/usr/bin/env bash
set -e
eval $(minikube docker-env)

if [ -z "$IMAGE_LOAD_COMMANDS" ]; then
  echo "⚠️  No image load commands configured. Skipping image build/load."
  exit 0
fi

echo "📦 Running project-specific image load commands..."
# Execute the commands passed from Nix
eval "$IMAGE_LOAD_COMMANDS"

echo "✅ All custom images loaded into Minikube!"
