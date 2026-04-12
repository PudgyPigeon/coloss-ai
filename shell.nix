{pkgs}: let
  repoApps = import ./nix/apps.nix {inherit pkgs;};
  # Extract the program path from your CI factory
  sync-bin = repoApps.ci.apps.sync-sandbox.program;

  # --- Configuration Variables ---
  clusterName = "sandbox-cluster";
  gitServiceName = "sandbox-gitea";
  gitPort = "3000";
  gitUser = "admin";
  gitPass = "placeholder";
  nodeCount = toString 1;

  openWebUiDestPort = "9000";
  openWebUiSourcePort = "8080";

  argoCdNamespace = "argocd";
  argocdLocalPort = "8888";
  argocdSvcPort = "443";

  kindConfig = "./.local/sandbox-config.yaml";
  kubeconfig = "./kind-kubeconfig.yaml";

  argocd-creds = pkgs.writeShellScriptBin "argocd-creds" ''
    set -e
    PASS=$(kubectl -n ${argoCdNamespace} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "--------------------------------------------------"
    echo " You can log into your localhost cluster ArgoCD Portal:"
    echo "👤 User: admin"
    echo "🔑 Pass: $PASS"
    echo "🌐 URL:  https://localhost:${argocdLocalPort}"
    echo "--------------------------------------------------"
  '';

  # 1. Infrastructure Layer
  gitea-up = pkgs.writeShellScriptBin "gitea-up" ''
    set -e
    if [ ! "$(docker ps -aq -f name=${gitServiceName})" ]; then
      echo "🚀 Starting Git Service with Push-to-Create enabled..."

      # We use GITEA__SECTION__KEY to inject the app.ini settings directly
      docker run -d --name ${gitServiceName} -p ${gitPort}:3000 -p 2222:22 --restart=always \
        -e GITEA__database__DB_TYPE=sqlite3 \
        -e GITEA__security__INSTALL_LOCK=true \
        -e GITEA__repository__ENABLE_PUSH_CREATE_USER=true \
        -e GITEA__repository__ENABLE_PUSH_CREATE_ORG=true \
        -e USER_UID=1000 \
        -e USER_GID=1000 \
        gitea/gitea:latest

      echo "⏳ Waiting for Gitea to be ready..."
      until docker exec ${gitServiceName} curl -s http://localhost:3000 > /dev/null; do
        sleep 2
      done

      echo "👤 Creating Admin User..."
      # This matches your Docker Compose logic
      docker exec -u 1000 ${gitServiceName} /usr/local/bin/gitea admin user create \
        --username "${gitUser}" \
        --password "${gitPass}" \
        --email "${gitUser}@local" \
        --admin \
        --must-change-password=false || true

      echo "✅ Gitea is ready. Push-to-Create is ACTIVE."
    fi
  '';

  minikube-up = pkgs.writeShellScriptBin "minikube-up" ''
    set -e

    if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
      echo "🎡 Starting Minikube with GPU support..."

      minikube start \
        --driver=docker \
        --container-runtime=docker \
        --gpus=nvidia.com \
        --nodes=${nodeCount} \
        --kubernetes-version=stable \
        --force-systemd=true

    fi

    echo "✅ Minikube is UP."
  '';

  infra-up = pkgs.writeShellScriptBin "infra-up" ''
    set -e
    gitea-up
    minikube-up

    echo "🔗 Bridging Gitea to the Minikube network..."
    docker network connect minikube ${gitServiceName}

    echo "✅ Infrastructure is bridged."
  '';

  # 2. Management Layer
  argocd-up = pkgs.writeShellScriptBin "argocd-up" ''
    set -e
    kubectl create namespace ${argoCdNamespace} --dry-run=client -o yaml | kubectl apply -f -

    # Install ArgoCD via Helm
    for i in 1 2; do
      ${pkgs.kubernetes-helm}/bin/helm template argocd ./helm/mgmt/argocd \
        --namespace ${argoCdNamespace} \
        -f ./helm/values/sandbox/argocd.yaml \
        --set global.namespaceScoped=true --include-crds \
        | kubectl apply --server-side --force-conflicts -n ${argoCdNamespace} -f - \
        || true

      sleep 5
    done

    kubectl wait --for=condition=Available deployment/argocd-server -n ${argoCdNamespace} --timeout=300s

    pkill -f "port-forward svc/argocd-server" || true
    kubectl port-forward svc/argocd-server -n ${argoCdNamespace} ${argocdLocalPort}:${argocdSvcPort} > /dev/null 2>&1 &

    argocd-creds
  '';

  # 3. The Sync Script (Calling your sync-bin)
  sync-helm = pkgs.writeShellScriptBin "sync-helm" ''
    set -e
    echo "🔄 Calling CI Sync Binary..."

    # We pass the Gitea URL directly to your pre-defined sync binary
    # Adjust arguments based on what your sync-bin expects
    ${sync-bin} "http://${gitUser}:${gitPass}@localhost:${gitPort}/${gitUser}/manifests.git"
  '';

  expose = pkgs.writeShellScriptBin "expose" ''
    pkill -f "kubectl port-forward"
    kubectl port-forward svc/argocd-server -n ${argoCdNamespace} ${argocdLocalPort}:${argocdSvcPort} > /dev/null 2>&1 &
    kubectl port-forward -n open-webui svc/open-webui ${openWebUiDestPort}:${openWebUiSourcePort} > /dev/null 2>&1 &
  '';

  up = pkgs.writeShellScriptBin "up" ''
    infra-up
    argocd-up
    sync-helm
    expose
  '';

  down = pkgs.writeShellScriptBin "down" ''
    pkill -f "port-forward svc/argocd-server" || true
    minikube delete || true
    docker rm -f ${gitServiceName} || true
    rm -f ${kubeconfig}
  '';

  helm-deps-update = pkgs.writeShellScriptBin "helm-deps-update" ''
    set -e
    echo "🔍 Searching for Helm charts in ./helm ..."

    # Find all directories containing a Chart.yaml
    CHARTS=$(find ./helm -name "Chart.yaml" -exec dirname {} \;)

    for chart in $CHARTS; do
      echo "--------------------------------------------------"
      echo "📦 Updating dependencies for: $chart"
      ${pkgs.kubernetes-helm}/bin/helm dependency build "$chart"
    done

    echo "--------------------------------------------------"
    echo "✅ All Helm dependencies are up to date."
  '';

  sandbox-help = pkgs.writeShellScriptBin "sandbox-help" ''
    echo -e "\033[1;34m--- 🛠️  Sandbox Commands ---\033[0m"
    printf "\033[1;32m%-15s\033[0m %s\n" "up"           "Run full setup (Infra + ArgoCD)"
    printf "\033[1;32m%-15s\033[0m %s\n" "gitea-up"     "Provision Gitea"
    printf "\033[1;32m%-15s\033[0m %s\n" "minikube-up"  "Provision MiniKube"
    printf "\033[1;32m%-15s\033[0m %s\n" "infra-up"     "Provision Gitea and Minikube"
    printf "\033[1;32m%-15s\033[0m %s\n" "argocd-up"    "Install ArgoCD and tunnel to ${argocdLocalPort}"
    printf "\033[1;32m%-15s\033[0m %s\n" "argocd-creds" "Display credentials for port ${argocdLocalPort}"
    printf "\033[1;32m%-15s\033[0m %s\n" "helm-deps-update" "Update helm chart deps in this repo recursively"
    printf "\033[1;32m%-15s\033[0m %s\n" "sync-helm"         "OCI Hydrate -> Local Push -> Argo Sync"
    printf "\033[1;32m%-15s\033[0m %s\n" "sync-helm --dry-run" "Preview hydrated YAML structure"
    printf "\033[1;32m%-15s\033[0m %s\n" "expose" "Port forward local host services"
    printf "\033[1;32m%-15s\033[0m %s\n" "down"         "Nuke everything (Cluster)"
    echo -e "\033[1;34m----------------------------\033[0m"
  '';
in
  pkgs.mkShell {
    buildInputs = [
      pkgs.minikube
      pkgs.kubectl
      pkgs.kubernetes-helm
      pkgs.argocd
      pkgs.git
      pkgs.curl
      up
      gitea-up
      minikube-up
      infra-up
      argocd-creds
      argocd-up
      sync-helm
      helm-deps-update
      expose
      sandbox-help
      down
    ];
    # Note: It looks like it's not formatted correctly below but when you run 'nix develop' the box is lined up
    # so best left alone for aesthetics
    shellHook = ''
      export KUBECONFIG="$HOME/.kube/config"

      # Check if infra is actually up
      CLUSTER_STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null | grep "Running" || true)

      echo -e "\n\033[1;36m┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ \033[0m"
      if [[ -n "$CLUSTER_STATUS" ]]; then
          echo -e "\033[1;36m┃ 🚀 Sandbox Shell: \033[1;32mONLINE\033[1;36m                              ┃\033[0m"
          echo -e "\033[1;36m┃ ArgoCD: localhost:${argocdLocalPort}                                ┃\033[0m"
      else
          echo -e "\033[1;36m┃ 🚀 Sandbox Shell: \033[1;33mREADY TO START\033[1;36m                      ┃\033[0m"
      fi
      echo -e "\033[1;36m┃ Run '\033[1;32mup\033[1;36m' to provision your local infrastructure.      ┃\033[0m"
      echo -e "\033[1;36m┃ Type '\033[1;33msandbox-help\033[1;36m' to see available commands.        ┃\033[0m"
      echo -e "\033[1;36m┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m\n"

      alias k="kubectl"
      alias s-help="sandbox-help"

      if command -v kubectl >/dev/null; then
        source <(kubectl completion bash | sed 's/kubectl/k/g')
      fi
    '';
  }
