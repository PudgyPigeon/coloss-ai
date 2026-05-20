#!/usr/bin/env bash
set -euo pipefail

PASS=$(kubectl -n "${ARGO_CD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "\n\033[1;35m┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
echo -e "\033[1;35m┃ 🛡️  ArgoCD Local Cluster Credentials                    ┃\033[0m"
echo -e "\033[1;35m┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\033[0m"
echo -e "\033[1;35m┃ 👤 Username:  \033[1;32madmin\033[1;35m                                   ┃\033[0m"
echo -e "\033[1;35m┃ 🔑 Password:  \033[1;32m${PASS}\033[1;35m                               ┃\033[0m"
echo -e "\033[1;35m┃ 🌐 Web Portal: \033[1;36mhttps://localhost:${ARGOCD_LOCAL_PORT}\033[1;35m              ┃\033[0m"
echo -e "\033[1;35m┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m\n"
