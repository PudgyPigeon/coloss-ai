#!/usr/bin/env bash
pkill -f "port-forward svc/argocd-server" || true
docker rm -f ${GIT_SERVICE_NAME} || true

if [[ "$1" == "--delete" ]]; then
    echo "💣 Nuking the cluster..."
    minikube delete
else
    echo "✋ Stopping the cluster..."
    minikube stop
fi
