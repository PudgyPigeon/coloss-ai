#!/usr/bin/env bash
set -euo pipefail

: "${CPU_COUNT:=4}"
: "${MEM_COUNT:=8192}"
: "${NODE_COUNT:=1}"
: "${ENV_NAME:=dev}"

if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "=================================================="
  echo " 🎡 Starting Minikube ${ENV_NAME} environment..."
  echo "=================================================="
  
  minikube start \
    --driver=docker \
    --container-runtime=docker \
    --gpus nvidia.com \
    --cpus "${CPU_COUNT}" \
    --memory "${MEM_COUNT}" \
    --nodes "${NODE_COUNT}" \
    --kubernetes-version=stable \
    --mount --mount-string "/usr/lib/wsl:/usr/lib/wsl"
  # minikube start \
  #   --driver=docker \
  #   --gpus all \
  #   --cpus "${CPU_COUNT}" \
  #   --memory "${MEM_COUNT}" \
  #   --nodes "${NODE_COUNT}" \
  #   --kubernetes-version=stable \
  #   --mount --mount-string "/usr/lib/wsl:/usr/lib/wsl" 
    # mount command is hacky just to get it working with WSL NixOS 26.05 since
    # something janky happened to nvidia drivers after beta update

  echo "🔌 Enabling NVIDIA Device Plugin for Kubernetes..."
  minikube addons enable nvidia-device-plugin
else
  echo "🎡 Minikube is already running."
fi

# Ensure the addon is active even if Minikube was already running
if ! minikube addons list -o json | grep -q '"nvidia-device-plugin":true'; then
  minikube addons enable nvidia-device-plugin
fi

echo "✅ Success: Minikube is active with GPU support."

#sudo nvidia-ctk runtime configure --runtime=docker
# sudo systemctl restart docker
# #!/usr/bin/env bash
# set -euo pipefail

# if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
#   echo "=================================================="
#   echo " 🎡 Starting Minikube ${ENV_NAME} environment..."
#   echo "=================================================="

#   minikube start \
#     --driver=docker \
#     --container-runtime=docker \
#     --gpus=nvidia.com \
#     --cpus "${CPU_COUNT}" \
#     --memory "${MEM_COUNT}" \
#     --nodes "${NODE_COUNT}" \
#     --kubernetes-version=stable \
#     --force-systemd=true
# else
#   echo "🎡 Minikube is already running."
# fi

# echo "✅ Success: Minikube is active."
