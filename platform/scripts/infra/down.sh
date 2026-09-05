#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " 💣 Teardown: Stopping local cluster resources"
echo "=================================================="

pkill -f "port-forward" || true
docker rm -f "${GIT_SERVICE_NAME}" || true

if [[ "${1:-""}" == "--delete" ]]; then
    echo "💥 Nuking the Minikube virtual environment..."
    minikube delete
else
    echo "🛑 Safely stopping the Minikube cluster (state preserved)..."
    minikube stop
fi

echo "✅ Teardown complete."
