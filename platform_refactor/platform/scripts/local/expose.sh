#!/usr/bin/env bash
set -euo pipefail

echo "🔌 Re-building local background port-forwards..."

pkill -f "kubectl port-forward" || true

# Forward ArgoCD
kubectl port-forward svc/argocd-server -n "${ARGO_CD_NAMESPACE}" "${ARGOCD_LOCAL_PORT}:${ARGOCD_SVC_PORT}" > /dev/null 2>&1 &

# Forward Open WebUI
kubectl port-forward -n open-webui svc/open-webui "${OPEN_WEBUI_DEST_PORT}:${OPEN_WEBUI_SOURCE_PORT}" > /dev/null 2>&1 &

# Forward Wire Dashboard
kubectl port-forward -n wire svc/wire "${WIRE_LOCAL_PORT}:${WIRE_SVC_PORT}" > /dev/null 2>&1 &

echo "✅ Port-forwards established. Tunnels active in background."
