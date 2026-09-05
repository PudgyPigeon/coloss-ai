#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " ⚙️  ArgoCD: Installing & Bootstrapping Namespace..."
echo "=================================================="

# Create namespace safely
kubectl create namespace "${ARGO_CD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD via Helm using the hierarchical values path
for i in 1 2; do
  echo "🗳️  Applying configuration template (Attempt $i/2)..."
  helm template argocd "${HELM_SOURCE_PATH}/mgmt/argocd" \
    --namespace "${ARGO_CD_NAMESPACE}" \
    -f "${HELM_SOURCE_PATH}/values/${ENV_NAME}/mgmt/argocd.yaml" \
    --set global.namespaceScoped=true --include-crds \
    | kubectl apply --server-side --force-conflicts -n "${ARGO_CD_NAMESPACE}" -f - \
    || true

  sleep 3
done

echo "⏳ Waiting for ArgoCD Server to be ready (Available condition)..."
kubectl wait --for=condition=Available deployment/argocd-server -n "${ARGO_CD_NAMESPACE}" --timeout=300s

echo "🔌 Activating secure local dashboard forwarder..."
pkill -f "port-forward svc/argocd-server" || true
kubectl port-forward svc/argocd-server -n "${ARGO_CD_NAMESPACE}" "${ARGOCD_LOCAL_PORT}:${ARGOCD_SVC_PORT}" > /dev/null 2>&1 &

# Retrieve credentials
argocd-creds
