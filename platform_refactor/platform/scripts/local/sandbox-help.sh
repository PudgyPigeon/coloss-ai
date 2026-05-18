#!/usr/bin/env bash
set -euo pipefail

echo -e "\n\033[1;36m┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
echo -e "\033[1;36m┃ 🛠️  Swarm Sandbox Command Reference Manual             ┃\033[0m"
echo -e "\033[1;36m┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\033[0m"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "up" "Provision the full stack (Infra + ArgoCD)"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "gitea-up" "Start local GitOps source (Gitea)"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "minikube-up" "Provision Minikube cluster VM"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "infra-up" "Provision Minikube and Gitea"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "argocd-up" "Bootstrap ArgoCD and create port forwards"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "argocd-creds" "Show credentials and Web Portal details"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "helm-deps-update" "Update Helm subcharts dependencies"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "sync-helm" "Hydrate manifests and sync to local GitOps"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "expose" "Bind background networking port tunnels"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "load-images" "Load custom OCI images into Minikube"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "down" "Stop Minikube and delete Gitea context"
printf "\033[1;36m┃ \033[1;32m%-18s\033[1;37m %-36s\033[1;36m ┃\n" "down --delete" "Nuke Minikube VM & delete all local PVCs"
echo -e "\033[1;36m┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m\n"
