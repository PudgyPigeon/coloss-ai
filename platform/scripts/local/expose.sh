#!/usr/bin/env bash
pkill -f "kubectl port-forward"
kubectl port-forward svc/argocd-server -n ${ARGO_CD_NAMESPACE} ${ARGOCD_LOCAL_PORT}:${ARGOCD_SVC_PORT} > /dev/null 2>&1 &
kubectl port-forward -n open-webui svc/open-webui ${OPEN_WEBUI_DEST_PORT}:${OPEN_WEBUI_SOURCE_PORT} > /dev/null 2>&1 &
