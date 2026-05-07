#!/usr/bin/env bash
set -e
PASS=$(kubectl -n ${ARGO_CD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "--------------------------------------------------"
echo " You can log into your localhost cluster ArgoCD Portal:"
echo "👤 User: admin"
echo "🔑 Pass: $PASS"
echo "🌐 URL:  https://localhost:${ARGOCD_LOCAL_PORT}"
echo "--------------------------------------------------"
