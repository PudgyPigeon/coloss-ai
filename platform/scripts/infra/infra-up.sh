#!/usr/bin/env bash
set -euo pipefail

: "${GIT_SERVICE_NAME:=gitea}"

# Spin up services
gitea-up
minikube-up

echo "🔗 Bridging Gitea to the Minikube network bridge..."

# Wait up to 10 seconds for the Docker bridge network to appear
until docker network inspect minikube >/dev/null 2>&1; do
  echo "Waiting for minikube network bridge..."
  sleep 2
done

# Connect Gitea to minikube network if not already connected
if ! docker network inspect minikube --format '{{range .Containers}}{{.Name}} {{end}}' | grep -qw "${GIT_SERVICE_NAME}"; then
  docker network connect minikube "${GIT_SERVICE_NAME}"
  echo "Connected ${GIT_SERVICE_NAME} to minikube network."
else
  echo "${GIT_SERVICE_NAME} is already attached to minikube network."
fi

echo "=================================================="
echo " ✅ Success: Infrastructure is up and bridged."
echo "=================================================="
# #!/usr/bin/env bash
# set -euo pipefail

# # Spin up services
# gitea-up
# minikube-up

# echo "🔗 Bridging Gitea to the Minikube network bridge..."
# # Safely connect if not already connected
# if ! docker network inspect minikube | grep -q "${GIT_SERVICE_NAME}"; then
#   docker network connect minikube "${GIT_SERVICE_NAME}"
# fi

# echo "=================================================="
# echo " ✅ Success: Infrastructure is up and bridged."
# echo "=================================================="
