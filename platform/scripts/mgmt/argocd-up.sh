#!/usr/bin/env bash
set -e
kubectl create namespace ${ARGO_CD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD via Helm using the dynamic HELM_SOURCE_PATH
for i in 1 2; do
  helm template argocd "${HELM_SOURCE_PATH}/mgmt/argocd" \
    --namespace ${ARGO_CD_NAMESPACE} \
    -f "${HELM_SOURCE_PATH}/values/sandbox/argocd.yaml" \
    --set global.namespaceScoped=true --include-crds \
    | kubectl apply --server-side --force-conflicts -n ${ARGO_CD_NAMESPACE} -f - \
    || true

  sleep 5
done

kubectl wait --for=condition=Available deployment/argocd-server -n ${ARGO_CD_NAMESPACE} --timeout=300s

pkill -f "port-forward svc/argocd-server" || true
kubectl port-forward svc/argocd-server -n ${ARGO_CD_NAMESPACE} ${ARGOCD_LOCAL_PORT}:${ARGOCD_SVC_PORT} > /dev/null 2>&1 &

argocd-creds
